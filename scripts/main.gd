extends Node3D
## Sets up input, lighting, the city, the player, cars and pedestrians.

const City = preload("res://scripts/city.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const Player = preload("res://scripts/player.gd")
const Car = preload("res://scripts/car.gd")
const Pedestrian = preload("res://scripts/pedestrian.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const TouchControlsScene = preload("res://scenes/touch_controls.tscn")

const Quality = preload("res://scripts/quality.gd")
const PhoneMenu = preload("res://scripts/phone_menu.gd")
const VehicleHud = preload("res://scripts/vehicle_hud.gd")

## Models from VehicleModel.MODELS, cycled through the spawn points
const CAR_MODELS := ["corolla", "camry", "benz_g", "bmw_e30", "accord", "hiace", "vw_t3",
	"sprinter", "town_bus", "coach"]

var _player: CharacterBody3D
var _touch: Control = null
var _vehicle_hud: Control
var _phone: PanelContainer
var _paused := false


func _ready() -> void:
	var quality := Quality.current()
	print("Quality preset: ", Quality.current_name())
	Ragdoll.max_ragdolls = quality["ragdolls"]
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = quality["render_scale"]
	_setup_input()
	_setup_environment(quality)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var spawns := City.build(self, rng)

	var rig := CameraRig.new()
	add_child(rig)
	rig.camera.far = quality["draw_distance"]

	# The car next to the player first, then parking spots up to the preset's
	# count. Spots and pedestrians are picked evenly from their lists so smaller
	# presets still spread across the whole city.
	_spawn_car(Transform3D(Basis(Vector3.UP, PI), Vector3(City.road_line(3) + 3, 0.6, 0)), CAR_MODELS[0])
	var parking: Array = spawns["parking"]
	var parked := mini(parking.size(), quality["cars"] - 1)
	for i in parked:
		_spawn_car(parking[i * parking.size() / parked], CAR_MODELS[(i + 1) % CAR_MODELS.size()])

	var points: Array = spawns["sidewalk"]
	var walkers := mini(quality["pedestrians"], points.size())
	for i in walkers:
		var ped := Pedestrian.new()
		ped.colors = Ragdoll.random_colors(rng)
		ped.position = points[i * points.size() / walkers]
		add_child(ped)

	_player = Player.new()
	_player.camera_rig = rig
	_player.position = Vector3(City.road_line(3) - 1, 0.2, 5)
	add_child(_player)

	_setup_hud(rig)


func _process(_delta: float) -> void:
	_vehicle_hud.set_vehicle(_player.car)


func _spawn_car(xform: Transform3D, model: String) -> void:
	var car := Car.new()
	car.model = model
	car.transform = xform
	add_child(car)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"interact": [KEY_E, KEY_F],
		"ragdoll": [KEY_R],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func _setup_environment(quality: Dictionary) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.5, 0.78)
	sky_material.sky_horizon_color = Color(0.82, 0.8, 0.74)
	sky_material.ground_horizon_color = Color(0.7, 0.62, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Mostly warm daylight rather than blue sky, so colours stay true. Older
	# Intel Macs (OpenGL) often drop the sun entirely, leaving only ambient.
	env.ambient_light_color = Color(1.0, 0.95, 0.85)
	env.ambient_light_sky_contribution = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	# Humid Niger Delta haze
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.8, 0.72)
	env.fog_density = quality["fog_density"]
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = quality["shadows"]
	sun.directional_shadow_max_distance = quality["shadow_distance"]
	add_child(sun)


func _setup_hud(rig: Node3D) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	if TouchControls.wanted():
		_touch = TouchControlsScene.instantiate()
		_touch.camera_rig = rig
		_touch.player = _player
		layer.add_child(_touch)
		_touch.menu_requested.connect(_toggle_pause)
	_vehicle_hud = Control.new()
	_vehicle_hud.set_script(VehicleHud)
	_vehicle_hud.touch_mode = _touch != null
	_vehicle_hud.touch_controls = _touch
	layer.add_child(_vehicle_hud)
	_build_phone_menu(layer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_paused = not _paused
	_phone.visible = _paused
	get_tree().paused = _paused
	if _touch != null:
		_touch.release_all()
		# Let the in-game phone's Resume button receive taps while the world is paused.
		_touch.visible = not _paused
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED


func _build_phone_menu(layer: CanvasLayer) -> void:
	_phone = PanelContainer.new()
	_phone.set_script(PhoneMenu)
	_phone.connect("resume_requested", _toggle_pause)
	_phone.visible = false
	_phone.process_mode = Node.PROCESS_MODE_ALWAYS
	_phone.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_layout_phone()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.075, 0.08, 0.97)
	style.border_color = Color(0.82, 0.67, 0.31)
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	_phone.add_theme_stylebox_override("panel", style)
	layer.add_child(_phone)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	_phone.add_child(layout)
	var heading := Label.new()
	heading.text = "GARDEN CITY  /  PHONE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color(0.95, 0.77, 0.34))
	layout.add_child(heading)
	var sub := Label.new()
	sub.text = "PAUSED  •  QUICK GUIDE"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.55, 0.84, 0.72))
	layout.add_child(sub)
	var guide_scroll := ScrollContainer.new()
	guide_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(guide_scroll)
	var hints := Label.new()
	hints.text = "ON FOOT\nWASD / arrows   Move\nShift   Run\nSpace   Jump\nE / F   Enter or exit vehicle\nR   Ragdoll\nMouse   Look around\n\nIN A VEHICLE\nW / S   Accelerate / brake\nA / D   Steer\nSpace   Handbrake\nE / F   Exit vehicle\n\nPHONE CONTROLS\nLeft stick   Move / drive\nDrag right side   Look\nTouch buttons   Jump, run, enter, ragdoll"
	hints.add_theme_font_size_override("font_size", 16)
	hints.add_theme_color_override("font_color", Color(0.88, 0.92, 0.89))
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_scroll.add_child(hints)
	var resume := Button.new()
	resume.text = "RESUME GAME"
	resume.custom_minimum_size.y = 48
	resume.pressed.connect(_toggle_pause)
	layout.add_child(resume)
	var footer := Label.new()
	footer.text = "ESC / BACK  •  Garden City Stories"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 12)
	layout.add_child(footer)
	get_viewport().size_changed.connect(_layout_phone)


func _layout_phone() -> void:
	if _phone == null:
		return
	var view := get_viewport().get_visible_rect().size
	_phone.size = Vector2(minf(410.0, view.x * 0.84), minf(580.0, view.y * 0.9))
	_phone.position = (view - _phone.size) / 2.0
