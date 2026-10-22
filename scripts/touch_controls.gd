extends Control
## On-screen controls for phones and tablets.
##
## Left side: a floating joystick (walk, or steer and throttle in a car).
## Right side: drag to look around. Buttons: Jump/Handbrake, Run, Enter/Exit
## and Ragdoll. Everything presses the existing input actions with
## Input.action_press(), so player.gd and car.gd don't know touch exists.
##
## Each finger is tracked by its index, so moving and looking at the same time
## works. Touches are read in _input() and marked handled; the mouse events
## Godot also generates from touches are ignored by camera_rig.gd.

## Set to true to show the controls on a desktop without a touchscreen.
## Running with `godot --path . -- --touch` does the same.
const DEBUG_FORCE := false

## Joystick: distance below which nothing is pressed, as a fraction of its radius
const DEADZONE := 0.15
## Look sensitivity: dragging across the full screen height turns this many
## mouse-pixels' worth (see camera_rig.gd SENSITIVITY), whatever the resolution
const LOOK_PIXELS_PER_SCREEN := 900.0
## Thumb-sized buttons: about 14 mm across, but between 7% and 13% of the
## screen height, so they stay usable on tablets and tiny phones
const BUTTON_MM := 14.0
const MENU_SIZE := 38.0

const STICK_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]

var camera_rig: Node
var player: Node

## finger index -> "stick", "look" or a button name
var _fingers := {}
var _stick_center := Vector2.ZERO
var _stick_vector := Vector2.ZERO
var _sprint_on := false
var _was_in_car := false
var _unit := 60.0
var _safe := Rect2()
var _buttons := {}
var _menu_center := Vector2.ZERO

signal menu_requested


## True when the controls should be shown on this device.
static func wanted() -> bool:
	return DEBUG_FORCE or DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let every pointer event through; touches are read in _input()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view := get_viewport_rect().size
	# The safe area (outside notches and rounded corners) is in screen pixels;
	# convert it to this viewport's coordinates
	var window := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	safe.position -= Vector2(DisplayServer.window_get_position())
	if safe.size.x <= 0.0 or window.x <= 0.0:
		_safe = Rect2(Vector2.ZERO, view)
	else:
		var to_view := view / window
		_safe = Rect2(safe.position * to_view, safe.size * to_view).intersection(Rect2(Vector2.ZERO, view))

	var mm_px := DisplayServer.screen_get_dpi() / 25.4 * (view.y / window.y if window.y > 0.0 else 1.0)
	_unit = clampf(BUTTON_MM / 2.0 * mm_px, view.y * 0.07, view.y * 0.13)

	var corner := _safe.end - Vector2(_unit, _unit) * 1.5
	_buttons = {
		"jump": corner,
		"run": corner + Vector2(-2.6, 0.3) * _unit,
		"interact": corner + Vector2(0.3, -2.6) * _unit,
		"ragdoll": corner + Vector2(-2.3, -2.3) * _unit,
	}
	_menu_center = _safe.position + Vector2(_unit * 1.5, _unit * 1.5)
	_stick_center = _stick_rest()
	queue_redraw()


## The part of the screen clear of notches, in viewport coordinates.
func safe_rect() -> Rect2:
	return _safe


func _stick_rest() -> Vector2:
	return Vector2(_safe.position.x, _safe.end.y) + Vector2(1.0, -1.0) * _stick_radius() * 1.4


func _stick_radius() -> float:
	return _unit * 2.0


func _in_car() -> bool:
	return player != null and player.car != null


## Buttons shown right now (Run and Ragdoll only make sense on foot)
func _visible_buttons() -> Array:
	return ["jump", "interact"] if _in_car() else ["jump", "run", "interact", "ragdoll"]


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()


func _touch_down(index: int, pos: Vector2) -> void:
	if pos.distance_to(_menu_center) <= MENU_SIZE:
		_fingers[index] = "menu"
		menu_requested.emit()
		queue_redraw()
		return
	for button in _visible_buttons():
		if pos.distance_to(_buttons[button]) <= _unit * (0.8 if button == "ragdoll" else 1.0) * 1.15:
			_fingers[index] = button
			_press_button(button, true)
			queue_redraw()
			return
	if pos.x < get_viewport_rect().size.x * 0.45:
		# Floating joystick: it centres wherever the thumb lands
		_fingers[index] = "stick"
		_stick_center = pos
		_set_stick(Vector2.ZERO)
	else:
		_fingers[index] = "look"
	queue_redraw()


func _touch_up(index: int) -> void:
	var role: String = _fingers.get(index, "")
	_fingers.erase(index)
	if role == "stick":
		_stick_center = _stick_rest()
		_set_stick(Vector2.ZERO)
	elif role != "" and role != "look":
		_press_button(role, false)
	queue_redraw()


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var role: String = _fingers.get(index, "")
	if role == "stick":
		_set_stick((pos - _stick_center) / _stick_radius())
		queue_redraw()
	elif role == "look" and camera_rig != null:
		camera_rig.look(relative * LOOK_PIXELS_PER_SCREEN / get_viewport_rect().size.y)


## Presses the four movement actions with analog strength. Screen up is
## "move_forward", which also means throttle in a car.
func _set_stick(v: Vector2) -> void:
	v = v.limit_length(1.0)
	_stick_vector = v
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	var strengths := [maxf(-v.x, 0.0), maxf(v.x, 0.0), maxf(-v.y, 0.0), maxf(v.y, 0.0)]
	for i in STICK_ACTIONS.size():
		if strengths[i] > 0.0:
			Input.action_press(STICK_ACTIONS[i], strengths[i])
		else:
			Input.action_release(STICK_ACTIONS[i])


func _press_button(button: String, down: bool) -> void:
	if button == "run":
		# Run is a toggle: holding it would tie up the thumb used for looking
		if down:
			_sprint_on = not _sprint_on
			if _sprint_on:
				Input.action_press("sprint")
			else:
				Input.action_release("sprint")
		return
	if down:
		Input.action_press(button)
	else:
		Input.action_release(button)


func _process(_delta: float) -> void:
	var in_car := _in_car()
	if in_car != _was_in_car:
		_was_in_car = in_car
		# Running stops when you get into a car, so it isn't still on when you get out
		if _sprint_on:
			_sprint_on = false
			Input.action_release("sprint")
		queue_redraw()


func _notification(what: int) -> void:
	# Nothing may stay pressed after the app goes to the background
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		release_all()


## Lets go of every action the controls are holding.
func release_all() -> void:
	for index in _fingers.keys():
		_touch_up(index)
	_fingers.clear()
	if _sprint_on:
		_sprint_on = false
		Input.action_release("sprint")
	_set_stick(Vector2.ZERO)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var radius := _stick_radius()
	draw_circle(_stick_center, radius, Color(1, 1, 1, 0.12))
	draw_arc(_stick_center, radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(_stick_center + _stick_vector * radius, radius * 0.42, Color(1, 1, 1, 0.45))
	draw_circle(_menu_center, MENU_SIZE, Color(0.04, 0.07, 0.08, 0.72))
	draw_arc(_menu_center, MENU_SIZE, 0, TAU, 40, Color(0.9, 0.75, 0.35, 0.8), 2.0)
	draw_string(font, _menu_center + Vector2(-MENU_SIZE * 0.55, MENU_SIZE * 0.15), "MENU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var labels := {"jump": "Brake" if _in_car() else "Jump", "run": "Run", "interact": "Exit" if _in_car() else "Car", "ragdoll": "Fall"}
	var held: Array = _fingers.values()
	for button in _visible_buttons():
		var r := _unit * (0.8 if button == "ragdoll" else 1.0)
		var lit: bool = button in held or (button == "run" and _sprint_on)
		draw_circle(_buttons[button], r, Color(1, 1, 1, 0.45 if lit else 0.18))
		draw_arc(_buttons[button], r, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
		var font_px := int(_unit * 0.36)
		var text_size := font.get_string_size(labels[button], HORIZONTAL_ALIGNMENT_CENTER, -1, font_px)
		draw_string(font, _buttons[button] + Vector2(-text_size.x / 2, font_px * 0.35), labels[button], HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Color.WHITE)
