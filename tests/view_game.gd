extends SceneTree
## Screenshots through the real gameplay camera, for judging how the game looks.
## Needs a window (not --headless); the quality preset is picked as in the game:
##   godot --path . --script tests/view_game.gd -- --quality=low
##   godot --path . --script tests/view_game.gd -- --quality=low --out=before
## Saves PNGs to user://game_views/<out>/ (default "latest").

const City = preload("res://scripts/city.gd")
const StreetPlaces = preload("res://scripts/street_places.gd")
const SIZE := Vector2i(1600, 720)   # a 20:9 phone in landscape

var main: Node3D


func _initialize() -> void:
	DisplayServer.window_set_size(SIZE)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## name: [player position, camera yaw, camera pitch]
func _views() -> Dictionary:
	var clinic := StreetPlaces.clinic_spawn(1)
	var market := City.block_center(2, 1)
	return {
		"spawn_clinic": [clinic.origin, clinic.basis.get_euler().y, -0.2],
		"start_street": [Vector3(City.road_line(3) - 1, 0.2, 5), 0.0, -0.22],
		"down_the_road": [Vector3(City.road_line(3) + 2, 0.2, City.block_center(0, 4).z), 0.0, -0.08],
		"market": [market + Vector3(4, 0.2, 26), 0.0, -0.18],
		"looking_up": [Vector3(City.road_line(2) + 1.5, 0.2, City.block_center(0, 2).z), PI / 2, 0.15],
	}


func _run() -> void:
	var out := "latest"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var dir := "user://game_views/" + out
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(60)
	var player: CharacterBody3D = main._player
	var rig: Node3D
	for child in main.get_children():
		if child.get("camera") is Camera3D:
			rig = child
	var views := _views()
	for view_name: String in views:
		var v: Array = views[view_name]
		player.global_position = v[0]
		player.velocity = Vector3.ZERO
		player.rotation.y = v[1]
		rig.yaw = v[1]
		rig.pitch = v[2]
		main._update_streaming()
		await _frames(45)
		var image := root.get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [dir, view_name]
		image.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
	quit()
