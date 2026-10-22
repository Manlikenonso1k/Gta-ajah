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

## Models from VehicleModel.MODELS, cycled through the spawn points
const CAR_MODELS := ["corolla", "camry", "benz_g", "bmw_e30", "accord", "hiace", "vw_t3",
	"sprinter", "town_bus", "coach"]

var _player: CharacterBody3D
var _hud: Label
var _touch: Control = null


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
	var text := "WASD move · Shift run · Space jump · E enter car · R ragdoll · Esc free mouse"
	if _touch != null:
		text = "Left thumb: move · drag right side: look"
	if _player.car != null:
		var speed := roundi(_player.car.linear_velocity.length() * 3.6)
		text = ("%d km/h" % speed) if _touch != null else "WASD drive · Space handbrake · E get out    %d km/h" % speed
	_hud.text = text


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
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)

	if TouchControls.wanted():
		_touch = TouchControlsScene.instantiate()
		_touch.camera_rig = rig
		_touch.player = _player
		layer.add_child(_touch)
		# Keep the text clear of notches
		_hud.position = _touch.safe_rect().position + Vector2(16, 12)
