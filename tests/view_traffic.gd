extends SceneTree
## Top-down render of the road graph, pavement graph, crossings and the AI
## cars' planned paths, with the F6 debug view on. Reckless drivers' paths and
## boxes are red; normal ones green. Run with a window (not headless):
##   godot --path . --script tests/view_traffic.gd
## Optional user args: a float orthographic size (metres across), e.g. `-- 120`
## for a closer look at the city centre. Saves PNGs to user://traffic_views/.

const Traffic = preload("res://scripts/traffic.gd")
const City = preload("res://scripts/city.gd")

const EXTRA_TRAFFIC := 18


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	# A big square window makes the top-down city fill the frame.
	DisplayServer.window_set_size(Vector2i(1200, 1200))
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(40)

	# Find the traffic manager and add a crowd so paths are easy to see.
	var traffic: Node = null
	for child in main.get_children():
		if child is Traffic:
			traffic = child
	if traffic == null:
		push_error("traffic manager missing")
		quit(1)
		return
	traffic.spawn_cars(EXTRA_TRAFFIC)
	# Let the cars pick routes and spread out along the lanes.
	await _frames(120)
	traffic.set_debug_visible(true)
	await _frames(5)

	var directory := "user://traffic_views/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))

	# Wide shot: the whole city from straight above.
	var span := City.HALF * 2.0 + 20.0
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_float():
		span = args[0].to_float()
	await _capture(main, Vector3(0, 0, 0), span, directory + "traffic_topdown.png")

	# Closer shot centred on a busy inner junction.
	var junction := Vector3(City.road_line(2), 0.0, City.road_line(2))
	await _capture(main, junction, 90.0, directory + "traffic_junction.png")

	print("reckless drivers: ", _reckless_count(traffic), " of ", traffic.drivers.size())
	quit()


func _capture(main: Node3D, center: Vector3, span: float, path: String) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = span
	camera.near = 0.5
	camera.far = 2000.0
	# A plain dark background with flat ambient and no fog, so the coloured debug
	# lines read clearly from straight above (the game's fog would wash them out).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	camera.environment = env
	main.add_child(camera)
	# look_at needs the node in the tree; position then aim straight down with
	# -Z (north) toward the top of the image.
	camera.global_position = center + Vector3(0, 220, 0.01)
	camera.look_at(center, Vector3(0, 0, -1))
	camera.make_current()
	# A few process frames so the debug mesh and camera settle before the grab.
	for i in 30:
		await process_frame
	var full := ProjectSettings.globalize_path(path)
	root.get_texture().get_image().save_png(full)
	print("saved: ", full)
	camera.queue_free()


func _reckless_count(traffic: Node) -> int:
	var n := 0
	for driver in traffic.drivers:
		n += int(driver.reckless)
	return n
