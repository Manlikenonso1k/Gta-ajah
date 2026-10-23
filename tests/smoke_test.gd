extends SceneTree
## Headless gameplay check: godot --headless --path . --script tests/smoke_test.gd

var main: Node3D
const VehiclePersistence = preload("res://scripts/vehicle_persistence.gd")


func _initialize() -> void:
	VehiclePersistence.SAVE_PATH = "user://smoke_vehicle_state.json"
	VehiclePersistence.TEMP_PATH = "user://smoke_vehicle_state.json.tmp"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await _frames(120)
	# Keep the collision/ragdoll test deterministic; traffic has its own test.
	for traffic in get_nodes_in_group("traffic"):
		traffic.queue_free()
	await _frames(2)
	var player = main._player
	var car: VehicleBody3D
	for candidate in get_nodes_in_group("cars"):
		if candidate.persistent_id == "corolla_000":
			car = candidate
			break
	if car == null:
		push_error("Starter Corolla was not spawned")
		quit(1)
		return
	# Start from the documented starter spawn, isolated from a player's save.
	car.global_transform = car.original_spawn_transform
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	main._update_streaming()
	print("cars: ", get_nodes_in_group("cars").size(), "  car y: ", snappedf(car.global_position.y, 0.01))

	# Ragdoll on demand, then get back up
	player.go_ragdoll(Vector3(4, 3, 0))
	await _frames(90)
	var pelvis: RigidBody3D = player._ragdoll_pelvis
	print("ragdoll pelvis y after 1.5s: ", snappedf(pelvis.global_position.y, 0.01), "  ragdolls: ", get_nodes_in_group("ragdolls").size())
	await _frames(200)
	print("player back up: ", player.visible, "  ragdolls: ", get_nodes_in_group("ragdolls").size())

	# Drive the car into a pedestrian
	player.global_position = car.global_position + Vector3(1.5, 0, 0)
	await _frames(5)
	player._try_enter_car()
	await _frames(240)
	print("driving: ", player.car == car)
	if player.car != car:
		quit(1)
		return
	Input.action_press("move_left")
	await _frames(20)
	var left_steer := car.steering
	var left_arm: float = car._driver_limbs["arm_l"].rotation.z
	Input.action_release("move_left")
	Input.action_press("move_right")
	await _frames(20)
	var right_steer := car.steering
	var right_arm: float = car._driver_limbs["arm_l"].rotation.z
	Input.action_release("move_right")
	print("driver steering pose: ", left_steer > 0.05 and right_steer < -0.05 and left_arm < right_arm)
	# Reset any turn drift so this collision check is on a straight, known path.
	car.steering = 0.0
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	var ped = load("res://scripts/pedestrian.gd").new()
	ped.colors = {"skin": Color.BROWN, "shirt": Color.WHITE, "pants": Color.BLACK}
	ped.position = car.global_position + car.global_basis.z * 5.0 + Vector3(0, 0.2, 0)
	main.add_child(ped)
	# Stand still so a random wander direction can't take it out of the car's path
	ped.set_physics_process(false)
	var before := get_nodes_in_group("ragdolls").size()
	# Cars drive along their local +Z
	Input.action_press("move_forward")
	await _frames(150)
	Input.action_release("move_forward")
	print("car speed km/h: ", roundi(car.linear_velocity.length() * 3.6), "  upright: ", car.global_basis.y.y > 0.9,
		"  driven wheel contacts: ", car._driven_contact_ratio)
	print("pedestrian ragdolled: ", get_nodes_in_group("ragdolls").size() > before, "  ped freed: ", not is_instance_valid(ped))
	Input.action_press("interact")
	await _frames(480)
	Input.action_release("interact")
	var first_exit_speed := car.linear_velocity.length()
	print("safe exit after braking: ", player.car == null and player.visible, "  vehicle speed: ", snappedf(first_exit_speed, 0.01))
	if player.car != null or first_exit_speed > 0.5:
		quit(1)
		return
	# Repeat a stationary exit, the case that used to create the overlap impulse.
	player.global_position = car.global_position + car.global_basis.x * 1.5
	await _frames(3)
	player._try_enter_car()
	await _frames(240)
	if player.car != car:
		push_error("Repeated vehicle entry did not complete")
		quit(1)
		return
	Input.action_press("interact")
	await _frames(180)
	Input.action_release("interact")
	print("repeated stationary exit launch check: ", player.car == null and car.linear_velocity.length() < 0.5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VehiclePersistence.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VehiclePersistence.TEMP_PATH))
	quit()
