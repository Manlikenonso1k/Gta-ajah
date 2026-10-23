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
## Tuning below is for a 1200 kg car; forces scale with each model's mass
const BASE_MASS := 1200.0

const VehicleModel = preload("res://scripts/vehicle_model.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")

## Key into VehicleModel.MODELS
var model := "corolla"
var driver: Node = null
## Approximate engine speed for the HUD; this prototype has no gearbox model.
var estimated_rpm := 850.0
var _half_width := 0.9
var _heft := 1.0
var _exit_pending := false
var _driver_visual: Node3D
var _driver_limbs := {}
var _driver_seat := Vector3(0.2, 0.85, 0.35)
var _door_rig: Node3D
var _door_animation: AnimationPlayer
var _door_clip := ""


func _ready() -> void:
	add_to_group("cars")
	var data := VehicleModel.build(model)
	mass = data["mass"]
	_heft = mass / BASE_MASS
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.25, 0)

	for part in data["body"]:
		add_child(_mesh_instance(part))
	_setup_door_rig(data)

	# Collision box follows the body, raised a little so it doesn't scrape the
	# road. Some models have stray geometry below the tyres; ignore it.
	var aabb: AABB = data["body_aabb"]
	var bottom := maxf(aabb.position.y, 0.0) + 0.15
	_half_width = aabb.size.x / 2
	_driver_seat = Vector3(0.22, clampf(aabb.position.y + 0.1, 0.3, 0.5), 0.35)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x, aabb.end.y - bottom, aabb.size.z)
	shape.shape = box
	shape.position = Vector3(aabb.get_center().x, (aabb.end.y + bottom) / 2, aabb.get_center().z)
	add_child(shape)

	for w in data["wheels"]:
		var wheel := VehicleWheel3D.new()
		# Suspension settles about halfway under the car's weight
		wheel.position = w["center"] + Vector3(0, REST_LENGTH / 2, 0)
		wheel.use_as_steering = w["front"]
		wheel.use_as_traction = not w["front"]
		wheel.wheel_radius = w["radius"]
		wheel.wheel_rest_length = REST_LENGTH
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 40.0
		wheel.suspension_max_force = 12000.0 * _heft
		wheel.damping_compression = 1.5
		wheel.damping_relaxation = 2.0
		wheel.wheel_friction_slip = 3.0
		wheel.wheel_roll_influence = 0.1
		add_child(wheel)
		for part in w["parts"]:
			wheel.add_child(_mesh_instance(part))

	var bumper := Area3D.new()
	bumper.collision_layer = 0
	bumper.collision_mask = 4
	var bumper_shape := CollisionShape3D.new()
	var bumper_box := BoxShape3D.new()
	bumper_box.size = box.size + Vector3(0.4, 0.6, 0.6)
	bumper_shape.shape = bumper_box
	bumper_shape.position = shape.position
	bumper.add_child(bumper_shape)
	bumper.body_entered.connect(_on_bumper_body_entered)
	add_child(bumper)


func start_driving(new_driver: Node) -> void:
	driver = new_driver
	_exit_pending = false
	_driver_visual = Node3D.new()
	_driver_visual.position = _driver_seat
	_driver_visual.scale = Vector3.ONE * 0.55
	_driver_visual.rotation.y = PI
	add_child(_driver_visual)
	_driver_limbs = Ragdoll.build_visual(_driver_visual, new_driver.colors)
	Ragdoll.animate_driver(_driver_limbs, 0.0)


func driver_door_point() -> Vector3:
	return Vector3(_half_width + 0.62, 0.0, _driver_seat.z * 0.5)


func driver_seat_point() -> Vector3:
	return _driver_seat


func animate_driver_door(open: bool) -> void:
	if _door_animation == null or _door_clip.is_empty():
		return
	_door_animation.speed_scale = 3.5
	if open:
		_door_animation.play(_door_clip)
	else:
		_door_animation.play(_door_clip, -1.0, -1.0, true)
	await _door_animation.animation_finished


func finish_driver_exit() -> void:
	if is_instance_valid(_driver_visual):
		_driver_visual.queue_free()
	_driver_visual = null
	_driver_limbs.clear()


func _setup_door_rig(data: Dictionary) -> void:
	# Only the Sprinter asset has a real door clip. Keep its imported hierarchy
	# as an invisible rig and show just the animated door meshes over the cut body.
	var packed: PackedScene = load(data["source_path"])
	var rig: Node3D = packed.instantiate()
	rig.transform = data["source_transform"]
	var stack: Array[Node] = [rig]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is AnimationPlayer:
			var clips: PackedStringArray = node.get_animation_list()
			if not clips.is_empty():
				_door_animation = node
				_door_clip = clips[0]
		if node is MeshInstance3D:
			var ancestor: Node = node
			var is_door := false
			while ancestor != rig:
				if "porte" in str(ancestor.name).to_lower():
					is_door = true
					break
				ancestor = ancestor.get_parent()
			node.visible = is_door
		for child in node.get_children():
			stack.append(child)
	if _door_animation == null:
		rig.free()
		return
	_door_rig = rig
	add_child(_door_rig)


func _physics_process(delta: float) -> void:
	if driver == null:
		engine_force = 0.0
		steering = 0.0
		brake = 5.0 * _heft
		estimated_rpm = move_toward(estimated_rpm, 850.0, 1800.0 * delta)
		return

	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(global_basis.z)
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer_target := Input.get_axis("move_right", "move_left") * lerpf(MAX_STEER, 0.2, clampf(speed / 30.0, 0, 1))
	steering = move_toward(steering, steer_target, 2.0 * delta)
	var speed_ratio := clampf(speed / TOP_SPEED, 0.0, 1.0)
	var rpm_target := 850.0 + speed_ratio * 4600.0 + maxf(throttle, 0.0) * 1500.0 * (1.0 - speed_ratio * 0.65)
	estimated_rpm = lerpf(estimated_rpm, rpm_target, 1.0 - exp(-4.0 * delta))
	if not _driver_limbs.is_empty():
		Ragdoll.animate_driver(_driver_limbs, steering)

	engine_force = 0.0
	brake = 1.0 * _heft
	if Input.is_action_pressed("jump"):
		brake = HANDBRAKE * _heft
	elif throttle > 0.0:
		engine_force = throttle * ENGINE * _heft if speed < TOP_SPEED else 0.0
		brake = 0.0
	elif throttle < 0.0:
		if forward_speed > 1.0:
			brake = BRAKE * _heft
		else:
			engine_force = throttle * ENGINE * _heft * 0.5
			brake = 0.0

	if Input.is_action_just_pressed("interact"):
		_exit_pending = true
	if _exit_pending:
		engine_force = 0.0
		brake = BRAKE * _heft
		if speed <= 0.8:
			_exit_pending = false
			var exit_pos := global_position + global_basis.x * (_half_width + 0.8) + Vector3.UP * 0.15
			var leaving: Node = driver
			driver = null
			leaving.begin_exit_car(self, exit_pos)


func _on_bumper_body_entered(body: Node3D) -> void:
	if body.has_method("hit_by_vehicle") and linear_velocity.length() > HIT_SPEED:
		body.hit_by_vehicle(linear_velocity)


func _mesh_instance(part: Array) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = part[0]
	mesh.transform = part[1]
	return mesh
