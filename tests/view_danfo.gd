extends SceneTree
## Renders a danfo (or another van) for checking its sliding door, seats,
## passengers and conductor. Needs a window (not --headless):
##   godot --path . --script tests/view_danfo.gd -- vw_t3 [door|full|inside] [filled]
## "door": 6 frames of the sliding door opening, seen from the kerb side.
## "full": kerb side, front 3/4 and rear 3/4 of the van, door open.
## "inside": looking down through a cut-away roof, and in through the doorway.
## "filled" seats traffic passengers and the conductor; "moving" keeps the
## conductor hanging on the step as on a moving danfo.
## Saves PNGs to user://danfo_views/.

const Car = preload("res://scripts/car.gd")
const CELL := Vector2i(640, 420)

var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var key: String = args[0] if args.size() > 0 else "vw_t3"
	var mode: String = args[1] if args.size() > 1 else "full"
	var filled := args.has("filled")
	DisplayServer.window_set_size(CELL)

	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.78, 0.82, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.85)
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	world.add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60, 60)
	plane.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.35, 0.37)
	plane.material_override = mat
	ground.add_child(plane)
	world.add_child(ground)

	var car = Car.new()
	car.model = key
	car.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))
	world.add_child(car)
	await _frames(60)
	car.freeze = true
	if filled and car.get("occupants") != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		car.occupants.fill_traffic(rng)
		if args.has("moving") and car.occupants.conductor != null:
			car.occupants.conductor.hold_on = true
		await _frames(40)

	_camera = Camera3D.new()
	_camera.fov = 50.0
	world.add_child(_camera)
	_camera.make_current()
	var directory := "user://danfo_views/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	# Car faces +Z; +X is the driver's side, -X the kerb side with the sliding door
	var kerb := Vector3(-4.6, 1.3, -0.1)
	var shots := []
	match mode:
		"door":
			for n in 6:
				shots.append([kerb, Vector3(0, 1.0, 0), float(n) / 5.0])
		"inside":
			# From the back of the van looking forward along the aisle, and in through the doorway
			shots = [[Vector3(0.0, 1.55, -1.95), Vector3(0.0, 1.0, 1.2), -1.0], [Vector3(-2.4, 1.45, -0.1), Vector3(0.3, 1.0, -0.1), -1.0]]
		_:
			shots = [[kerb, Vector3(0, 1.0, 0), -1.0], [Vector3(-5.5, 2.2, 6.0), Vector3(0, 1.0, 0), -1.0], [Vector3(-5.5, 2.2, -6.0), Vector3(0, 1.0, 0), -1.0]]
	var roof_hidden := mode == "inside"
	if roof_hidden and car.has_method("set_roof_cutaway"):
		car.set_roof_cutaway(true)
	var sheet := Image.create(CELL.x * shots.size(), CELL.y, false, Image.FORMAT_RGB8)
	for n in shots.size():
		var shot: Array = shots[n]
		if shot[2] >= 0.0 and car.has_method("set_sliding_door"):
			car.set_sliding_door(shot[2])
		_camera.global_position = shot[0]
		_camera.look_at(shot[1], Vector3.UP)
		for i in 4:
			await process_frame
		var image := root.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		image.resize(CELL.x, CELL.y)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(n * CELL.x, 0))
	var path := ProjectSettings.globalize_path(directory + "%s_%s%s%s.png" % [key, mode, "_filled" if filled else "", "_moving" if args.has("moving") else ""])
	sheet.save_png(path)
	print("saved: ", path)
	quit()
