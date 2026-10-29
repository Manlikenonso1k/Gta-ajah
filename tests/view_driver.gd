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
	# Standalone character check for the generated player model (V2). Loads the
	# model on its own, measures its world-space height, and renders a front and
	# a side view on a 0.5 m grid so the model can be eyeballed:
	#   godot --path . --script tests/view_driver.gd -- player
	if requested_model == "player":
		await _player_view()
		quit()
		return
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


## Loads assets/characters/player/player.glb on its own, prints its world-space
## size (height = y extent, feet expected at y = 0), and renders a front view
## (character faces -Z, so the camera sits on -Z and looks toward +Z) and a side
## view on a 0.5 m grid. Images go to user://vehicle_views/player_front/side.png.
func _player_view() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.85, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.2
	root.add_child(env)
	var model_path := "res://assets/characters/player/player.glb"
	if not ResourceLoader.exists(model_path):
		push_error("player model not found: " + model_path)
		return
	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	root.add_child(model)
	await process_frame
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("player AABB position ", box.position.snappedf(0.001), " size ", box.size.snappedf(0.001))
	print("player height (y) ", snappedf(box.size.y, 0.001), " m  feet y ", snappedf(box.position.y, 0.001), " m")
	var grid := _player_grid()
	root.add_child(grid)
	var center := box.get_center()
	var out := "user://vehicle_views/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var eye_y := box.position.y + box.size.y * 0.5
	var look := Vector3(center.x, eye_y, center.z)
	for view: Array in [["front", Vector3(0, 0, -3.2)], ["side", Vector3(3.2, 0, 0)]]:
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.4
		root.add_child(cam)
		cam.position = look + view[1]
		cam.look_at(look)
		cam.make_current()
		for f in 6:
			await process_frame
		var path := ProjectSettings.globalize_path(out + "player_%s.png" % view[0])
		root.get_texture().get_image().save_png(path)
		print("saved player view: ", path)
		cam.queue_free()
		await process_frame


func _player_grid() -> Node3D:
	var grid := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.35, 0.35)
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color.RED
	# Horizontal lines every 0.5 m up to 2 m; ground (y = 0) in red.
	for i in range(0, 5):
		var y := i * 0.5
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4, 0.01 if i else 0.02, 0.01)
		line.mesh = box
		line.material_override = red if i == 0 else mat
		line.position = Vector3(0, y, 0)
		grid.add_child(line)
	return grid
