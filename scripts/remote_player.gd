extends Node3D
## Another online player as seen on this phone: the player model with its
## name above it, moved smoothly towards the latest received position and
## animated from the received speed and state. Hidden while that player drives
## (the car itself is moved by scripts/net_sync.gd).
## It has no collision: each phone only simulates its own player.

const Ragdoll = preload("res://scripts/ragdoll.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const AnimationSets = preload("res://scripts/animation_sets.gd")
const PLAYER_JSON := "res://assets/characters/player/player.json"

## Beyond this the puppet jumps instead of sliding (respawn, teleport)
const SNAP_DISTANCE := 12.0

var peer_id := 0
var display_name := "Player":
	set(value):
		display_name = value
		if _label != null:
			_label.text = value

var _target := Vector3.ZERO
var _target_yaw := 0.0
var _velocity := Vector3.ZERO
var _speed := 0.0
var _anim := "idle"
var _since_update := 0.0
var _has_state := false
var _model: Node3D
var _loco: RefCounted
var _limbs := {}
var _phase := 0.0
var _label: Label3D
var _in_air := false


func _ready() -> void:
	var visual := Node3D.new()
	add_child(visual)
	_load_model(visual)
	if _loco == null:
		_limbs = Ragdoll.build_visual(visual, {"skin": Color(0.3, 0.18, 0.11), "shirt": Color(0.75, 0.2, 0.15), "pants": Color(0.2, 0.2, 0.25)})
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.15
	_label.font_size = 48
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.86, 0.35)
	_label.no_depth_test = true
	add_child(_label)
	visible = false


func _load_model(visual: Node3D) -> void:
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_JSON))
	if not info is Dictionary:
		return
	var path := str(info.get("model_path", ""))
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + peer_id
	var clips := AnimationSets.pick(str(info.get("id", "PLAYER")), str(info.get("gender", "male")), info.get("tags", []))
	var loco := Locomotion.create(model, clips, rng)
	if loco == null:
		model.free()
		return
	_model = model
	_loco = loco
	visual.add_child(model)
	# glTF models face +Z; players face -Z
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for mixer: AnimationMixer in model.find_children("*", "AnimationMixer", true, false):
		mixer.active = true


## A state message from that player: p = position, y = yaw, s = ground speed,
## a = "idle" | "walk" | "run" | "air" | "down", c = car (when driving).
func apply_state(data: Dictionary) -> void:
	var p: Array = data.get("p", [0, 0, 0])
	var new_target := Vector3(float(p[0]), float(p[1]), float(p[2]))
	if _has_state and _since_update > 0.0:
		_velocity = (new_target - _target) / maxf(_since_update, 0.03)
	_target = new_target
	_target_yaw = float(data.get("y", 0.0))
	_speed = float(data.get("s", 0.0))
	_anim = str(data.get("a", "idle"))
	_since_update = 0.0
	var driving: bool = data.get("c") is Dictionary
	if not _has_state or global_position.distance_to(_target) > SNAP_DISTANCE:
		global_position = _target
		rotation.y = _target_yaw
	_has_state = true
	# While knocked down the other phone shows a ragdoll; here they reappear
	# when they get up
	visible = not driving and _anim != "down"
	if _anim == "air" and not _in_air and _loco != null:
		_loco.play_action("Jump_Start")
	_in_air = _anim == "air"


func _process(delta: float) -> void:
	if not _has_state:
		return
	_since_update += delta
	# Aim slightly ahead along the last movement so the puppet doesn't stop
	# between messages; never extrapolate for long.
	var ahead := _target + _velocity * minf(_since_update, 0.15)
	global_position = global_position.lerp(ahead, clampf(12.0 * delta, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(12.0 * delta, 0.0, 1.0))
	if not visible:
		return
	if _loco != null:
		var state := "idle"
		if _anim == "run":
			state = "run"
		elif _anim == "walk":
			state = "walk"
		_loco.set_locomotion(_speed if _anim != "down" else 0.0, state)
		_loco.advance(delta)
	else:
		_phase += _speed * 2.2 * delta
		Ragdoll.animate(_limbs, _phase, clampf(_speed / 7.0 * 1.5, 0, 1))
