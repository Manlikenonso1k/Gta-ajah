extends Node3D
## Third-person orbit camera. Mouse to look; in a car it swings back behind
## the vehicle when the mouse is left alone.

const ControlSettings = preload("res://scripts/control_settings.gd")
const SENSITIVITY := 0.003

var target: Node3D
var height := 1.6
var vehicle_mode := false
var yaw := 0.0
var pitch := -0.25
var camera: Camera3D

var _arm: SpringArm3D
var _mouse_idle := 0.0


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = 4.5
	_arm.collision_mask = 1
	_arm.margin = 0.2
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 1500
	_arm.add_child(camera)
	# Phones have no mouse to capture; looking around comes from touch_controls.gd
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func follow(node: Node3D, follow_height: float, in_vehicle := false) -> void:
	target = node
	height = follow_height
	vehicle_mode = in_vehicle


## Turns the camera by `relative` pixels of mouse-style movement. Touch drags
## call this too, so both rotate the camera the same way.
func look(relative: Vector2) -> void:
	yaw -= relative.x * SENSITIVITY
	pitch = clampf(pitch - relative.y * SENSITIVITY, -1.2, 0.5)
	_mouse_idle = 0.0


func _unhandled_input(event: InputEvent) -> void:
	# Mouse events that Godot generates from touches would fight the touch
	# controls (a finger on the joystick would also turn the camera), and the
	# capture/Esc behaviour makes no sense without a real mouse.
	if event.device == InputEvent.DEVICE_ID_EMULATION or OS.has_feature("mobile"):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * float(ControlSettings.get_value("look_sensitivity")))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	_mouse_idle += delta
	var goal := target.global_position + Vector3.UP * height
	global_position = global_position.lerp(goal, minf(1.0, 15.0 * delta))
	if vehicle_mode and _mouse_idle > 1.5 and target is RigidBody3D and target.linear_velocity.length() > 2.0:
		# Vehicles drive along +Z, so "behind" is the car's yaw + PI
		yaw = lerp_angle(yaw, target.global_rotation.y + PI, 2.0 * delta)
	rotation = Vector3(pitch, yaw, 0)
	_arm.spring_length = lerpf(_arm.spring_length, 7.0 if vehicle_mode else 4.5, 3.0 * delta)
