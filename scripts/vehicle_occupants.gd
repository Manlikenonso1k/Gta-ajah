extends Node3D
## The people inside one vehicle: a driver (an AI driver picked from the
## pedestrian registry, or the player) and, in danfos and buses, a few seated
## passengers. Each person is posed by scripts/seated_pose.gd.
##
## car.gd adds one of these to every car (empty for parked cars, which stay
## empty); traffic.gd calls fill_traffic() when it spawns an AI car; the player
## sits down and gets out through player_enter() / player_exit().
##
## Distance LOD from the camera (the spec's performance rule):
##   within FULL_DISTANCE  the clip plays, the hands follow the steering wheel
##                         and the wheel turns;
##   up to HIDE_DISTANCE   a fixed seated pose with the wheel centred;
##   beyond that, or while traffic runs the car in its frozen lightweight mode
##   (car meta "traffic_detail" false), everyone in it is hidden.

const SeatedPose = preload("res://scripts/seated_pose.gd")
const SteeringWheel = preload("res://scripts/steering_wheel.gd")
const VehicleModel = preload("res://scripts/vehicle_model.gd")
const Registry = preload("res://scripts/pedestrian_registry.gd")

const FULL_DISTANCE := 40.0
const HIDE_DISTANCE := 120.0
## How often the LOD level is re-checked (seconds)
const LOD_INTERVAL := 0.25
## Models that carry passengers when they drive in traffic (danfos and buses)
const PASSENGER_MODELS := ["vw_t3", "hiace", "town_bus", "coach"]
const ENTER_BLEND := 0.35
## Registry picks tried before giving up on a driver who fits the car
const DRIVER_PICKS := 8

enum Lod { FULL, FIXED, HIDDEN }

var car: Node3D
var cabin := {}
var driver: RefCounted
var passengers: Array = []
var player_seated := false
var lod := Lod.FULL
## The rim angle and steering fraction last posed (radians, -1..1)
var wheel_angle := 0.0
var steer_fraction := 0.0
var _wheel: Node3D
var _max_steer := 0.5
## Roof triangles above the driver's seat per model (see _roof_triangles)
static var _roofs := {}
var _lod_timer := 0.0
## Running enter/exit step, or empty
var _sequence: Dictionary = {}
## True while the player is getting in or out
var _busy := false


## Adds the occupants node to `car` (car.gd calls this in _ready).
static func attach(car_: Node3D, data: Dictionary) -> Node3D:
	var node: Node3D = new()
	node.name = "Occupants"
	node.car = car_
	node.cabin = cabin_for(car_.model, data)
	car_.add_child(node)
	node.set_process(false)
	return node


## Vehicle-space cabin geometry for seated_pose.gd: seat, heel (floor point
## the driver's heels rest on), wheel_center/axis/radius, back recline, max
## wheel turn and the passenger seats. `data` is VehicleModel.build() output.
static func cabin_for(key: String, data: Dictionary) -> Dictionary:
	var raw: Dictionary = VehicleModel.cabin(key)
	if raw.is_empty() or not data.has("steering_wheel"):
		return {}
	var sw: Dictionary = data["steering_wheel"]
	var seat: Vector3 = data["driver_seat"]
	var tilt := float(raw.get("wheel_tilt", 25.0))
	var out := {
		"seat": seat,
		"wheel_center": sw["center"],
		"wheel_axis": sw["axis"],
		"wheel_radius": float(sw["radius"]),
		"max_turn": float(sw["max_turn"]),
		# Car drivers recline about 20 degrees; bus and coach drivers sit more
		# upright behind a flatter wheel, and pull the seat right up to it
		"recline": deg_to_rad(lerpf(20.0, 5.0, clampf((tilt - 25.0) / 40.0, 0.0, 1.0))),
		"max_slide": 0.32 + clampf((tilt - 40.0) / 25.0, 0.0, 1.0) * 0.2,
	}
	if raw.has("heel"):
		var h: Array = raw["heel"]
		out["heel"] = Vector3(h[0], h[1], h[2])
	else:
		# Cars: low seat, legs stretched forward; vans and buses: upright
		var car_like := tilt < 35.0 and seat.y < 0.8
		out["heel"] = seat + (Vector3(0.0, -0.3, 0.78) if car_like else Vector3(0.0, -0.42, 0.52))
	var seats: Array[Vector3] = []
	for p: Array in raw.get("passengers", []):
		seats.append(Vector3(p[0], p[1], p[2]))
	out["passenger_seats"] = seats
	out["passenger_heel_drop"] = float(raw.get("passenger_heel_drop", 0.42))
	return out


## Adds the roof over the driver's seat to `cabin` the first time somebody
## sits in this vehicle (parked cars that nobody drives never pay for it).
func _ensure_roof() -> void:
	if cabin.is_empty() or cabin.has("roof_triangles"):
		return
	cabin["roof_triangles"] = _roof_triangles(car.model, VehicleModel.build(car.model), cabin["seat"])


## Body triangles over the driver's seat (roof, headliner, frame), three
## points each, that a head could touch; seated_pose.gd keeps the crown below
## them. Once per model.
static func _roof_triangles(key: String, data: Dictionary, seat: Vector3) -> PackedVector3Array:
	if _roofs.has(key):
		return _roofs[key]
	var tris := PackedVector3Array()
	var lo := Vector2(seat.x - 0.45, seat.z - 0.7)
	var hi := Vector2(seat.x + 0.45, seat.z + 0.6)
	for part: Array in data["body"]:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		for t in range(0, idx.size() - 2, 3):
			var a := xf * verts[idx[t]]
			var b := xf * verts[idx[t + 1]]
			var c := xf * verts[idx[t + 2]]
			if maxf(a.y, maxf(b.y, c.y)) < seat.y + 0.45:
				continue
			# Bounding box of the triangle overlaps the area over the seat
			if minf(a.x, minf(b.x, c.x)) > hi.x or maxf(a.x, maxf(b.x, c.x)) < lo.x:
				continue
			if minf(a.z, minf(b.z, c.z)) > hi.y or maxf(a.z, maxf(b.z, c.z)) < lo.y:
				continue
			tris.append(a)
			tris.append(b)
			tris.append(c)
	_roofs[key] = tris
	return tris


## Puts an AI driver (and, in danfos and buses, passengers) into a traffic
## car. Characters come from the pedestrian registry with its 90/10 mix.
func fill_traffic(rng: RandomNumberGenerator) -> void:
	if cabin.is_empty():
		return
	for i in DRIVER_PICKS:
		if add_driver(Registry.choose(rng)):
			break
	if car.model in PASSENGER_MODELS:
		var seats: Array = cabin["passenger_seats"].duplicate()
		var want := mini(rng.randi_range(2, 4), seats.size())
		# Shuffle the free seats so danfos fill differently
		for i in range(seats.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap = seats[i]
			seats[i] = seats[j]
			seats[j] = swap
		for i in want:
			add_passenger(Registry.choose(rng), seats[i])
	_refresh_lod(true)


## Seats a registry character as the driver. Returns false if its model can't
## be posed (no standard skeleton) or is too tall for the car's roof.
func add_driver(entry: Dictionary) -> bool:
	_ensure_roof()
	var model := _instance(entry)
	if model == null:
		return false
	var pose := SeatedPose.create(car, model, cabin, true)
	if pose == null:
		if is_instance_valid(model):
			model.free()
		return false
	pose.fit_reach()
	if not pose.fits():
		pose.release().free()
		return false
	driver = pose
	pose.model.set_meta("character_id", entry.get("id", ""))
	set_process(true)
	return true


func add_passenger(entry: Dictionary, seat: Vector3) -> bool:
	var model := _instance(entry)
	if model == null:
		return false
	var seat_cabin := cabin.duplicate()
	seat_cabin["seat"] = seat
	seat_cabin["heel"] = seat + Vector3(0.0, -float(cabin.get("passenger_heel_drop", 0.42)), 0.45)
	seat_cabin["recline"] = deg_to_rad(12.0)
	var pose := SeatedPose.create(car, model, seat_cabin, false)
	if pose == null:
		model.free()
		return false
	pose.model.set_meta("character_id", entry.get("id", ""))
	passengers.append(pose)
	set_process(true)
	return true


## Everyone seated (driver first).
func people() -> Array:
	var out: Array = []
	if driver != null:
		out.append(driver)
	out.append_array(passengers)
	return out


## True while the steering wheel should turn with the steering (car.gd asks).
func wheel_live() -> bool:
	return lod == Lod.FULL


## True while the player is sitting down or getting out.
func is_busy() -> bool:
	return _busy


# --- the player getting in and out --------------------------------------------

## Seats the player's `model` (with its own Locomotion `loco`): starting
## outside at `door_point` (vehicle space, on the ground) it sits down with
## Sit_Enter while moving onto the seat, then takes the wheel. Await it.
func player_enter(model: Node3D, loco: RefCounted, door_point: Vector3) -> void:
	_ensure_roof()
	var pose := SeatedPose.create(car, model, cabin, true, loco)
	if pose == null:
		return
	_busy = true
	pose.fit_reach()
	driver = pose
	player_seated = true
	set_process(true)
	lod = Lod.FULL
	var seated := model.transform
	var start := Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(model.scale), pose.seat_node.to_local(car.to_global(door_point)))
	# Standing at the door, back to the seat: sit down (the one-shot fades in
	# from standing), and once it has, the seated Driving pose becomes the base
	# the sit-down fades out into.
	pose.clear_overrides()
	pose.set_base("")
	var length: float = loco.play_action("Sit_Enter")
	pose.hand_weight = 0.0
	pose.leg_weight = 0.0
	model.transform = start
	await _run_sequence({"pose": pose, "from": start, "to": seated, "length": maxf(length, 0.5), "turn_from": 0.45, "turn_to": 1.0,
		"base_at": 0.25, "base": pose.clip})
	# Hands and feet settle onto the wheel and floor
	await _run_sequence({"pose": pose, "blend_in": ENTER_BLEND})
	_busy = false


## Gets the player's model out: hands off the wheel, turn to the door, stand
## up with Sit_Exit while moving out to `door_point`. Returns the model, still
## parented to the car at the door point; the player takes it back.
func player_exit(door_point: Vector3) -> Node3D:
	# An exit asked for while still sitting down waits for that to finish
	while _busy and is_inside_tree():
		await get_tree().process_frame
	if driver == null or not player_seated:
		return null
	_busy = true
	var pose: RefCounted = driver
	await _run_sequence({"pose": pose, "blend_out": 0.25})
	var model: Node3D = pose.model
	var seated := model.transform
	var finish := Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(model.scale), pose.seat_node.to_local(car.to_global(door_point)))
	# Stand up (fading in from the seated base); switch the base back to
	# standing before the one-shot fades out into it.
	pose.clear_overrides()
	var length: float = pose.loco.play_action("Sit_Exit")
	await _run_sequence({"pose": pose, "from": seated, "to": finish, "length": maxf(length, 0.5), "turn_from": 0.0, "turn_to": 0.5,
		"base_at": maxf(length - 0.45, 0.2), "base": ""})
	driver = null
	player_seated = false
	_busy = false
	set_process(not passengers.is_empty())
	return pose.release()


func _run_sequence(seq: Dictionary) -> void:
	seq["t"] = 0.0
	_sequence = seq
	set_process(true)
	while not _sequence.is_empty():
		await get_tree().process_frame
		if not is_inside_tree():
			return


func _step_sequence(delta: float) -> void:
	var seq := _sequence
	var pose: RefCounted = seq["pose"]
	seq["t"] = float(seq["t"]) + delta
	var t: float = seq["t"]
	if seq.has("blend_in") or seq.has("blend_out"):
		var span: float = seq.get("blend_in", seq.get("blend_out", 0.3))
		var k := clampf(t / span, 0.0, 1.0)
		var w := k if seq.has("blend_in") else 1.0 - k
		pose.hand_weight = w
		pose.leg_weight = w
		_pose_driver(delta)
		if k >= 1.0:
			_sequence = {}
		return
	var length: float = seq["length"]
	if seq.has("base_at") and t >= float(seq["base_at"]):
		pose.set_base(String(seq["base"]))
		seq.erase("base_at")
	var k := clampf(t / length, 0.0, 1.0)
	var from: Transform3D = seq["from"]
	var to: Transform3D = seq["to"]
	var move := smoothstep(0.0, 1.0, k)
	var turn := smoothstep(float(seq["turn_from"]), float(seq["turn_to"]), k)
	var scale := from.basis.get_scale()
	var yaw_from := from.basis.orthonormalized().get_euler().y
	var yaw_to := to.basis.orthonormalized().get_euler().y
	pose.model.transform = Transform3D(Basis(Vector3.UP, lerp_angle(yaw_from, yaw_to, turn)).scaled(scale), from.origin.lerp(to.origin, move))
	pose.loco.advance(delta)
	if k >= 1.0:
		_sequence = {}


# --- per frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if driver != null:
		_read_steering()
	if not _sequence.is_empty():
		_step_sequence(delta)
		return
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = LOD_INTERVAL
		_refresh_lod(false)
	if lod != Lod.FULL:
		return
	_pose_driver(delta)
	for p: RefCounted in passengers:
		p.pose(0.0, 0.0, delta)


func _pose_driver(delta: float) -> void:
	if driver == null:
		return
	_read_steering()
	driver.pose(wheel_angle, steer_fraction, delta)


func _read_steering() -> void:
	if _wheel == null:
		_wheel = car.get("_steering_wheel")
		var handling = car.get("_handling")
		if handling is Dictionary:
			_max_steer = float(handling.get("max_steer", 0.55))
	var steering := float(car.get("steering")) if car.get("steering") != null else 0.0
	steer_fraction = clampf(steering / maxf(_max_steer, 0.001), -1.0, 1.0)
	wheel_angle = steer_fraction * float(cabin.get("max_turn", PI))


## Chooses the LOD level from the camera distance and traffic's detail flag.
func _refresh_lod(force: bool) -> void:
	if people().is_empty():
		return
	var wanted := Lod.FULL
	if player_seated:
		wanted = Lod.FULL
	elif not bool(car.get_meta("traffic_detail", true)):
		wanted = Lod.HIDDEN
	else:
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		var distance := camera.global_position.distance_to(car.global_position) if camera != null else 0.0
		if distance > HIDE_DISTANCE:
			wanted = Lod.HIDDEN
		elif distance > FULL_DISTANCE:
			wanted = Lod.FIXED
	if wanted == lod and not force:
		return
	lod = wanted
	for p: RefCounted in people():
		p.seat_node.visible = lod != Lod.HIDDEN
	if lod == Lod.FIXED:
		# A still seated pose with the wheel centred
		if _wheel == null:
			_read_steering()
		SteeringWheel.update(_wheel, 0.0, 1.0)
		if driver != null:
			driver.pose(0.0, 0.0, 0.0)
		for p: RefCounted in passengers:
			p.pose(0.0, 0.0, 0.0)


func _instance(entry: Dictionary) -> Node3D:
	var path: String = entry.get("model_path", "")
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var model: Node3D = packed.instantiate()
	model.scale = Vector3.ONE * float(entry.get("scale", 1.0))
	for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
		mesh.visibility_range_end = HIDE_DISTANCE
	return model
