extends CharacterBody3D
## Wandering pedestrian. Turns into a ragdoll when hit by a car.

const Ragdoll = preload("res://scripts/ragdoll.gd")

const SPEED := 1.4

var colors: Dictionary
var wander_origin := Vector3.ZERO

var _direction := Vector3.FORWARD
var _turn_timer := 0.0
var _limbs: Dictionary
var _phase := 0.0
var _pause_timer := 0.0
var _avoid_timer := 0.0


func _ready() -> void:
	add_to_group("pedestrians")
	if wander_origin == Vector3.ZERO:
		wander_origin = global_position
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	var visual := Node3D.new()
	add_child(visual)
	_limbs = Ragdoll.build_visual(visual, colors)
	_phase = randf() * TAU
	_pick_direction()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_turn_timer -= delta
	_avoid_timer -= delta
	_pause_timer = maxf(0.0, _pause_timer - delta)
	if _turn_timer <= 0.0 or is_on_wall():
		_pick_direction()
	if global_position.distance_to(wander_origin) > 20.0:
		_direction = (wander_origin - global_position).normalized()
	elif _avoid_timer <= 0.0:
		_avoid_timer = 0.3
		_avoid_obstacles()
		_avoid_traffic()
	if _pause_timer <= 0.0 and _turn_timer > 0.0 and randf() < delta * 0.015:
		_pause_timer = randf_range(0.6, 1.8)
	if _pause_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, SPEED * 5.0 * delta)
		move_and_slide()
		_phase += delta
		Ragdoll.animate(_limbs, _phase, 0.0)
		return
	velocity.x = _direction.x * SPEED
	velocity.z = _direction.z * SPEED
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(-_direction.x, -_direction.z), 6.0 * delta)
	var actual_speed := Vector2(velocity.x, velocity.z).length()
	_phase += actual_speed * 2.2 * delta
	Ragdoll.animate(_limbs, _phase, clampf(actual_speed / SPEED, 0.0, 1.0) * 0.6)


func _avoid_traffic() -> void:
	var nearest_distance := 8.0
	var escape := Vector3.ZERO
	for vehicle in get_tree().get_nodes_in_group("traffic"):
		var away: Vector3 = global_position - vehicle.global_position
		var distance: float = away.length()
		if distance >= nearest_distance or vehicle.linear_velocity.length() < 2.0:
			continue
		if away.normalized().dot(vehicle.linear_velocity.normalized()) > 0.25:
			nearest_distance = distance
			escape = away.normalized()
	if escape.length_squared() > 0.0:
		_direction = Vector3(escape.x, 0.0, escape.z).normalized()


func _avoid_obstacles() -> void:
	if _direction.length_squared() < 0.1:
		return
	var ahead := global_position + _direction.normalized() * 1.2 + Vector3.UP * 0.65
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.38
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, ahead)
	query.collision_mask = 1 | 2
	query.exclude = [get_rid()]
	if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return
	var side := Vector3(-_direction.z, 0.0, _direction.x).normalized()
	var home := wander_origin - global_position
	if side.dot(home) < 0.0:
		side = -side
	_direction = side


func _pick_direction() -> void:
	if global_position.distance_to(wander_origin) > 20.0:
		_direction = (wander_origin - global_position).normalized()
	else:
		_direction = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_turn_timer = randf_range(3.0, 8.0)


func hit_by_vehicle(vehicle_velocity: Vector3) -> void:
	Ragdoll.spawn(get_parent(), global_transform, colors, vehicle_velocity * 0.8 + Vector3.UP * 3.0)
	queue_free()
