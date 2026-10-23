extends CharacterBody3D
## Wandering pedestrian. Turns into a ragdoll when hit by a car.

const Ragdoll = preload("res://scripts/ragdoll.gd")
const HumanoidWalk = preload("res://scripts/humanoid_walk.gd")

const SPEED := 1.4
const VISIBLE_DISTANCE := 120.0
## Real legs need about 1.8 steps per second at walking speed; the phase
## below was tuned for the stick figure's shorter stride
const WALK_CADENCE := 1.8

var colors: Dictionary
var wander_origin := Vector3.ZERO
var character_id := "PED_LEGACY_PROC_001"
var character_display_name := "Legacy Procedural Pedestrian"
var model_path := "procedural://scripts/ragdoll.gd"
var appearance_category := "unclassified_procedural"
var outfit_id := "legacy_colour_variant"
var model_scene: PackedScene
var character_scale := 1.0
var collision_radius := 0.3
var collision_height := 1.8
var _model_animation_player: AnimationPlayer
var _walker: RefCounted

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
	capsule.radius = collision_radius
	capsule.height = collision_height
	shape.shape = capsule
	shape.position.y = collision_height * 0.5
	add_child(shape)
	var visual := Node3D.new()
	visual.name = "CharacterVisual"
	add_child(visual)
	if model_scene != null:
		var model := model_scene.instantiate()
		model.name = "ImportedCharacterModel"
		model.scale = Vector3.ONE * character_scale
		# Imported models face +Z (glTF); characters in this game face -Z
		model.rotation.y = PI
		visual.add_child(model)
		for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
			# Too small to read beyond this, and skinned meshes are costly on phones
			mesh.visibility_range_end = VISIBLE_DISTANCE
		_walker = HumanoidWalk.create(model)
		_model_animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _walker != null and _model_animation_player != null:
			# The procedural walk drives the skeleton; a clip would fight it
			_model_animation_player.stop()
			_model_animation_player = null
		_set_model_animation("walk")
	else:
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
		if not _limbs.is_empty():
			Ragdoll.animate(_limbs, _phase, 0.0)
		elif _walker != null:
			_walker.pose(_phase * WALK_CADENCE, 0.0)
		else:
			_set_model_animation("idle")
		return
	velocity.x = _direction.x * SPEED
	velocity.z = _direction.z * SPEED
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(-_direction.x, -_direction.z), 6.0 * delta)
	var actual_speed := Vector2(velocity.x, velocity.z).length()
	_phase += actual_speed * 2.2 * delta
	if not _limbs.is_empty():
		Ragdoll.animate(_limbs, _phase, clampf(actual_speed / SPEED, 0.0, 1.0) * 0.6)
	elif _walker != null:
		_walker.pose(_phase * WALK_CADENCE, clampf(actual_speed / SPEED, 0.0, 1.0))
	else:
		_set_model_animation("walk")


func _set_model_animation(wanted: String) -> void:
	if _model_animation_player == null:
		return
	var fallback := ""
	for animation_name: StringName in _model_animation_player.get_animation_list():
		var lower := String(animation_name).to_lower()
		if lower.contains(wanted):
			if _model_animation_player.current_animation != animation_name:
				_model_animation_player.play(animation_name)
			return
		if fallback.is_empty() and (lower.contains("idle") or lower.contains("walk")):
			fallback = animation_name
	if not fallback.is_empty():
		if _model_animation_player.current_animation != fallback:
			_model_animation_player.play(fallback)


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
