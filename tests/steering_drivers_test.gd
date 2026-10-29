extends SceneTree
## People in moving cars, and the realistic player, in the real game scene.
## Run: godot --headless --path . --script tests/steering_drivers_test.gd
##
## Checks: every moving AI car has a seated driver who is visible up close
## (and the distance LOD: fixed pose at 80 m, hidden at 150 m); danfos carry
## passengers; parked cars stay empty; the player's ragdoll is the realistic
## model (no stick figure) and GetUp plays afterwards; the realistic player
## drives with both hands on the rim while the wheel turns, and gets out again.

const VehiclePersistence = preload("res://scripts/vehicle_persistence.gd")
const RealisticRagdoll = preload("res://scripts/realistic_ragdoll.gd")
const VehicleOccupants = preload("res://scripts/vehicle_occupants.gd")
const Registry = preload("res://scripts/pedestrian_registry.gd")

var main: Node3D
var _failures: Array[String] = []


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func():
		push_error("steering_drivers_test timed out")
		quit(2))
	VehiclePersistence.SAVE_PATH = "user://steering_drivers_state.json"
	VehiclePersistence.TEMP_PATH = "user://steering_drivers_state.json.tmp"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _run() -> void:
	await _frames(120)
	# Make sure both danfo models drive (the default traffic may be all cars)
	var traffic_node: Node = null
	for child in main.get_children():
		if child.has_method("spawn_car"):
			traffic_node = child
	_check(traffic_node != null, "traffic node not found")
	if traffic_node != null:
		for danfo in ["vw_t3", "hiace"]:
			var spot: Dictionary = traffic_node._free_spot()
			if not spot.is_empty():
				traffic_node.spawn_car(spot.lane, spot.distance, danfo, true)
	await _frames(10)
	_check_traffic()
	_check_parked()
	await _check_player_ragdoll()
	await _check_player_driving()
	for path in [VehiclePersistence.SAVE_PATH, VehiclePersistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures.is_empty():
		print("Drivers, passengers and realistic player checks passed.")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		quit(1)


func _check_traffic() -> void:
	var traffic := get_nodes_in_group("traffic")
	_check(not traffic.is_empty(), "no traffic cars spawned")
	var categories := {}
	var camera := Camera3D.new()
	root.add_child(camera)
	var game_camera := root.get_viewport().get_camera_3d()
	camera.make_current()
	for car: Node3D in traffic:
		var occ: Node3D = car.occupants
		var label := "%s (%s)" % [car.persistent_id, car.model]
		if occ == null or occ.driver == null:
			_failures.append("%s has no driver" % label)
			continue
		var id := str(occ.driver.model.get_meta("character_id", ""))
		var entry := Registry.by_id(id)
		categories[entry.get("appearance_category", "?")] = categories.get(entry.get("appearance_category", "?"), 0) + 1
		# The detail flag decides first; check with the car treated as near
		var detail: bool = car.get_meta("traffic_detail", true)
		car.set_meta("traffic_detail", true)
		for probe in [[8.0, VehicleOccupants.Lod.FULL, true], [80.0, VehicleOccupants.Lod.FIXED, true], [150.0, VehicleOccupants.Lod.HIDDEN, false]]:
			camera.global_position = car.global_position + Vector3(probe[0], 3.0, 0.0)
			occ._refresh_lod(true)
			_check(occ.lod == probe[1], "%s: at %d m LOD is %d, expected %d" % [label, probe[0], occ.lod, probe[1]])
			_check(occ.driver.seat_node.is_visible_in_tree() == probe[2], "%s: driver visible=%s at %d m" % [label, not probe[2], probe[0]])
		# Up close the driver's hands are on the rim
		camera.global_position = car.global_position + Vector3(8.0, 3.0, 0.0)
		occ._refresh_lod(true)
		occ._pose_driver(0.0)
		for side in ["Left", "Right"]:
			var err: float = occ.driver.rim_error(side)
			_check(err <= 0.03, "%s: AI driver's %s palm %.3f m off the rim" % [label, side, err])
		car.set_meta("traffic_detail", detail)
		occ._refresh_lod(true)
		if car.model in VehicleOccupants.PASSENGER_MODELS:
			_check(occ.passengers.size() >= 2, "%s: a danfo should carry passengers, has %d" % [label, occ.passengers.size()])
		print("%s: driver %s, %d passengers" % [label, id, occ.passengers.size()])
	print("traffic driver categories: ", categories)
	camera.queue_free()
	if game_camera != null:
		game_camera.make_current()


func _check_parked() -> void:
	for car: Node3D in get_nodes_in_group("cars"):
		if car.is_in_group("traffic"):
			continue
		_check(car.occupants == null or car.occupants.people().is_empty(), "parked %s has people in it" % car.persistent_id)


func _check_player_ragdoll() -> void:
	var player = main._player
	var model: Node3D = player._model
	_check(model != null and player._loco != null, "player has no realistic model")
	if model == null:
		return
	player.go_ragdoll(Vector3(3, 2, 0))
	await _frames(10)
	var ragdolls := get_nodes_in_group("ragdolls")
	_check(player._ragdoll != null and player._ragdoll.get_script() == RealisticRagdoll, "player ragdoll is not the realistic ragdoll")
	_check(player._ragdoll != null and player._ragdoll.model == model, "player ragdoll does not use the player's model")
	for r in ragdolls:
		_check(r.get_script() == RealisticRagdoll, "a stick-figure ragdoll was spawned (%s)" % r.name)
	_check(player._ragdoll_pelvis is RigidBody3D, "player._ragdoll_pelvis should be the ragdoll's pelvis body")
	# Down for RAGDOLL_TIME minus the GetUp clip, then GetUp
	var saw_get_up := false
	for i in 300:
		await physics_frame
		if player._getting_up and player._loco.is_action_playing():
			saw_get_up = true
		if player.interaction_state == player.InteractionState.ON_FOOT:
			break
	_check(saw_get_up, "GetUp clip did not play after the ragdoll")
	_check(player.interaction_state == player.InteractionState.ON_FOOT, "player did not get back up")
	_check(model.get_parent() == player._visual, "player model was not taken back from the ragdoll")
	_check(get_nodes_in_group("ragdolls").is_empty(), "ragdoll left behind after getting up")
	print("player ragdoll: realistic, GetUp played: ", saw_get_up)


func _check_player_driving() -> void:
	for t in get_nodes_in_group("traffic"):
		t.queue_free()
	await _frames(2)
	var player = main._player
	var car: VehicleBody3D
	for candidate in get_nodes_in_group("cars"):
		if candidate.persistent_id == "corolla_000":
			car = candidate
	if car == null:
		_failures.append("starter Corolla missing")
		return
	car.global_transform = car.original_spawn_transform
	car.linear_velocity = Vector3.ZERO
	main._update_streaming()
	player.global_position = car.global_position + car.global_basis.x * 1.5
	await _frames(3)
	player._try_enter_car()
	for i in 360:
		await physics_frame
		if player.car == car:
			break
	_check(player.car == car, "player did not get into the car")
	if player.car != car:
		return
	var occ: Node3D = car.occupants
	# The car is the player's as soon as he sits down; wait for the sit-down
	for i in 180:
		if not occ.is_busy():
			break
		await physics_frame
	_check(not occ.is_busy(), "sitting down did not finish")
	_check(occ.player_seated and occ.driver != null and occ.driver.model == player._model, "the realistic player is not the seated driver")
	_check(car._driver_limbs.is_empty(), "the procedural stick driver is still shown")
	var angles := {}
	for dir in ["move_left", "move_right"]:
		Input.action_press(dir)
		await _frames(40)
		angles[dir] = occ.wheel_angle
		var wheel: Node3D = car._steering_wheel
		var turned := not wheel.basis.is_equal_approx(Basis.IDENTITY)
		_check(turned, "steering wheel did not turn for %s" % dir)
		for side in ["Left", "Right"]:
			var err: float = occ.driver.rim_error(side)
			_check(err <= 0.03, "player's %s palm %.3f m off the rim while %s (slide %.3f, hand turn %.2f, weight %.2f, steer %.2f, lod %d)" % [
				side, err, dir, occ.driver.seat_slide, occ.driver.hand_turn[side], occ.driver.hand_weight, occ.steer_fraction, occ.lod])
			if err > 0.03:
				var p = occ.driver
				var sh: Vector3 = p._vehicle_point(p._bones[side + "UpperArm"])
				var target: Vector3 = p._wrist_target_turn(side, p.hand_turn[side])
				print("   DIAG shoulder %s target %s d %.3f wrist %s elbow %s scale %.3f model %s seat %s base %s action %s" % [
					sh.snappedf(0.001), target.snappedf(0.001), sh.distance_to(target), p._vehicle_point(p._bones[side + "Hand"]).snappedf(0.001),
					p._vehicle_point(p._bones[side + "LowerArm"]).snappedf(0.001), p._scale(), p.model.transform, p.seat_node.transform.origin,
					(p.loco.tree.tree_root.get_node("move").get_blend_point_node(0) as AnimationNodeAnimation).animation, p.loco.is_action_playing()])
				p.pose(occ.wheel_angle, occ.steer_fraction, 0.0)
				print("   DIAG after a fresh pose(): err %.3f" % p.rim_error(side))
		Input.action_release(dir)
	_check(angles["move_left"] > 0.2 and angles["move_right"] < -0.2, "wheel angle should follow steering both ways: %s" % [angles])
	print("player driving: wheel angle left %.2f rad, right %.2f rad" % [angles["move_left"], angles["move_right"]])
	await _frames(30)
	Input.action_press("interact")
	await _frames(5)
	Input.action_release("interact")
	for i in 360:
		await physics_frame
		if player.car == null and player.interaction_state == player.InteractionState.ON_FOOT:
			break
	_check(player.car == null and player.visible, "player did not get out")
	_check(player._model.get_parent() == player._visual, "player model not back on the player after getting out")
	_check(not occ.player_seated and occ.driver == null, "car still has the player seated")
	print("player exit: on foot at ", player.global_position.snappedf(0.01))
