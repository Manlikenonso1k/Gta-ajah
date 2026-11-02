extends PanelContainer
## Toolbar shown while moving and resizing the on-screen controls (as in
## mobile shooters' HUD layout screens). Drag any control to move it; tap one
## to pick it, then use SIZE. The layout is saved as you go
## (scripts/control_settings.gd); DONE goes back to the settings.

const ControlSettings = preload("res://scripts/control_settings.gd")

signal done

var touch: Control

var _title: Label
var _size: HSlider
var _opacity: HSlider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.075, 0.08, 0.92)
	style.border_color = Color(0.82, 0.67, 0.31)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	_title = Label.new()
	_title.text = "Drag a control to move it"
	_title.custom_minimum_size.x = 170
	_title.add_theme_color_override("font_color", Color(0.95, 0.77, 0.34))
	row.add_child(_title)
	row.add_child(_caption("SIZE"))
	_size = _slider(0.5, 2.2, 1.0)
	_size.value_changed.connect(_on_size)
	row.add_child(_size)
	row.add_child(_caption("SEE-THROUGH"))
	_opacity = _slider(0.15, 1.0, float(ControlSettings.get_value("opacity")))
	_opacity.value_changed.connect(func(v: float) -> void:
		ControlSettings.set_value("opacity", v)
		touch.queue_redraw())
	row.add_child(_opacity)
	var view := Button.new()
	view.text = "SHOW: ON FOOT"
	view.custom_minimum_size = Vector2(150, 44)
	view.pressed.connect(func() -> void:
		touch.edit_view = "car" if touch.edit_view == "foot" else "foot"
		view.text = "SHOW: IN CAR" if touch.edit_view == "car" else "SHOW: ON FOOT"
		_select(""))
	row.add_child(view)
	var reset := Button.new()
	reset.text = "RESET"
	reset.custom_minimum_size = Vector2(90, 44)
	reset.pressed.connect(func() -> void:
		touch.reset_layout()
		_select(touch.selected))
	row.add_child(reset)
	var finish := Button.new()
	finish.text = "DONE"
	finish.custom_minimum_size = Vector2(90, 44)
	finish.pressed.connect(func() -> void: done.emit())
	row.add_child(finish)
	get_viewport().size_changed.connect(_place)


## Shows the toolbar and puts the controls in edit mode.
func open(touch_controls: Control) -> void:
	touch = touch_controls
	if not touch.selection_changed.is_connected(_select):
		touch.selection_changed.connect(_select)
	visible = true
	touch.edit_mode = true
	_select(touch.selected)
	_place.call_deferred()


func close() -> void:
	visible = false
	if touch != null:
		touch.edit_mode = false
		touch.edit_blocked.clear()


func _place() -> void:
	if not visible:
		return
	var view := get_viewport_rect().size
	size = Vector2(minf(view.x - 24.0, 1100.0), 0.0)
	reset_size()
	position = Vector2((view.x - size.x) / 2.0, 10.0)
	# Touches on the toolbar go to its sliders, not to the controls under it
	touch.edit_blocked.clear()
	touch.edit_blocked.append(Rect2(position, size).grow(6.0))


func _select(element: String) -> void:
	if element == "":
		_title.text = "Drag a control to move it"
		_size.editable = false
		return
	_title.text = touch.NAMES.get(element, element)
	_size.editable = true
	_size.set_value_no_signal(touch.element_scale(element))


func _on_size(value: float) -> void:
	if touch.selected != "":
		touch.set_element(touch.selected, touch.element_position(touch.selected), value)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.55, 0.84, 0.72))
	return label


func _slider(lo: float, hi: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(120, 40)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return slider
