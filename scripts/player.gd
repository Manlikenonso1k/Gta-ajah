extends CharacterBody3D
## On-foot player: walk/run/jump relative to the camera, enter cars,
## and go ragdoll (R key or hit by a car), getting back up after a few seconds.

const Ragdoll = preload("res://scripts/ragdoll.gd")

const WALK_SPEED := 3.0
const RUN_SPEED := 7.0
const JUMP_VELOCITY := 5.0
const ENTER_DISTANCE := 4.0
const RAGDOLL_TIME := 4.0
enum InteractionState { ON_FOOT, APPROACHING_DOOR, OPENING_DOOR, ENTERING_SEAT, DRIVING, EXITING, RAGDOLL }

var camera_rig: Node3D
var colors := {"skin": Color(0.3, 0.18, 0.11), "shirt": Color(0.1, 0.45, 0.25), "pants": Color(0.2, 0.25, 0.4)}
var car: Node = null

var _limbs: Dictionary
var _phase := 0.0
var _ragdoll_pelvis: RigidBody3D = null
var _ragdoll_timer := 0.0
var _enter_cooldown := 0.0
var _interaction_busy := false
var _visual: Node3D
var interaction_state := InteractionState.ON_FOOT


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_visual = Node3D.new()
	add_child(_visual)
	_limbs = Ragdoll.build_visual(_visual, colors)
	camera_rig.follow(self, 1.6)


func _physics_process(delta: float) -> void:
	_enter_cooldown -= delta
	if _ragdoll_pelvis != null:
		_ragdoll_timer -= delta
		if _ragdoll_timer <= 0.0 or not is_instance_valid(_ragdoll_pelvis):
			_get_up()
		return
	if interaction_state != InteractionState.ON_FOOT:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := Vector3.FORWARD.rotated(Vector3.UP, camera_rig.yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, camera_rig.yaw)
	var direction := (right * input.x - forward * input.y).normalized()
	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED

	velocity.x = move_toward(velocity.x, direction.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 30.0 * delta)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	move_and_slide()

	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 10.0 * delta)
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_phase += ground_speed * 2.2 * delta
	Ragdoll.animate(_limbs, _phase, clampf(ground_speed / RUN_SPEED * 1.5, 0, 1))

	if Input.is_action_just_pressed("ragdoll"):
		go_ragdoll(velocity + Vector3.UP * 2.0)
	elif Input.is_action_just_pressed("interact") and _enter_cooldown <= 0.0:
		_try_enter_car()


func _try_enter_car() -> void:
	if interaction_state != InteractionState.ON_FOOT:
		return
	var nearest: Node3D = null
	for c in get_tree().get_nodes_in_group("cars"):
		var d := global_position.distance_to(c.global_position)
		if d < ENTER_DISTANCE and (nearest == null or d < global_position.distance_to(nearest.global_position)):
			nearest = c
	if nearest == null:
		return
	_interaction_busy = true
	interaction_state = InteractionState.APPROACHING_DOOR
	velocity = Vector3.ZERO
	var arrived := false
	for attempt in 3:
		if not is_instance_valid(nearest) or interaction_state != InteractionState.APPROACHING_DOOR:
			break
		var destination: Vector3 = nearest.to_global(nearest.driver_door_point())
		var vehicle_start: Vector3 = nearest.global_position
		var route := _find_exterior_path(destination)
		if route.is_empty():
			break
		var blocked := false
		for waypoint: Vector3 in route:
			if interaction_state != InteractionState.APPROACHING_DOOR or not is_instance_valid(nearest):
				blocked = true
				break
			if not await _walk_to(waypoint):
				blocked = true
				break
			if global_position.distance_to(destination) > 4.0 and nearest.global_position.distance_to(vehicle_start) > 0.6:
				blocked = true
				break
		if not blocked:
			arrived = true
			break
	if not arrived:
		if interaction_state == InteractionState.APPROACHING_DOOR:
			interaction_state = InteractionState.ON_FOOT
			Ragdoll.animate(_limbs, _phase, 0.0)
		_interaction_busy = false
		_enter_cooldown = 0.5
		return
	interaction_state = InteractionState.OPENING_DOOR
	await _reach_for_door()
	if interaction_state != InteractionState.OPENING_DOOR or not is_instance_valid(nearest):
		if interaction_state == InteractionState.OPENING_DOOR:
			interaction_state = InteractionState.ON_FOOT
			_interaction_busy = false
		return
	await nearest.animate_driver_door(true)
	if interaction_state != InteractionState.OPENING_DOOR or not is_instance_valid(nearest):
		if interaction_state == InteractionState.OPENING_DOOR:
			interaction_state = InteractionState.ON_FOOT
			_interaction_busy = false
		return
	# The final short move goes through the open doorway; hide the standing mesh
	# progressively so the head never passes visibly through the roof.
	interaction_state = InteractionState.ENTERING_SEAT
	var seat_point: Vector3 = nearest.to_global(nearest.driver_seat_point())
	collision_layer = 0
	collision_mask = 0
	var enter_tween := create_tween()
	enter_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	enter_tween.tween_property(self, "global_position", seat_point, 0.32)
	enter_tween.parallel().tween_property(_visual, "scale", Vector3(0.15, 0.15, 0.15), 0.32)
	await enter_tween.finished
	if interaction_state != InteractionState.ENTERING_SEAT:
		return
	if not is_instance_valid(nearest):
		_visual.scale = Vector3.ONE
		interaction_state = InteractionState.ON_FOOT
		_interaction_busy = false
		_set_active(true)
		return
	await nearest.animate_driver_door(false)
	if interaction_state != InteractionState.ENTERING_SEAT:
		return
	if not is_instance_valid(nearest):
		_interaction_busy = false
		_visual.scale = Vector3.ONE
		interaction_state = InteractionState.ON_FOOT
		_set_active(true)
		return
	global_rotation.y = nearest.global_rotation.y + PI
	car = nearest
	interaction_state = InteractionState.DRIVING
	_set_active(false)
	car.start_driving(self)
	camera_rig.follow(car, 1.4, true)
	_interaction_busy = false


func begin_exit_car(vehicle: Node3D, position_: Vector3) -> void:
	_interaction_busy = true
	interaction_state = InteractionState.EXITING
	await vehicle.animate_driver_door(true)
	global_position = vehicle.to_global(vehicle.driver_seat_point())
	global_rotation.y = vehicle.global_rotation.y + PI
	velocity = Vector3.ZERO
	# Keep the character out of rigid-body collision until fully clear of the
	# vehicle's box collider; restoring it at the seat caused the launch impulse.
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	vehicle.finish_driver_exit()
	_visual.scale = Vector3(0.15, 0.15, 0.15)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", position_, 0.42)
	tween.parallel().tween_property(_visual, "scale", Vector3.ONE, 0.42)
	await tween.finished
	_set_active(true)
	await vehicle.animate_driver_door(false)
	car = null
	interaction_state = InteractionState.ON_FOOT
	_enter_cooldown = 0.4
	_interaction_busy = false
	camera_rig.follow(self, 1.6)


func _walk_to(target: Vector3) -> bool:
	var elapsed := 0.0
	var last_distance := INF
	var stuck_time := 0.0
	while is_instance_valid(self) and interaction_state == InteractionState.APPROACHING_DOOR and global_position.distance_to(target) > 0.32 and elapsed < 12.0:
		var offset := target - global_position
		offset.y = 0.0
		var direction := offset.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 10.0 * get_physics_process_delta_time())
		velocity.x = direction.x * WALK_SPEED
		velocity.z = direction.z * WALK_SPEED
		if not is_on_floor():
			velocity.y += get_gravity().y * get_physics_process_delta_time()
		move_and_slide()
		var distance := global_position.distance_to(target)
		var moved := last_distance - distance if last_distance < INF else WALK_SPEED * get_physics_process_delta_time()
		_phase += maxf(moved, 0.0) * 2.2
		Ragdoll.animate(_limbs, _phase, clampf(velocity.length() / WALK_SPEED, 0.0, 1.0))
		stuck_time = stuck_time + get_physics_process_delta_time() if distance >= last_distance - 0.005 else 0.0
		if stuck_time > 0.8:
			velocity = Vector3.ZERO
			return false
		last_distance = distance
		elapsed += get_physics_process_delta_time()
		await get_tree().physics_frame
	velocity = Vector3.ZERO
	return interaction_state == InteractionState.APPROACHING_DOOR and global_position.distance_to(target) <= 0.45


func _find_exterior_path(destination: Vector3) -> Array[Vector3]:
	const CELL := 1.0
	const MARGIN := 12.0
	var min_x := minf(global_position.x, destination.x) - MARGIN
	var min_z := minf(global_position.z, destination.z) - MARGIN
	var width := ceili((maxf(global_position.x, destination.x) + MARGIN - min_x) / CELL)
	var height := ceili((maxf(global_position.z, destination.z) + MARGIN - min_z) / CELL)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, width, height)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(min_x, min_z)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.29
	capsule.height = 1.72
	query.shape = capsule
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var walk_y := global_position.y + 0.87
	for x in width:
		for z in height:
			var world := Vector3(min_x + (x + 0.5) * CELL, walk_y, min_z + (z + 0.5) * CELL)
			query.transform = Transform3D(Basis.IDENTITY, world)
			if not space.intersect_shape(query, 1).is_empty():
				grid.set_point_solid(Vector2i(x, z), true)
	var start := Vector2i(clampi(floori((global_position.x - min_x) / CELL), 0, width - 1), clampi(floori((global_position.z - min_z) / CELL), 0, height - 1))
	var finish := Vector2i(clampi(floori((destination.x - min_x) / CELL), 0, width - 1), clampi(floori((destination.z - min_z) / CELL), 0, height - 1))
	grid.set_point_solid(start, false)
	grid.set_point_solid(finish, false)
	var ids := grid.get_id_path(start, finish)
	var route: Array[Vector3] = []
	for cell in ids:
		var point: Vector2 = grid.get_point_position(cell)
		route.append(Vector3(point.x, global_position.y, point.y))
	if not route.is_empty():
		route[route.size() - 1] = Vector3(destination.x, global_position.y, destination.z)
	return route


func _reach_for_door() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for limb_name in ["arm_r", "arm_l"]:
		var limb: Node3D = _limbs[limb_name]
		tween.parallel().tween_property(limb, "rotation:x", -0.9, 0.2)
	await tween.finished


func hit_by_vehicle(vehicle_velocity: Vector3) -> void:
	go_ragdoll(vehicle_velocity * 0.8 + Vector3.UP * 3.0)


func go_ragdoll(launch_velocity: Vector3) -> void:
	interaction_state = InteractionState.RAGDOLL
	_interaction_busy = true
	_ragdoll_pelvis = Ragdoll.spawn(get_parent(), global_transform, colors, launch_velocity)
	_ragdoll_timer = RAGDOLL_TIME
	visible = false
	collision_layer = 0
	collision_mask = 1
	camera_rig.follow(_ragdoll_pelvis, 0.6)


func _get_up() -> void:
	if is_instance_valid(_ragdoll_pelvis):
		global_position = Vector3(_ragdoll_pelvis.global_position.x, maxf(_ragdoll_pelvis.global_position.y, 0.1), _ragdoll_pelvis.global_position.z)
		_ragdoll_pelvis.get_parent().queue_free()
	_ragdoll_pelvis = null
	interaction_state = InteractionState.ON_FOOT
	_interaction_busy = false
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	camera_rig.follow(self, 1.6)


func _set_active(active: bool) -> void:
	visible = active
	collision_layer = 4 if active else 0
	collision_mask = (1 | 2 | 4) if active else 0
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
