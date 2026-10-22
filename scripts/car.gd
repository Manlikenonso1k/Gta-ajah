extends VehicleBody3D
## Drivable car. Forward is +Z (VehicleBody3D convention).
## Knocks characters into ragdolls when it hits them at speed.

const Ragdoll = preload("res://scripts/ragdoll.gd")

const ENGINE := 2500.0
const BRAKE := 25.0
const HANDBRAKE := 40.0
const MAX_STEER := 0.55
const TOP_SPEED := 45.0
const HIT_SPEED := 4.0

var paint := Color(0.8, 0.1, 0.1)
var driver: Node = null


func _ready() -> void:
	add_to_group("cars")
	mass = 1200
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.7, 4.2)
	shape.shape = box
	shape.position.y = 0.75
	add_child(shape)

	_part(Vector3(1.8, 0.55, 4.2), Vector3(0, 0.7, 0), paint)
	_part(Vector3(1.6, 0.5, 2.1), Vector3(0, 1.22, -0.2), Color(0.08, 0.1, 0.12))
	_part(Vector3(1.5, 0.08, 1.9), Vector3(0, 1.5, -0.2), paint)
	for x in [-0.6, 0.6]:
		_part(Vector3(0.35, 0.15, 0.05), Vector3(x, 0.8, 2.11), Color(1, 0.95, 0.8), true)
		_part(Vector3(0.35, 0.12, 0.05), Vector3(x, 0.8, -2.11), Color(0.8, 0.05, 0.05), true)

	for w in [[-0.85, 1.35, true], [0.85, 1.35, true], [-0.85, -1.35, false], [0.85, -1.35, false]]:
		var wheel := VehicleWheel3D.new()
		wheel.position = Vector3(w[0], 0.5, w[1])
		wheel.use_as_steering = w[2]
		wheel.use_as_traction = not w[2]
		wheel.wheel_radius = 0.36
		wheel.wheel_rest_length = 0.2
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 40.0
		wheel.suspension_max_force = 12000.0
		wheel.damping_compression = 1.5
		wheel.damping_relaxation = 2.0
		wheel.wheel_friction_slip = 3.0
		wheel.wheel_roll_influence = 0.1
		var tyre := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.36
		cylinder.bottom_radius = 0.36
		cylinder.height = 0.25
		tyre.mesh = cylinder
		tyre.material_override = Ragdoll.material(Color(0.06, 0.06, 0.06))
		tyre.rotation.z = PI / 2
		wheel.add_child(tyre)
		add_child(wheel)

	var bumper := Area3D.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 4
	var bumper_shape := CollisionShape3D.new()
	var bumper_box := BoxShape3D.new()
	bumper_box.size = Vector3(2.2, 1.6, 4.8)
	bumper_shape.shape = bumper_box
	bumper_shape.position.y = 0.8
	bumper.add_child(bumper_shape)
	bumper.body_entered.connect(_on_bumper_body_entered)
	add_child(bumper)


func _part(size: Vector3, pos: Vector3, color: Color, glow := false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	if glow:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mesh.material_override = mat
	else:
		mesh.material_override = Ragdoll.material(color)
	mesh.position = pos
	add_child(mesh)


func start_driving(new_driver: Node) -> void:
	driver = new_driver


func _physics_process(delta: float) -> void:
	if driver == null:
		engine_force = 0.0
		steering = 0.0
		brake = 5.0
		return

	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(global_basis.z)
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer_target := Input.get_axis("move_right", "move_left") * lerpf(MAX_STEER, 0.2, clampf(speed / 30.0, 0, 1))
	steering = move_toward(steering, steer_target, 2.0 * delta)

	engine_force = 0.0
	brake = 1.0
	if Input.is_action_pressed("jump"):
		brake = HANDBRAKE
	elif throttle > 0.0:
		engine_force = throttle * ENGINE if speed < TOP_SPEED else 0.0
		brake = 0.0
	elif throttle < 0.0:
		if forward_speed > 1.0:
			brake = BRAKE
		else:
			engine_force = throttle * ENGINE * 0.5
			brake = 0.0

	if Input.is_action_just_pressed("interact"):
		# Driver gets out on the left (+X when facing +Z)
		var exit_pos := global_position + global_basis.x * 1.8 + Vector3.UP * 0.3
		var leaving := driver
		driver = null
		leaving.exit_car(exit_pos)


func _on_bumper_body_entered(body: Node3D) -> void:
	if body.has_method("hit_by_vehicle") and linear_velocity.length() > HIT_SPEED:
		body.hit_by_vehicle(linear_velocity)
