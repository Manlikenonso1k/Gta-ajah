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
var persistent_id := ""
var original_spawn_transform := Transform3D.IDENTITY
var driver: Node = null
## Engine speed estimate driven by road speed, traction, gear ratio, and shifts.
var estimated_rpm := 850.0
var redline_warning := false
var ai_enabled := false
var ai_route: Array[Vector3] = []
var ai_route_index := 0
var ai_target_speed := 0.0
var _half_width := 0.9
var _half_length := 2.2
var _heft := 1.0
var _exit_pending := false
var _driver_visual: Node3D
var _driver_limbs := {}
var _driver_seat := Vector3(0.2, 0.85, 0.35)
var _door_rig: Node3D
var _door_animation: AnimationPlayer
var _door_clip := ""
var _handling := {}
var current_gear := 1
var _shift_timer := 0.0
var _base_mass := 1200.0
var _driver_weight := 0.0
var _target_driver_weight := 0.0
var _wheels: Array[VehicleWheel3D] = []
var _wheel_grips: Array[float] = []
var _traction_blend := 1.0
var _driven_contact_ratio := 1.0
var _ai_blocked := false
var _ai_stuck_time := 0.0


func _ready() -> void:
	add_to_group("cars")
	var data := VehicleModel.build(model)
	mass = data["mass"]
	_base_mass = mass
	_heft = mass / BASE_MASS
	_handling = data.get("handling", {})
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, float(_handling.get("center_of_mass_y", 0.18 + 0.1 * clampf(_heft / 10.0, 0.0, 1.0))), 0)
	angular_damp = float(_handling.get("angular_damp", 1.2 + 0.8 * clampf(_heft / 10.0, 0.0, 1.0)))

	for part in data["body"]:
		add_child(_mesh_instance(part))
	_setup_door_rig(data)

	# Collision box follows the body, raised a little so it doesn't scrape the
	# road. Some models have stray geometry below the tyres; ignore it.
	var aabb: AABB = data["body_aabb"]
	var bottom := maxf(aabb.position.y, 0.0) + 0.15
	_half_width = aabb.size.x / 2
	_half_length = aabb.size.z / 2
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
		wheel.suspension_stiffness = float(_handling.get("suspension", 40.0))
		wheel.suspension_max_force = 12000.0 * _heft
		wheel.damping_compression = float(_handling.get("compression", 1.5))
		wheel.damping_relaxation = float(_handling.get("relaxation", 2.0))
		wheel.wheel_friction_slip = float(_handling.get("grip", 3.0))
		wheel.wheel_roll_influence = float(_handling.get("roll_influence", 0.1))
		add_child(wheel)
		_wheels.append(wheel)
		_wheel_grips.append(wheel.wheel_friction_slip)
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
	_target_driver_weight = 75.0
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


func exterior_entry_points(from_world: Vector3) -> Array[Vector3]:
	# Passenger/rear approaches route around a vehicle end, then along the
	# driver's side. CharacterBody3D collision remains enabled during this walk.
	var local_from := to_local(from_world)
	var side_x := _half_width + 0.85
	var front_z := maxf(_half_length + 1.15, _driver_seat.z + 1.5)
	var rear_z := -maxf(_half_length + 1.15, absf(_driver_seat.z) + 1.5)
	var front_cost := absf(local_from.z - front_z) + absf(local_from.x - side_x)
	var rear_cost := absf(local_from.z - rear_z) + absf(local_from.x - side_x)
	var end_z := front_z if front_cost < rear_cost else rear_z
	var points: Array[Vector3] = []
	if local_from.x < 0.0:
		points.append(to_global(Vector3(local_from.x, 0.0, end_z)))
		points.append(to_global(Vector3(side_x, 0.0, end_z)))
	else:
		points.append(to_global(Vector3(side_x, 0.0, local_from.z)))
	points.append(to_global(driver_door_point()))
	return points


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
	_target_driver_weight = 0.0
	if is_instance_valid(_driver_visual):
		_driver_visual.queue_free()
	_driver_visual = null
	_driver_limbs.clear()
	var world_root := get_parent()
	if world_root.has_method("save_vehicle_states"):
		world_root.save_vehicle_states()


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
				var clip: Animation = node.get_animation(_door_clip)
				for track in clip.get_track_count():
					# Porte_avnt_1 is the Sprinter's +X/front driver's door.
					clip.track_set_enabled(track, "Porte_avnt_1" in str(clip.track_get_path(track)))
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
	_driver_weight = move_toward(_driver_weight, _target_driver_weight, 180.0 * delta)
	mass = _base_mass + _driver_weight
	_heft = mass / BASE_MASS
	var load_fraction := _driver_weight / maxf(_base_mass + _driver_weight, 1.0)
	var base_com_y: float = _handling.get("center_of_mass_y", 0.18 + 0.1 * clampf(_base_mass / 13000.0, 0.0, 1.0))
	center_of_mass = Vector3(0.0, lerpf(base_com_y, _driver_seat.y, load_fraction), 0.0)
	for wheel in _wheels:
		wheel.suspension_max_force = 12000.0 * _heft
	if driver == null and not ai_enabled:
		engine_force = 0.0
		steering = 0.0
		brake = 5.0 * _heft
		estimated_rpm = move_toward(estimated_rpm, 850.0, 1800.0 * delta)
		return

	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(global_basis.z)
	var throttle := _ai_throttle() if ai_enabled else Input.get_axis("move_back", "move_forward")
	var steer_input := _ai_steer() if ai_enabled else Input.get_axis("move_right", "move_left")
	if ai_enabled:
		_ai_stuck_time = _ai_stuck_time + delta if speed < 0.6 else 0.0
		if _ai_stuck_time > 4.0 and not ai_route.is_empty():
			ai_route_index = (ai_route_index + 1) % ai_route.size()
			_ai_stuck_time = 0.0
	if ai_enabled and not ai_route.is_empty() and global_position.distance_to(ai_route[ai_route_index % ai_route.size()]) < 6.0:
		ai_route_index = (ai_route_index + 1) % ai_route.size()
	var contact_count := 0
	var driven_count := 0
	for i in _wheels.size():
		if _wheels[i].is_in_contact():
			contact_count += 1
			if i >= 2:
				driven_count += 1
	var contact_target := lerpf(0.28, 1.0, float(contact_count) / maxf(float(_wheels.size()), 1.0))
	var drive_target := lerpf(0.2, 1.0, float(driven_count) / 2.0)
	_traction_blend = move_toward(_traction_blend, contact_target, 1.8 * delta)
	_driven_contact_ratio = move_toward(_driven_contact_ratio, drive_target, 2.8 * delta)
	for i in _wheels.size():
		_wheels[i].wheel_friction_slip = _wheel_grips[i] * lerpf(0.35, 1.0, _traction_blend)
	var max_steer: float = _handling.get("max_steer", MAX_STEER)
	var speed_limit: float = _handling.get("top_speed", TOP_SPEED)
	var steer_target := steer_input * lerpf(max_steer, max_steer * 0.36, clampf(speed / 30.0, 0, 1)) * _traction_blend
	steering = move_toward(steering, steer_target, float(_handling.get("steer_response", 2.0)) * delta)
	var gears: Array = _handling.get("gears", [1.0])
	var ratios: Array = _handling.get("ratios", [1.0])
	_shift_timer = maxf(0.0, _shift_timer - delta)
	var ratio: float = float(ratios[mini(current_gear - 1, ratios.size() - 1)])
	var redline: float = _handling.get("redline", 6500.0)
	var rpm_target := 850.0 + clampf(speed / maxf(speed_limit, 1.0), 0.0, 1.0) * (redline - 1200.0) * ratio
	if throttle > 0.0 and speed > 1.0:
		rpm_target = maxf(rpm_target, 1200.0 + throttle * 1800.0 * ratio + 2200.0 * (1.0 - _driven_contact_ratio))
	if _shift_timer > 0.0:
		rpm_target *= 0.72
	if rpm_target > float(_handling.get("shift_rpm", 5100.0)) and current_gear < gears.size():
		current_gear += 1
		_shift_timer = 0.35
	elif speed < 5.0 and current_gear > 1:
		current_gear = 1
		_shift_timer = 0.2
	estimated_rpm = lerpf(estimated_rpm, clampf(rpm_target, 850.0, redline), 1.0 - exp(-5.0 * delta))
	redline_warning = estimated_rpm >= redline * 0.97
	if not _driver_limbs.is_empty():
		Ragdoll.animate_driver(_driver_limbs, steering)

	engine_force = 0.0
	brake = 1.0 * _heft
	if not ai_enabled and Input.is_action_pressed("jump"):
		brake = HANDBRAKE * _heft
	elif throttle > 0.0:
		var accel: float = _handling.get("accel", ENGINE / BASE_MASS)
		var gear_power: float = float(gears[mini(current_gear - 1, gears.size() - 1)])
		engine_force = throttle * mass * accel * gear_power * _driven_contact_ratio if speed < speed_limit else 0.0
		brake = 0.0
	elif throttle < 0.0:
		if forward_speed > 1.0:
			brake = float(_handling.get("brake", BRAKE)) * _heft
		else:
			engine_force = throttle * mass * float(_handling.get("accel", ENGINE / BASE_MASS)) * 0.5 * _driven_contact_ratio
			brake = 0.0
	if _ai_blocked:
		engine_force = 0.0
		brake = float(_handling.get("brake", BRAKE)) * _heft

	if not ai_enabled and Input.is_action_just_pressed("interact"):
		_exit_pending = true
	if _exit_pending:
		engine_force = 0.0
		brake = float(_handling.get("brake", BRAKE)) * _heft
		if speed <= 0.8:
			_exit_pending = false
			var exit_pos := global_position + global_basis.x * (_half_width + 0.8) + Vector3.UP * 0.15
			var leaving: Node = driver
			driver = null
			leaving.begin_exit_car(self, exit_pos)


func set_driver_weight_loaded(loaded: bool) -> void:
	_target_driver_weight = 75.0 if loaded else 0.0


func _ai_throttle() -> float:
	_ai_blocked = false
	if ai_route.is_empty():
		return 0.0
	var target: Vector3 = ai_route[ai_route_index % ai_route.size()]
	var desired := ai_target_speed
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8,
		global_position + global_basis.z * 11.0 + Vector3.UP * 0.8, 1 | 2 | 4)
	query.exclude = [get_rid()]
	if not space.intersect_ray(query).is_empty():
		_ai_blocked = true
		return 0.0
	var speed := linear_velocity.length()
	if speed > desired + 1.0:
		return -0.25
	return clampf((desired - speed) * 0.25, 0.0, 1.0)


func _ai_steer() -> float:
	if ai_route.is_empty():
		return 0.0
	var target: Vector3 = ai_route[ai_route_index % ai_route.size()]
	var local_target := global_basis.inverse() * (target - global_position)
	return clampf(-atan2(local_target.x, maxf(local_target.z, 0.1)) * 0.85, -1.0, 1.0)


func _on_bumper_body_entered(body: Node3D) -> void:
	if body.has_method("hit_by_vehicle") and linear_velocity.length() > HIT_SPEED:
		body.hit_by_vehicle(linear_velocity)


func _mesh_instance(part: Array) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = part[0]
	mesh.transform = part[1]
	return mesh
