extends SceneTree
## Movable buttons, tilt steering and the gyroscope camera, headless:
##   godot --headless --path . --script tests/controls_test.gd

const ControlSettings = preload("res://scripts/control_settings.gd")

## Stand-ins for the player (only .car is read) and the camera rig
class FakePlayer extends Node:
	var car: Variant = null

class FakeRig extends Node:
	var turned := Vector2.ZERO
	func look(relative: Vector2) -> void:
		turned += relative

var controls: Control
var player: FakePlayer
var rig: FakeRig
var failures := 0


func _initialize() -> void:
	ControlSettings.PATH = "user://controls_test.json"
	ControlSettings.reset()
	for action in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint", "interact", "ragdoll"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	player = FakePlayer.new()
	rig = FakeRig.new()
	root.add_child(player)
	root.add_child(rig)
	controls = load("res://scenes/touch_controls.tscn").instantiate()
	controls.player = player
	controls.camera_rig = rig
	root.add_child(controls)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	controls._input(event)


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	controls._input(event)


func _run() -> void:
	await process_frame
	controls.get_viewport().size = Vector2i(1600, 720)
	controls._layout()

	# Edit mode: dragging Jump moves it, presses nothing, and the spot is saved
	controls.edit_mode = true
	var jump_at: Vector2 = controls.element_position("jump")
	var target := Vector2(900, 400)
	_touch(0, jump_at, true)
	_drag(0, target, target - jump_at)
	_check(not Input.is_action_pressed("jump"), "edit mode presses nothing")
	_touch(0, target, false)
	_check(controls.element_position("jump").distance_to(target) < 1.0, "jump moved to %s" % controls.element_position("jump"))
	_check(controls.selected == "jump", "jump selected")
	controls.set_element("jump", controls.element_position("jump"), 1.6)
	_check(is_equal_approx(controls.radius("jump"), controls._unit * 1.6), "jump resized to 1.6x")
	controls.edit_mode = false
	# Saved: a fresh read of the file brings the same layout back
	ControlSettings._loaded = false
	controls._layout()
	_check(controls.element_position("jump").distance_to(target) < 1.0, "layout survives reloading")
	_touch(1, target, true)
	_check(Input.is_action_pressed("jump"), "jump works at its new spot")
	_touch(1, target, false)
	_check(not Input.is_action_pressed("jump"), "jump released")
	controls.reset_layout()
	_check(controls.element_position("jump").distance_to(controls.default_positions()["jump"]) < 1.0, "reset puts jump back")

	# Tilt steering: in a car, roll presses left/right; pedals are gas and brake
	ControlSettings.set_value("steering", "tilt")
	player.car = Node.new()
	await process_frame
	_check("gas" in controls.visible_elements() and not "stick" in controls.visible_elements(), "pedals replace the joystick in a car")
	controls.gravity_override = Vector3(4.0, -8.9, 0.0)
	await process_frame
	var right := Input.get_action_strength("move_right")
	_check(right > 0.5 and not Input.is_action_pressed("move_left"), "tilting one way steers right (%.2f)" % right)
	ControlSettings.set_value("invert_tilt", true)
	await process_frame
	_check(Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "reverse tilt steers left")
	controls.gravity_override = Vector3(0.12, -9.8, 0.0)
	await process_frame
	_check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "level phone drives straight")
	var gas_at: Vector2 = controls.element_position("gas")
	_touch(2, gas_at, true)
	_check(Input.is_action_pressed("move_forward"), "gas pedal accelerates")
	_touch(2, gas_at, false)
	_check(not Input.is_action_pressed("move_forward"), "gas released")

	# Gyroscope camera: off while tilt-steering, turns the camera on foot
	ControlSettings.set_value("gyro_camera", true)
	controls.gyro_override = Vector3(0.0, 1.0, 0.0)
	rig.turned = Vector2.ZERO
	await process_frame
	_check(rig.turned == Vector2.ZERO, "gyro camera off while tilt-steering")
	player.car.free()
	player.car = null
	await process_frame
	rig.turned = Vector2.ZERO
	await process_frame
	await process_frame
	_check(rig.turned.x < 0.0, "turning the phone left turns the camera left (%.1f)" % rig.turned.x)
	ControlSettings.set_value("invert_gyro_x", true)
	rig.turned = Vector2.ZERO
	await process_frame
	_check(rig.turned.x > 0.0, "reversed gyro turns the other way")
	controls.gyro_override = Vector3.ZERO
	_check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "tilt released on foot")

	ControlSettings.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://controls_test.json"))
	print("controls test: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures > 0 else 0)
