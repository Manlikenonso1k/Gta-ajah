extends PanelContainer
## Controls & settings screen, opened from the in-game phone menu.
## Phone-only rows (steering, gyroscope, button layout) are hidden on
## computers without a touchscreen. Everything is saved immediately in
## user://controls.json (scripts/control_settings.gd).

const ControlSettings = preload("res://scripts/control_settings.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const GOLD := Color(0.95, 0.77, 0.34)
const MINT := Color(0.55, 0.84, 0.72)

signal closed
signal edit_layout_requested

var _tilt_bar: HSlider
var _tilt_label: Label
var _touch := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_touch = TouchControls.wanted()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.075, 0.08, 0.97)
	style.border_color = Color(0.82, 0.67, 0.31)
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", style)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)
	var heading := _label("CONTROLS & SETTINGS", 21, GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)

	if _touch:
		_section(rows, "DRIVING")
		var steering := OptionButton.new()
		steering.add_item("Steer with joystick")
		steering.add_item("Steer by tilting the phone (+ gas/brake pedals)")
		steering.select(1 if ControlSettings.get_value("steering") == "tilt" else 0)
		steering.custom_minimum_size.y = 44
		steering.item_selected.connect(func(i: int) -> void: ControlSettings.set_value("steering", "tilt" if i == 1 else "stick"))
		rows.add_child(steering)
		_slider_row(rows, "Tilt sensitivity", "tilt_sensitivity", 0.5, 2.5)
		_check_row(rows, "Reverse tilt direction", "invert_tilt")
		_tilt_label = _label("Tilt test: hold the phone like a wheel", 13, Color(0.8, 0.85, 0.82))
		rows.add_child(_tilt_label)
		_tilt_bar = HSlider.new()
		_tilt_bar.min_value = -1.0
		_tilt_bar.max_value = 1.0
		_tilt_bar.step = 0.01
		_tilt_bar.editable = false
		_tilt_bar.custom_minimum_size.y = 28
		rows.add_child(_tilt_bar)

		_section(rows, "GYROSCOPE CAMERA")
		_check_row(rows, "Aim the camera by turning the phone", "gyro_camera")
		_slider_row(rows, "Gyroscope sensitivity", "gyro_sensitivity", 0.3, 3.0)
		_check_row(rows, "Reverse left / right", "invert_gyro_x")
		_check_row(rows, "Reverse up / down", "invert_gyro_y")

		_section(rows, "BUTTONS")
		_slider_row(rows, "See-through", "opacity", 0.15, 1.0)
		var edit := Button.new()
		edit.text = "MOVE & RESIZE BUTTONS"
		edit.custom_minimum_size.y = 46
		edit.pressed.connect(func() -> void: edit_layout_requested.emit())
		rows.add_child(edit)

	_section(rows, "CAMERA")
	_slider_row(rows, "Look sensitivity (drag / mouse)", "look_sensitivity", 0.3, 3.0)

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size.y = 46
	back.pressed.connect(func() -> void: closed.emit())
	layout.add_child(back)
	get_viewport().size_changed.connect(_place)
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		closed.emit()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible or _tilt_bar == null:
		return
	var gravity := Input.get_gravity()
	if gravity.length() < 1.0:
		gravity = Input.get_accelerometer()
	if gravity.length() < 1.0:
		_tilt_label.text = "Tilt test: no tilt sensor found on this device"
		return
	var amount := TouchControls.tilt_amount(gravity)
	_tilt_bar.value = amount
	_tilt_label.text = "Tilt test: %s" % ("straight" if amount == 0.0 else ("steering LEFT" if amount < 0.0 else "steering RIGHT"))


func _place() -> void:
	var view := get_viewport_rect().size
	size = Vector2(minf(560.0, view.x * 0.9), minf(640.0, view.y * 0.94))
	position = (view - size) / 2.0


func _section(parent: Control, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	parent.add_child(spacer)
	parent.add_child(_label(text, 14, MINT))


func _slider_row(parent: Control, text: String, key: String, lo: float, hi: float) -> void:
	var row := HBoxContainer.new()
	var label := _label(text, 14, Color(0.88, 0.92, 0.89))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.05
	slider.value = float(ControlSettings.get_value(key))
	slider.custom_minimum_size = Vector2(190, 38)
	slider.value_changed.connect(func(v: float) -> void: ControlSettings.set_value(key, v))
	row.add_child(slider)
	parent.add_child(row)


func _check_row(parent: Control, text: String, key: String) -> void:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = bool(ControlSettings.get_value(key))
	check.custom_minimum_size.y = 40
	check.toggled.connect(func(on: bool) -> void: ControlSettings.set_value(key, on))
	parent.add_child(check)


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label
