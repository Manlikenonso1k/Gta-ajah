extends SceneTree
## Headless pause check: godot --headless --path . --script tests/phone_menu_test.gd

var main: Node


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	main._toggle_pause()
	assert(paused and main._phone.visible, "phone menu should pause and appear")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	main._phone._unhandled_input(cancel)
	assert(not paused and not main._phone.visible, "cancel should close phone and resume the world")
	print("phone menu: pause, cancel, and resume passed")
	quit()
