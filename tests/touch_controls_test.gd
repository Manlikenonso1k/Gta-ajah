extends SceneTree
## Headless touch input check: godot --headless --path . --script tests/touch_controls_test.gd

var controls: Control


func _initialize() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint", "interact", "ragdoll"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	controls = load("res://scenes/touch_controls.tscn").instantiate()
	root.add_child(controls)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	controls.get_viewport().size = Vector2i(1280, 720)
	controls._layout()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(100, 300)
	controls._input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(100, 180)
	drag.relative = Vector2(0, -120)
	controls._input(drag)
	assert(Input.is_action_pressed("move_forward"), "joystick drag should press move_forward")
	print("touch joystick: move_forward pressed")

	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = drag.position
	controls._input(up)
	assert(not Input.is_action_pressed("move_forward"), "lifting joystick should release move_forward")
	print("touch release: move_forward released")

	var jump_pos: Vector2 = controls._buttons["jump"]
	var jump_down := InputEventScreenTouch.new()
	jump_down.index = 1
	jump_down.pressed = true
	jump_down.position = jump_pos
	controls._input(jump_down)
	assert(Input.is_action_pressed("jump"), "jump button should press jump")
	var jump_up := InputEventScreenTouch.new()
	jump_up.index = 1
	jump_up.pressed = false
	jump_up.position = jump_pos
	controls._input(jump_up)
	assert(not Input.is_action_pressed("jump"), "lifting jump finger should release jump")
	print("touch button: jump pressed and released")
	quit()
