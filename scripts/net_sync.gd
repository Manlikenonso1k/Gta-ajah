extends Node
## Online play inside the game world (added by main.gd when Net is online).
##
## About 12 times a second it sends this player's position, animation and, when
## driving, the car's transform. For every other player it keeps a
## RemotePlayer puppet, and while they drive it moves the matching car here:
## a parked car with the same persistent id (every phone builds the same city
## and parked cars), or a stand-in copy of the model for cars that only exist
## on their phone (traffic). A car driven by someone else is frozen
## (kinematic) on this phone, follows their transform and can't be entered.

const RemotePlayer = preload("res://scripts/remote_player.gd")
const Car = preload("res://scripts/car.gd")

const SEND_INTERVAL := 1.0 / 12.0
## Remote players that send nothing for this long are removed
const STALE_TIME := 10.0
const REMOTE_META := "net_remote_driver"

var main: Node3D
var player: CharacterBody3D

var _send_timer := 0.0
var _puppets := {}      # id -> RemotePlayer
var _last_seen := {}    # id -> seconds since their last message
var _cars := {}         # id -> car node they drive here
var _car_targets := {}  # id -> {xform, vel, since}
var _ghosts := {}       # id -> true when _cars[id] is a stand-in we spawned
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Net.message.connect(_on_message)
	Net.peer_left.connect(_remove_peer)
	Net.disconnected.connect(_on_disconnected)


func set_status_label(label: Label) -> void:
	_status = label
	_update_status()


func player_count() -> int:
	return _puppets.size() + 1


func _process(delta: float) -> void:
	if not Net.online():
		return
	_send_timer += delta
	if _send_timer >= SEND_INTERVAL and player != null:
		_send_timer = 0.0
		Net.send(_local_state())
	for id: int in _last_seen.keys():
		_last_seen[id] += delta
		if _last_seen[id] > STALE_TIME:
			_remove_peer(id)
	for id: int in _cars.keys():
		_move_remote_car(id, delta)


func _local_state() -> Dictionary:
	var anim := "idle"
	var state: int = player.interaction_state
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if state == player.InteractionState.RAGDOLL:
		anim = "down"
	elif not player.is_on_floor():
		anim = "air"
	elif speed > 2.2:
		anim = "run"
	elif speed > 0.15:
		anim = "walk"
	var p: Vector3 = player.global_position
	var data := {"t": "state", "n": Net.player_name, "p": _round3(p), "y": snappedf(player.rotation.y, 0.001), "s": snappedf(speed, 0.01), "a": anim}
	var car: Node3D = player.car
	if car != null and is_instance_valid(car) and state == player.InteractionState.DRIVING:
		var q := car.global_basis.get_rotation_quaternion()
		var v: Vector3 = car.linear_velocity
		data["c"] = {"k": car.persistent_id, "m": car.model, "x": _round3(car.global_position), "q": [snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)], "v": _round3(v)}
		# Seen from outside, the player is where the car is
		data["p"] = _round3(car.global_position)
	return data


func _on_message(from_id: int, data: Dictionary) -> void:
	if str(data.get("t", "")) != "state":
		return
	_last_seen[from_id] = 0.0
	var puppet: Node3D = _puppets.get(from_id)
	if puppet == null:
		puppet = RemotePlayer.new()
		puppet.peer_id = from_id
		puppet.name = "RemotePlayer_%d" % from_id
		main.add_child(puppet)
		_puppets[from_id] = puppet
		_update_status()
	puppet.display_name = str(data.get("n", "Player"))
	puppet.apply_state(data)
	var car_data: Variant = data.get("c")
	if car_data is Dictionary:
		_drive_remote_car(from_id, car_data)
	elif _cars.has(from_id):
		_release_car(from_id)


## The car that player drives here: theirs by persistent id, else a stand-in.
func _drive_remote_car(id: int, c: Dictionary) -> void:
	var key := str(c.get("k", ""))
	var car: Node3D = _cars.get(id)
	if car != null and (not is_instance_valid(car) or (key != "" and car.persistent_id != key) or (key == "" and not _ghosts.has(id))):
		_release_car(id)
		car = null
	var x: Array = c.get("x", [0, 0, 0])
	var q: Array = c.get("q", [0, 0, 0, 1])
	var v: Array = c.get("v", [0, 0, 0])
	var xform := Transform3D(Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized()), Vector3(float(x[0]), float(x[1]), float(x[2])))
	if car == null:
		if key != "":
			for candidate in get_tree().get_nodes_in_group("persistent_vehicles"):
				if candidate.persistent_id == key:
					car = candidate
					break
		if car != null and car == player.car:
			# Both took the same car at once: the lower id keeps it. The other
			# phone sees this one's claim and puts its player out on foot.
			if Net.my_id < id:
				return
			if player.interaction_state == player.InteractionState.DRIVING:
				player.begin_exit_car(car, car.to_global(car.driver_door_point()))
		if car == null:
			car = Car.new()
			car.model = str(c.get("m", "corolla"))
			car.name = "RemoteCar_%d" % id
			car.transform = xform
			main.add_child(car)
			_ghosts[id] = true
		_cars[id] = car
		car.set_meta(REMOTE_META, id)
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
		car.global_transform = xform
	_car_targets[id] = {"xform": xform, "vel": Vector3(float(v[0]), float(v[1]), float(v[2])), "since": 0.0}


func _move_remote_car(id: int, delta: float) -> void:
	var car: Node3D = _cars[id]
	if not is_instance_valid(car):
		_cars.erase(id)
		return
	var target: Dictionary = _car_targets.get(id, {})
	if target.is_empty():
		return
	target["since"] += delta
	var xform: Transform3D = target["xform"]
	var vel: Vector3 = target["vel"]
	var aim := xform.origin + vel * minf(target["since"], 0.25)
	var k := clampf(14.0 * delta, 0.0, 1.0)
	var t: Transform3D = car.global_transform
	if t.origin.distance_to(aim) > 15.0:
		t.origin = aim
	else:
		t.origin = t.origin.lerp(aim, k)
	t.basis = Basis(t.basis.get_rotation_quaternion().slerp(xform.basis.get_rotation_quaternion(), k))
	car.global_transform = t
	car.freeze = true
	# A frozen body reports no velocity; the bumper uses this to knock people down
	car.set_meta("net_velocity", vel)


## They stopped driving it (or left): the car stays where it is and is
## simulated here again; a stand-in disappears.
func _release_car(id: int) -> void:
	var car: Node3D = _cars.get(id)
	_cars.erase(id)
	_car_targets.erase(id)
	var ghost := _ghosts.has(id)
	_ghosts.erase(id)
	if car == null or not is_instance_valid(car):
		return
	if ghost:
		car.queue_free()
		return
	car.remove_meta(REMOTE_META)
	car.remove_meta("net_velocity")
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = false


func _remove_peer(id: int) -> void:
	if _cars.has(id):
		_release_car(id)
	var puppet: Node = _puppets.get(id)
	if puppet != null and is_instance_valid(puppet):
		puppet.queue_free()
	_puppets.erase(id)
	_last_seen.erase(id)
	_update_status()


func _on_disconnected(reason: String) -> void:
	for id: int in _puppets.keys():
		_remove_peer(id)
	if _status != null:
		_status.text = "OFFLINE  •  " + reason
		_status.modulate = Color(1.0, 0.55, 0.45)


func _update_status() -> void:
	if _status == null:
		return
	var where := "WI-FI HOST" if Net.mode == Net.Mode.HOST else "ONLINE"
	var text := "%s  •  %d player%s" % [where, player_count(), "" if player_count() == 1 else "s"]
	if Net.mode == Net.Mode.HOST:
		var addresses := Net.lan_addresses()
		if not addresses.is_empty():
			text += "  •  join: " + ", ".join(addresses)
	_status.text = text
	_status.modulate = Color(0.6, 1.0, 0.75)


static func _round3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
