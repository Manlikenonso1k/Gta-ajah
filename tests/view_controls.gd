extends SceneTree
## Screenshots of the touch controls, the settings screen and the button
## layout editor, at phone size. Needs a window (not --headless):
##   godot --path . --script tests/view_controls.gd -- --touch --quality=low
## Saves PNGs to user://control_views/.

var main: Node3D


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 720))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("user://control_views")
	var path := "user://control_views/%s.png" % name
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _run() -> void:
	await _frames(60)
	await _shot("hud")
	main._toggle_pause()
	main._open_settings()
	await _shot("settings")
	main._edit_layout()
	main._touch.selected = "jump"
	main._editor._select("jump")
	await _shot("layout_editor")
	main._finish_layout()
	quit()
