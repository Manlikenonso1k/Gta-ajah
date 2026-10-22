extends VehicleBody3D
## Drivable car. Forward is +Z (VehicleBody3D convention).
## Knocks characters into ragdolls when it hits them at speed.

const ENGINE := 2500.0
const BRAKE := 25.0
const HANDBRAKE := 40.0
const MAX_STEER := 0.55
const TOP_SPEED := 45.0
const HIT_SPEED := 4.0
const REST_LENGTH := 0.2

## Kenney Car Kit models (CC0): body plus four wheels named wheel-front-left
## etc., facing +Z, about 2/3 real size.
const MODELS := {
	"sedan": preload("res://assets/models/cars/kenney/sedan.glb"),
	"sedan_sports": preload("res://assets/models/cars/kenney/sedan-sports.glb"),
	"hatchback": preload("res://assets/models/cars/kenney/hatchback-sports.glb"),
	"suv": preload("res://assets/models/cars/kenney/suv.glb"),
	"suv_luxury": preload("res://assets/models/cars/kenney/suv-luxury.glb"),
	"taxi": preload("res://assets/models/cars/kenney/taxi.glb"),
	"police": preload("res://assets/models/cars/kenney/police.glb"),
	"van": preload("res://assets/models/cars/kenney/van.glb"),
	"delivery": preload("res://assets/models/cars/kenney/delivery.glb"),
	"truck": preload("res://assets/models/cars/kenney/truck.glb"),
	"ambulance": preload("res://assets/models/cars/kenney/ambulance.glb"),
}
const MODEL_SCALE := 1.5

var model := "sedan"
var driver: Node = null
var _half_width := 0.9


func _ready() -> void:
	add_to_group("cars")
	mass = 1200
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0)

	var visual: Node3D = MODELS[model].instantiate()
	visual.scale = Vector3.ONE * MODEL_SCALE
	add_child(visual)

	# Collision box follows the body, raised a little so it doesn't scrape the road
	var body: MeshInstance3D = visual.get_node("body")
	var aabb := body.get_aabb()
	aabb.position = (aabb.position + body.position) * MODEL_SCALE
	aabb.size *= MODEL_SCALE
	_half_width = aabb.size.x / 2
	var clearance := 0.15
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size - Vector3(0, clearance, 0)
	shape.shape = box
	shape.position = aabb.get_center() + Vector3(0, clearance / 2, 0)
	add_child(shape)

	# Each wheel mesh moves into a VehicleWheel3D so it spins and steers
	for wheel_mesh: MeshInstance3D in visual.find_children("wheel-*", "MeshInstance3D"):
		var front := wheel_mesh.name.begins_with("wheel-front")
		var wheel := VehicleWheel3D.new()
		# Suspension settles about halfway under the car's weight
		wheel.position = wheel_mesh.position * MODEL_SCALE + Vector3(0, REST_LENGTH / 2, 0)
		wheel.use_as_steering = front
		wheel.use_as_traction = not front
		wheel.wheel_radius = wheel_mesh.get_aabb().size.y / 2 * MODEL_SCALE
		wheel.wheel_rest_length = REST_LENGTH
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 40.0
		wheel.suspension_max_force = 12000.0
		wheel.damping_compression = 1.5
		wheel.damping_relaxation = 2.0
		wheel.wheel_friction_slip = 3.0
		wheel.wheel_roll_influence = 0.1
		add_child(wheel)
		wheel_mesh.reparent(wheel, false)
		wheel_mesh.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * MODEL_SCALE), Vector3.ZERO)

	var bumper := Area3D.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 4
	var bumper_shape := CollisionShape3D.new()
	var bumper_box := BoxShape3D.new()
	bumper_box.size = aabb.size + Vector3(0.4, 0.4, 0.6)
	bumper_shape.shape = bumper_box
	bumper_shape.position = aabb.get_center()
	bumper.add_child(bumper_shape)
	bumper.body_entered.connect(_on_bumper_body_entered)
	add_child(bumper)


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
		var exit_pos := global_position + global_basis.x * (_half_width + 0.8) + Vector3.UP * 0.3
		var leaving := driver
		driver = null
		leaving.exit_car(exit_pos)


func _on_bumper_body_entered(body: Node3D) -> void:
	if body.has_method("hit_by_vehicle") and linear_velocity.length() > HIT_SPEED:
		body.hit_by_vehicle(linear_velocity)
