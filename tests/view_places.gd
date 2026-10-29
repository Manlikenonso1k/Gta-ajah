extends SceneTree
## Renders the street-life places (scripts/street_places.gd) in the real game
## scene: a row of 4 frames about half a second apart per view, so smoke and
## animation show. Needs a window (not --headless):
##   godot --path . --script tests/view_places.gd            # every view
##   godot --path . --script tests/view_places.gd -- suya    # views whose name contains "suya"
## Saves PNGs to user://place_views/.

const City = preload("res://scripts/city.gd")
const StreetPlaces = preload("res://scripts/street_places.gd")
const FRAMES := 4
const CELL := Vector2i(640, 400)

## name: [camera position, look-at point]
var VIEWS := {}


func _initialize() -> void:
	var bridge := Vector3(City.road_line(StreetPlaces.FLYOVER_ROAD), 0, City.block_center(0, StreetPlaces.FLYOVER_ROW).z)
	var market := City.block_center(2, 1)
	var clinic := City.block_center(3, 1) + Vector3(-City.LOT_OFFSET, 0, City.LOT_OFFSET - 2.0)
	VIEWS = {
		"flyover": [bridge + Vector3(14, 7, 24), bridge + Vector3(0, 3, 0)],
		"under_bridge_east": [bridge + Vector3(12.5, 2.2, 10.5), bridge + Vector3(13, 0.4, 0)],
		"under_bridge_west": [bridge + Vector3(-13.5, 2.2, 10.5), bridge + Vector3(-13, 0.4, 0)],
		"market": [market + Vector3(4, 5.5, 30), market + Vector3(2, 1.5, 8)],
		"suya": [market + Vector3(10, 2.2, 21), market + Vector3(6, 1.2, 14)],
		"supermarket": [market + Vector3(-4, 2.4, 22), market + Vector3(-9.5, 2.2, 13)],
		"clinic": [clinic + Vector3(-11, 2.6, -1.5), clinic + Vector3(-3.5, 1.2, -1.5)],
	}
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(CELL.x, CELL.y))
	var filter := "" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(30)
	var player: Node3D = main.get("_player")
	var directory := "user://place_views/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var camera := Camera3D.new()
	camera.fov = 60.0
	root.add_child(camera)
	for name: String in VIEWS:
		if filter != "" and not name.contains(filter):
			continue
		var view: Array = VIEWS[name]
		# The player stands nearby so the block, its people and their animation
		# are fully active (streaming follows the player)
		var back := Vector3(view[0].x - view[1].x, 0.0, view[0].z - view[1].z).normalized()
		player.global_position = Vector3(view[0].x, 0.2, view[0].z) + back * 6.0
		main.call("_update_streaming")
		camera.global_position = view[0]
		camera.look_at(view[1], Vector3.UP)
		camera.make_current()
		await _frames(90)
		var sheet := Image.create(CELL.x * FRAMES, CELL.y, false, Image.FORMAT_RGB8)
		for f in FRAMES:
			camera.make_current()
			for i in 3:
				await process_frame
			var image := root.get_texture().get_image()
			image.convert(Image.FORMAT_RGB8)
			image.resize(CELL.x, CELL.y)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(f * CELL.x, 0))
			await _frames(30)
		var path := ProjectSettings.globalize_path(directory + name + ".png")
		sheet.save_png(path)
		print("saved: ", path)
	quit()
