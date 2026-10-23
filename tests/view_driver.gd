extends SceneTree
## Capture the procedural driver inside the starter Camry after entry.
## Run with a window: godot --path . --script tests/view_driver.gd

func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var requested_model := "camry"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		requested_model = args[0]
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(90)
	var player: Node = main._player
	var car: Node3D
	for candidate in get_nodes_in_group("cars"):
		if candidate.model == requested_model:
			car = candidate
			break
	player.global_position = car.global_position + Vector3(1.5, 0.0, 0.0)
	await _frames(2)
	player._try_enter_car()
	await _frames(180)
	if player.car == null:
		push_error("Player did not complete vehicle entry")
		quit(1)
		return
	if requested_model == "sprinter":
		car.animate_driver_door(true)
		await _frames(55)
	var rig: Node3D = player.camera_rig
	rig.yaw = car.global_rotation.y + PI / 2.0
	rig.pitch = -0.08
	for frame in 30:
		await process_frame
	var directory := "user://vehicle_views/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := ProjectSettings.globalize_path(directory + "driver_%s.png" % requested_model)
	print("driver visual at: ", car._driver_visual.global_position)
	root.get_texture().get_image().save_png(path)
	print("saved driver view: ", path)
	quit()
