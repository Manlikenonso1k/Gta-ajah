extends Node3D
## Sets up input, lighting, the city, the player, cars and pedestrians.

const City = preload("res://scripts/city.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const CameraRig = preload("res://scripts/camera_rig.gd")
const Player = preload("res://scripts/player.gd")
const Car = preload("res://scripts/car.gd")
const Pedestrian = preload("res://scripts/pedestrian.gd")

const PEDESTRIANS := 30
## Models from car.gd MODELS, cycled through the spawn points
const CAR_MODELS := ["sedan", "taxi", "suv_luxury", "hatchback", "van", "police",
	"sedan_sports", "suv", "delivery", "ambulance", "truck"]

var _player: CharacterBody3D
var _hud: Label


func _ready() -> void:
	_setup_input()
	_setup_environment()

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var spawns := City.build(self, rng)

	var rig := CameraRig.new()
	add_child(rig)

	_spawn_car(Transform3D(Basis(Vector3.UP, PI), Vector3(City.road_line(3) + 3, 0.6, 0)), CAR_MODELS[0])
	for i in spawns["parking"].size():
		_spawn_car(spawns["parking"][i], CAR_MODELS[(i + 1) % CAR_MODELS.size()])

	var points: Array = spawns["sidewalk"]
	for i in mini(PEDESTRIANS, points.size()):
		var ped := Pedestrian.new()
		ped.colors = Ragdoll.random_colors(rng)
		ped.position = points[i]
		add_child(ped)

	_player = Player.new()
	_player.camera_rig = rig
	_player.position = Vector3(City.road_line(3) - 1, 0.2, 5)
	add_child(_player)

	_setup_hud()


func _process(_delta: float) -> void:
	var text := "WASD move · Shift run · Space jump · E enter car · R ragdoll · Esc free mouse"
	if _player.car != null:
		text = "WASD drive · Space handbrake · E get out    %d km/h" % roundi(_player.car.linear_velocity.length() * 3.6)
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


func _setup_environment() -> void:
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
	env.fog_density = 0.0025
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	add_child(sun)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)
