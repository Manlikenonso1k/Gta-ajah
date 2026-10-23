extends SceneTree
## Headless gameplay check: godot --headless --path . --script tests/smoke_test.gd

var main: Node3D


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await _frames(120)
	var player = main._player
	var car: VehicleBody3D = get_nodes_in_group("cars")[0]
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
	await _frames(45)
	print("driving: ", player.car == car)
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
	var ped = load("res://scripts/pedestrian.gd").new()
	ped.colors = {"skin": Color.BROWN, "shirt": Color.WHITE, "pants": Color.BLACK}
	ped.position = car.global_position + car.global_basis.z * 30.0 + Vector3(0, 0.2, 0)
	main.add_child(ped)
	# Stand still so a random wander direction can't take it out of the car's path
	ped.set_physics_process(false)
	var before := get_nodes_in_group("ragdolls").size()
	# Cars drive along their local +Z
	Input.action_press("move_forward")
	await _frames(240)
	Input.action_release("move_forward")
	print("car speed km/h: ", roundi(car.linear_velocity.length() * 3.6), "  upright: ", car.global_basis.y.y > 0.9)
	print("pedestrian ragdolled: ", get_nodes_in_group("ragdolls").size() > before, "  ped freed: ", not is_instance_valid(ped))
	Input.action_press("interact")
	await _frames(480)
	Input.action_release("interact")
	print("safe exit after braking: ", player.car == null and player.visible)
	quit()
