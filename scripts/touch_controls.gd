extends Control
## On-screen controls for phones and tablets.
##
## Left side: a joystick (walk, or steer and throttle in a car). Right side:
## drag to look around. Buttons: Jump/Handbrake, Run, Enter/Exit and Ragdoll.
## Everything presses the existing input actions with Input.action_press(), so
## player.gd and car.gd don't know touch exists.
##
## Settings (scripts/control_settings.gd, changed in the pause menu):
## - every element can be moved and resized (edit_mode, driven by
##   scripts/controls_editor.gd) and the layout is saved
## - steering "tilt": in a car, turning the phone like a wheel steers and GAS /
##   BRAKE pedals replace the joystick
## - gyro_camera: turning the phone turns the camera (as in shooters)
##
## Each finger is tracked by its index, so moving and looking at the same time
## works. Touches are read in _input() and marked handled; the mouse events
## Godot also generates from touches are ignored by camera_rig.gd.

const ControlSettings = preload("res://scripts/control_settings.gd")

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
## Tilt steering: degrees of phone roll for full lock at sensitivity 1
const TILT_FULL_LOCK := 28.0
const TILT_DEADZONE := 0.06
## camera_rig.gd turns 0.003 rad per look() pixel
const RIG_RADIANS_PER_PIXEL := 0.003

const STICK_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]
## Everything that can be moved and resized
const ELEMENTS := ["stick", "jump", "run", "interact", "ragdoll", "gas", "brake", "menu"]
const NAMES := {"stick": "Joystick", "jump": "Jump / Handbrake", "run": "Run", "interact": "Car", "ragdoll": "Fall", "gas": "Gas pedal", "brake": "Brake pedal", "menu": "Menu"}
## Size of each element relative to the button unit
const BASE_SIZE := {"stick": 2.0, "jump": 1.0, "run": 1.0, "interact": 1.0, "ragdoll": 0.8, "gas": 1.2, "brake": 1.2, "menu": 0.62}

var camera_rig: Node
var player: Node
## While true, touches move and select elements instead of pressing them
var edit_mode := false:
	set(value):
		edit_mode = value
		release_all()
		queue_redraw()
## Which set edit mode shows: "foot" or "car" (the pedals share the
## joystick's and Run's spots, so they are edited separately)
var edit_view := "foot":
	set(value):
		edit_view = value
		selected = ""
		queue_redraw()
## Element picked in edit mode ("" = none)
var selected := ""
## Areas where edit mode leaves touches to other controls (the editor's toolbar)
var edit_blocked: Array[Rect2] = []
## Tests set these instead of reading the phone's sensors
var gravity_override: Variant = null
var gyro_override: Variant = null

## finger index -> "stick", "look", "drag:<element>" or a button name
var _fingers := {}
var _stick_center := Vector2.ZERO
var _stick_vector := Vector2.ZERO
var _sprint_on := false
var _was_in_car := false
var _unit := 60.0
var _safe := Rect2()
## Centre of every element except the stick (kept as `_buttons` for tests)
var _buttons := {}
var _stick_rest_point := Vector2.ZERO
var _tilt_active := false
var _drag_offset := Vector2.ZERO

signal menu_requested
signal selection_changed(element: String)


## True when the controls should be shown on this device.
static func wanted() -> bool:
	return DEBUG_FORCE or DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()


## -1 (full left) .. 1 (full right) for a gravity vector, as tilt steering
## reads it. The settings screen uses this for its live test bar.
static func tilt_amount(gravity: Vector3) -> float:
	var g := gravity.length()
	if g < 1.0:
		return 0.0
	var roll := asin(clampf(gravity.x / g, -1.0, 1.0))
	var full := deg_to_rad(TILT_FULL_LOCK) / maxf(float(ControlSettings.get_value("tilt_sensitivity")), 0.1)
	var amount := clampf(roll / full, -1.0, 1.0)
	if ControlSettings.get_value("invert_tilt"):
		amount = -amount
	return 0.0 if absf(amount) < TILT_DEADZONE else amount


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

	var defaults := default_positions()
	var layout: Dictionary = ControlSettings.get_value("layout")
	_buttons = {}
	for element: String in ELEMENTS:
		var pos: Vector2 = defaults[element]
		var saved: Variant = layout.get(element)
		if saved is Dictionary and saved.has("x") and saved.has("y"):
			pos = Vector2(float(saved["x"]), float(saved["y"])) * view
		if element == "stick":
			_stick_rest_point = pos
		else:
			_buttons[element] = pos
	_stick_center = _stick_rest_point
	queue_redraw()


## Where each element sits before the player moves it.
func default_positions() -> Dictionary:
	var corner := _safe.end - Vector2(_unit, _unit) * 1.5
	var stick_radius := _unit * BASE_SIZE["stick"]
	return {
		"stick": Vector2(_safe.position.x, _safe.end.y) + Vector2(1.0, -1.0) * stick_radius * 1.4,
		"jump": corner,
		"run": corner + Vector2(-2.6, 0.3) * _unit,
		"interact": corner + Vector2(0.3, -2.6) * _unit,
		"ragdoll": corner + Vector2(-2.3, -2.3) * _unit,
		# The pedals take the joystick's and Run's places while tilt-steering
		"gas": corner + Vector2(-2.7, 0.2) * _unit,
		"brake": Vector2(_safe.position.x, _safe.end.y) + Vector2(1.8, -1.6) * _unit,
		"menu": _safe.position + Vector2(_unit * 1.5, _unit * 1.5),
	}


## The part of the screen clear of notches, in viewport coordinates.
func safe_rect() -> Rect2:
	return _safe


func radius(element: String) -> float:
	var layout: Dictionary = ControlSettings.get_value("layout")
	var saved: Variant = layout.get(element)
	var size_scale := float(saved.get("s", 1.0)) if saved is Dictionary else 1.0
	return _unit * BASE_SIZE[element] * size_scale


func element_position(element: String) -> Vector2:
	return _stick_rest_point if element == "stick" else _buttons[element]


## Stores an element's position (viewport pixels) and size multiplier.
func set_element(element: String, pos: Vector2, size_scale := -1.0) -> void:
	var layout: Dictionary = ControlSettings.get_value("layout")
	var entry: Dictionary = layout.get(element, {})
	var view := get_viewport_rect().size
	pos = pos.clamp(Vector2.ZERO, view)
	entry["x"] = pos.x / view.x
	entry["y"] = pos.y / view.y
	if size_scale > 0.0:
		entry["s"] = size_scale
	elif not entry.has("s"):
		entry["s"] = 1.0
	layout[element] = entry
	ControlSettings.set_value("layout", layout)
	_layout()


func element_scale(element: String) -> float:
	var saved: Variant = (ControlSettings.get_value("layout") as Dictionary).get(element)
	return float(saved.get("s", 1.0)) if saved is Dictionary else 1.0


func reset_layout() -> void:
	ControlSettings.set_value("layout", {})
	_layout()


func _in_car() -> bool:
	return player != null and player.car != null


func _tilt_steering() -> bool:
	return _in_car() and ControlSettings.get_value("steering") == "tilt"


## Elements shown right now
func visible_elements() -> Array:
	if edit_mode:
		if edit_view == "car":
			return ["brake", "gas", "jump", "interact", "menu"]
		return ["stick", "jump", "run", "interact", "ragdoll", "menu"]
	if _tilt_steering():
		return ["brake", "gas", "jump", "interact", "menu"]
	if _in_car():
		return ["stick", "jump", "interact", "menu"]
	return ["stick", "jump", "run", "interact", "ragdoll", "menu"]


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if edit_mode and event.pressed and _in_blocked(event.position):
			return
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if not _fingers.has(event.index):
			return
		_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()


func _in_blocked(pos: Vector2) -> bool:
	for rect in edit_blocked:
		if rect.has_point(pos):
			return true
	return false


## The element under `pos`, or "".
func element_at(pos: Vector2) -> String:
	var best := ""
	var best_distance := INF
	for element: String in visible_elements():
		var d := pos.distance_to(element_position(element))
		var reach := radius(element) * (1.0 if element == "stick" else 1.15)
		if d <= reach and d < best_distance:
			best = element
			best_distance = d
	return best


func _touch_down(index: int, pos: Vector2) -> void:
	if edit_mode:
		var picked := element_at(pos)
		if picked != "":
			_fingers[index] = "drag:" + picked
			_drag_offset = element_position(picked) - pos
			if picked != selected:
				selected = picked
				selection_changed.emit(picked)
		queue_redraw()
		return
	var element := element_at(pos)
	if element == "menu":
		_fingers[index] = "menu"
		menu_requested.emit()
	elif element != "" and element != "stick":
		_fingers[index] = element
		_press_button(element, true)
	elif "stick" in visible_elements() and (element == "stick" or _on_stick_side(pos)):
		# Floating joystick around its spot: it centres where the thumb lands
		_fingers[index] = "stick"
		_stick_center = pos
		_set_stick(Vector2.ZERO)
	else:
		_fingers[index] = "look"
	queue_redraw()


## The joystick's side of the screen (left 45%, or right 45% if it was moved
## there): a thumb landing anywhere there takes the joystick.
func _on_stick_side(pos: Vector2) -> bool:
	var width := get_viewport_rect().size.x
	if _stick_rest_point.x < width * 0.5:
		return pos.x < width * 0.45
	return pos.x > width * 0.55


func _touch_up(index: int) -> void:
	var role: String = _fingers.get(index, "")
	_fingers.erase(index)
	if role == "stick":
		_stick_center = _stick_rest_point
		_set_stick(Vector2.ZERO)
	elif role.begins_with("drag:"):
		var element := role.trim_prefix("drag:")
		set_element(element, element_position(element))
	elif role != "" and role != "look" and role != "menu":
		_press_button(role, false)
	queue_redraw()


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var role: String = _fingers.get(index, "")
	if role == "stick":
		_set_stick((pos - _stick_center) / radius("stick"))
		queue_redraw()
	elif role == "look" and camera_rig != null:
		var sensitivity := float(ControlSettings.get_value("look_sensitivity"))
		camera_rig.look(relative * LOOK_PIXELS_PER_SCREEN * sensitivity / get_viewport_rect().size.y)
	elif role.begins_with("drag:"):
		var element := role.trim_prefix("drag:")
		var target := (pos + _drag_offset).clamp(Vector2.ZERO, get_viewport_rect().size)
		if element == "stick":
			_stick_rest_point = target
			_stick_center = target
		else:
			_buttons[element] = target
		queue_redraw()


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
	var action: String = {"gas": "move_forward", "brake": "move_back"}.get(button, button)
	if down:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _process(delta: float) -> void:
	var in_car := _in_car()
	if in_car != _was_in_car:
		_was_in_car = in_car
		# Running stops when you get into a car, so it isn't still on when you get out
		if _sprint_on:
			_sprint_on = false
			Input.action_release("sprint")
		release_all()
		queue_redraw()
	if edit_mode:
		return
	_update_tilt()
	_update_gyro(delta)


## Tilt steering: phone roll presses move_left / move_right.
func _update_tilt() -> void:
	if not _tilt_steering():
		if _tilt_active:
			_tilt_active = false
			Input.action_release("move_left")
			Input.action_release("move_right")
		return
	_tilt_active = true
	var gravity: Vector3 = gravity_override if gravity_override != null else Input.get_gravity()
	if gravity.length() < 1.0:
		gravity = Input.get_accelerometer()
	var amount := tilt_amount(gravity)
	if amount < 0.0:
		Input.action_press("move_left", -amount)
		Input.action_release("move_right")
	elif amount > 0.0:
		Input.action_press("move_right", amount)
		Input.action_release("move_left")
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")


## Gyroscope camera: turning the phone turns the camera. Off while
## tilt-steering, where turning the phone is the steering wheel.
func _update_gyro(delta: float) -> void:
	if camera_rig == null or not ControlSettings.get_value("gyro_camera") or _tilt_steering():
		return
	var rate: Vector3 = gyro_override if gyro_override != null else Input.get_gyroscope()
	if rate.length() < 0.02:
		return
	var sensitivity := float(ControlSettings.get_value("gyro_sensitivity"))
	var x_sign := -1.0 if ControlSettings.get_value("invert_gyro_x") else 1.0
	var y_sign := -1.0 if ControlSettings.get_value("invert_gyro_y") else 1.0
	# Turning the phone left (positive rate around its vertical axis) turns the
	# camera left; tipping its top away looks up
	var turn := Vector2(-rate.y * x_sign, -rate.x * y_sign) * delta * sensitivity / RIG_RADIANS_PER_PIXEL
	camera_rig.look(turn)


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
	for action in ["jump", "interact", "ragdoll"]:
		Input.action_release(action)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var alpha := clampf(float(ControlSettings.get_value("opacity")), 0.15, 1.0) / 0.55
	var shown := visible_elements()
	if "stick" in shown:
		var r := radius("stick")
		var center := _stick_rest_point if edit_mode else _stick_center
		draw_circle(center, r, Color(1, 1, 1, 0.12 * alpha))
		draw_arc(center, r, 0, TAU, 48, Color(1, 1, 1, minf(0.35 * alpha, 1.0)), 3.0)
		draw_circle(center + (Vector2.ZERO if edit_mode else _stick_vector * r), r * 0.42, Color(1, 1, 1, minf(0.45 * alpha, 1.0)))

	var labels := {"jump": "Brake" if _in_car() else "Jump", "run": "Run", "interact": "Exit" if _in_car() else "Car",
		"ragdoll": "Fall", "gas": "GAS", "brake": "BRAKE", "menu": "MENU"}
	if edit_mode:
		labels["jump"] = "Brake" if edit_view == "car" else "Jump"
		labels["interact"] = "Exit" if edit_view == "car" else "Car"
	var held: Array = _fingers.values()
	for button: String in shown:
		if button == "stick":
			continue
		var r := radius(button)
		var center: Vector2 = _buttons[button]
		var lit: bool = button in held or (button == "run" and _sprint_on)
		var fill := Color(1, 1, 1, minf((0.45 if lit else 0.18) * alpha, 1.0))
		var ring := Color(1, 1, 1, minf(0.5 * alpha, 1.0))
		if button == "menu":
			fill = Color(0.04, 0.07, 0.08, minf(0.72 * alpha, 1.0))
			ring = Color(0.9, 0.75, 0.35, minf(0.8 * alpha, 1.0))
		elif button == "gas":
			fill = Color(0.3, 0.85, 0.4, minf((0.55 if lit else 0.25) * alpha, 1.0))
		elif button == "brake":
			fill = Color(0.95, 0.3, 0.25, minf((0.55 if lit else 0.25) * alpha, 1.0))
		draw_circle(center, r, fill)
		draw_arc(center, r, 0, TAU, 40, ring, 3.0)
		var font_px := int(clampf(r * 0.38, 10.0, 40.0))
		var text: String = labels[button]
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_px)
		draw_string(font, center + Vector2(-text_size.x / 2, font_px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Color(1, 1, 1, minf(alpha, 1.0)))

	if edit_mode:
		for element: String in shown:
			var pos := element_position(element)
			var r := radius(element)
			var picked := element == selected
			draw_arc(pos, r + 6.0, 0, TAU, 48, Color(1.0, 0.8, 0.3, 1.0) if picked else Color(1, 1, 1, 0.35), 4.0 if picked else 2.0)
			if element == "stick":
				var text_size := font.get_string_size("JOYSTICK", HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
				draw_string(font, pos + Vector2(-text_size.x / 2, 6), "JOYSTICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
