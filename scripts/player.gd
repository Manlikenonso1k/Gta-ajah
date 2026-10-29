extends CharacterBody3D
## On-foot player: walk/run/jump relative to the camera, enter cars,
## and go ragdoll (R key or hit by a car), getting back up after a few seconds.
##
## The body is the realistic model named in assets/characters/player/player.json
## (edit "model_path" there to swap it for any rigged humanoid .glb on the
## standard skeleton). It is animated with the shared mocap library through
## scripts/locomotion.gd: idle, walk, jog and sprint by ground speed, Jump_Start,
## Fall and Jump_Land in the air, and GetUp after a ragdoll. It ragdolls on its
## own skeleton (scripts/realistic_ragdoll.gd) and sits in cars through the
## car's scripts/vehicle_occupants.gd (Sit_Enter, Driving with both hands on the
## steering wheel, Sit_Exit). Without a usable model it falls back to the
## procedural stick figure of scripts/ragdoll.gd.

const Ragdoll = preload("res://scripts/ragdoll.gd")
const RealisticRagdoll = preload("res://scripts/realistic_ragdoll.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")
const PLAYER_JSON := "res://assets/characters/player/player.json"

const WALK_SPEED := 3.0
const RUN_SPEED := 7.0
const JUMP_VELOCITY := 5.0
const ENTER_DISTANCE := 4.0
const RAGDOLL_TIME := 4.0
enum InteractionState { ON_FOOT, APPROACHING_DOOR, OPENING_DOOR, ENTERING_SEAT, DRIVING, EXITING, RAGDOLL }

var camera_rig: Node3D
var colors := {"skin": Color(0.3, 0.18, 0.11), "shirt": Color(0.1, 0.45, 0.25), "pants": Color(0.2, 0.25, 0.4)}
var car: Node = null
## player.json contents (id, display name, model path, licence)
var model_info := {}

var _limbs: Dictionary
var _phase := 0.0
var _ragdoll_pelvis: RigidBody3D = null
var _ragdoll_timer := 0.0
var _enter_cooldown := 0.0
var _interaction_busy := false
var _visual: Node3D
var interaction_state := InteractionState.ON_FOOT

## The realistic model and its locomotion (null when using the stick figure)
var _model: Node3D
var _loco: RefCounted
## The realistic ragdoll while down
var _ragdoll: Node3D
var _getting_up := false
## In the air: seconds airborne and the air clip playing ("" = none)
var _air_time := 0.0
var _air_clip := ""
var _landing_time := 0.0


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
	_visual.name = "PlayerVisual"
	add_child(_visual)
	_load_model()
	if _loco == null:
		_limbs = Ragdoll.build_visual(_visual, colors)
	camera_rig.follow(self, 1.6)


## Loads the model named in player.json under the visual node.
func _load_model() -> void:
	var text := FileAccess.get_file_as_string(PLAYER_JSON)
	var info: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not info is Dictionary:
		push_warning("player.json missing or invalid; using the stick figure")
		return
	model_info = info
	var path := str(info.get("model_path", ""))
	if not ResourceLoader.exists(path):
		push_warning("player model not found: " + path)
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.name = "PlayerModel"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var loco := Locomotion.create(model, {"idle": "Idle"}, rng)
	if loco == null:
		push_warning("player model has no standard skeleton; using the stick figure")
		model.free()
		return
	_model = model
	_loco = loco
	_attach_model(model)


## Puts the model under the visual node, turned to face the player's -Z.
func _attach_model(model: Node3D) -> void:
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	_visual.add_child(model)
	# glTF models face +Z; the player faces -Z
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for mixer: AnimationMixer in model.find_children("*", "AnimationMixer", true, false):
		mixer.active = true


func _physics_process(delta: float) -> void:
	_enter_cooldown -= delta
	if _ragdoll_pelvis != null or _getting_up:
		_update_ragdoll(delta)
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
	var jumped := false
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jumped = true
	move_and_slide()

	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 10.0 * delta)
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_animate_on_foot(delta, ground_speed, jumped)

	if Input.is_action_just_pressed("ragdoll"):
		go_ragdoll(velocity + Vector3.UP * 2.0)
	elif Input.is_action_just_pressed("interact") and _enter_cooldown <= 0.0:
		_try_enter_car()


## Ground gaits by speed, plus the jump, fall and landing clips.
func _animate_on_foot(delta: float, ground_speed: float, jumped := false) -> void:
	if _loco == null:
		_phase += ground_speed * 2.2 * delta
		Ragdoll.animate(_limbs, _phase, clampf(ground_speed / RUN_SPEED * 1.5, 0, 1))
		return
	if jumped:
		_loco.play_action("Jump_Start")
		_air_clip = "Jump_Start"
		_air_time = 0.0
	elif is_on_floor():
		if not _air_clip.is_empty():
			# A real fall lands with Jump_Land when standing; when moving, run on
			if _air_time > 0.3 and ground_speed < 0.5:
				_loco.play_action("Jump_Land")
				_landing_time = 0.6
			else:
				_fade_out_action()
			_air_clip = ""
		_air_time = 0.0
		if _landing_time > 0.0:
			_landing_time -= delta
			if ground_speed > 0.5 or _landing_time <= 0.0:
				_fade_out_action()
				_landing_time = 0.0
	else:
		_air_time += delta
		# Past the top of the jump, or off a ledge: the falling loop
		if (_air_clip == "Jump_Start" and velocity.y < 1.0) or (_air_clip.is_empty() and _air_time > 0.3):
			_loco.play_action("Fall")
			_air_clip = "Fall"
	var state := "idle"
	if ground_speed > 2.2:
		state = "run"
	elif ground_speed > 0.15:
		state = "walk"
	_loco.set_locomotion(ground_speed, state)
	_loco.advance(delta)


func _fade_out_action() -> void:
	if _loco != null and _loco.is_action_playing():
		_loco.tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _try_enter_car() -> void:
	if interaction_state != InteractionState.ON_FOOT:
		return
	# In reach of the car's middle or of its driver's door (a 12 m coach's
	# door is further than ENTER_DISTANCE from its middle)
	var nearest: Node3D = null
	var nearest_d := INF
	for c in get_tree().get_nodes_in_group("cars"):
		var d := global_position.distance_to(c.global_position)
		if c.has_method("driver_door_point"):
			d = minf(d, global_position.distance_to(c.to_global(c.driver_door_point())))
		if d < ENTER_DISTANCE and d < nearest_d:
			nearest = c
			nearest_d = d
	if nearest == null:
		return
	_interaction_busy = true
	interaction_state = InteractionState.APPROACHING_DOOR
	velocity = Vector3.ZERO
	_fade_out_action()
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
			_animate_on_foot(0.0, 0.0)
		_interaction_busy = false
		_enter_cooldown = 0.5
		return
	interaction_state = InteractionState.OPENING_DOOR
	await _reach_for_door(nearest)
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
	interaction_state = InteractionState.ENTERING_SEAT
	var seat_point: Vector3 = nearest.to_global(nearest.driver_seat_point())
	collision_layer = 0
	collision_mask = 0
	var occupants: Node3D = nearest.get("occupants")
	if _loco != null and occupants != null and not occupants.cabin.is_empty():
		# Sit down through the doorway with Sit_Enter, then take the wheel.
		# Sitting down commits to the car: it is the player's from here and the
		# controls are live while the sit-down finishes (asking to get out
		# meanwhile waits for it).
		occupants.player_enter(_model, _loco, nearest.driver_door_point())
		_take_driver_seat(nearest, seat_point)
		while is_instance_valid(nearest) and occupants.is_busy():
			await get_tree().process_frame
		if not is_instance_valid(nearest):
			_recover_model_after_lost_car()
			return
		await nearest.animate_driver_door(false)
		_interaction_busy = false
		return
	else:
		# The final short move goes through the open doorway; hide the standing
		# mesh progressively so the head never passes visibly through the roof.
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
		_recover_model_after_lost_car()
		return
	_take_driver_seat(nearest, seat_point)
	_interaction_busy = false


## The player becomes the car's driver: hidden on foot, controls go to the car.
func _take_driver_seat(vehicle: Node3D, seat_point: Vector3) -> void:
	global_position = seat_point
	global_rotation.y = vehicle.global_rotation.y + PI
	car = vehicle
	interaction_state = InteractionState.DRIVING
	_set_active(false)
	car.start_driving(self)
	camera_rig.follow(car, 1.4, true)


func begin_exit_car(vehicle: Node3D, position_: Vector3) -> void:
	_interaction_busy = true
	interaction_state = InteractionState.EXITING
	await vehicle.animate_driver_door(true)
	var occupants: Node3D = vehicle.get("occupants")
	if occupants != null and occupants.player_seated:
		# Hands off the wheel, turn to the door and stand up with Sit_Exit
		var door: Vector3 = vehicle.driver_door_point()
		var model: Node3D = await occupants.player_exit(door)
		var outward: Vector3 = vehicle.global_basis.x
		global_position = vehicle.to_global(door) + Vector3.UP * 0.05
		rotation = Vector3(0.0, atan2(-outward.x, -outward.z), 0.0)
		velocity = Vector3.ZERO
		process_mode = Node.PROCESS_MODE_INHERIT
		visible = true
		vehicle.finish_driver_exit()
		if model != null:
			_attach_model(model)
			_loco.set_locomotion(0.0, "idle")
		_set_active(true)
	else:
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


## The car was freed while the player sat down in it (and took the model with
## it): reload the model and stand where the player is.
func _recover_model_after_lost_car() -> void:
	_model = null
	_loco = null
	_load_model()
	if _loco == null and _limbs.is_empty():
		_limbs = Ragdoll.build_visual(_visual, colors)
	interaction_state = InteractionState.ON_FOOT
	_interaction_busy = false
	_set_active(true)


func _walk_to(target: Vector3) -> bool:
	var elapsed := 0.0
	var last_distance := INF
	var stuck_time := 0.0
	while is_instance_valid(self) and interaction_state == InteractionState.APPROACHING_DOOR and global_position.distance_to(target) > 0.32 and elapsed < 12.0:
		var offset := target - global_position
		offset.y = 0.0
		var direction := offset.normalized()
		var dt := get_physics_process_delta_time()
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 10.0 * dt)
		velocity.x = direction.x * WALK_SPEED
		velocity.z = direction.z * WALK_SPEED
		if not is_on_floor():
			velocity.y += get_gravity().y * dt
		move_and_slide()
		var distance := global_position.distance_to(target)
		var moved := last_distance - distance if last_distance < INF else WALK_SPEED * dt
		if _loco != null:
			_animate_on_foot(dt, Vector2(velocity.x, velocity.z).length())
		else:
			_phase += maxf(moved, 0.0) * 2.2
			Ragdoll.animate(_limbs, _phase, clampf(velocity.length() / WALK_SPEED, 0.0, 1.0))
		stuck_time = stuck_time + dt if distance >= last_distance - 0.005 else 0.0
		if stuck_time > 0.8:
			velocity = Vector3.ZERO
			return false
		last_distance = distance
		elapsed += dt
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


## At the door: the realistic player steps onto the door point and turns his
## back to the seat (Sit_Enter sits down backwards); the stick figure reaches
## for the handle.
func _reach_for_door(vehicle: Node3D = null) -> void:
	if _loco != null and vehicle != null:
		var door: Vector3 = vehicle.to_global(vehicle.driver_door_point())
		door.y = global_position.y
		var outward: Vector3 = vehicle.global_basis.x
		var start_yaw := rotation.y
		var end_yaw := atan2(-outward.x, -outward.z)
		var start_pos := global_position
		var t := 0.0
		while t < 0.2 and interaction_state == InteractionState.OPENING_DOOR:
			var dt := get_physics_process_delta_time()
			t += dt
			var k := smoothstep(0.0, 1.0, t / 0.2)
			rotation.y = lerp_angle(start_yaw, end_yaw, k)
			global_position = start_pos.lerp(door, k)
			_animate_on_foot(dt, 0.0)
			await get_tree().physics_frame
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for limb_name in ["arm_r", "arm_l"]:
		var limb: Node3D = _limbs[limb_name]
		tween.parallel().tween_property(limb, "rotation:x", -0.9, 0.2)
	await tween.finished


func hit_by_vehicle(vehicle_velocity: Vector3, impact_point := Vector3.INF, vehicle_mass := 1200.0) -> void:
	if _ragdoll_pelvis != null or _getting_up:
		return
	var point := impact_point if impact_point != Vector3.INF else global_position
	_start_ragdoll(Vector3(velocity.x, 0.0, velocity.z), vehicle_velocity, point, vehicle_mass, vehicle_velocity * 0.8 + Vector3.UP * 3.0)


func go_ragdoll(launch_velocity: Vector3) -> void:
	if _ragdoll_pelvis != null or _getting_up:
		return
	# No vehicle: the body is thrown with the given velocity
	_start_ragdoll(launch_velocity, Vector3.ZERO, global_position, 0.0, launch_velocity)


## Realistic ragdoll on the player's own model; the stick ragdoll only if the
## model is missing or can't ragdoll.
func _start_ragdoll(body_velocity: Vector3, impact_velocity: Vector3, impact_point: Vector3, vehicle_mass: float, stick_launch: Vector3) -> void:
	interaction_state = InteractionState.RAGDOLL
	_interaction_busy = true
	_ragdoll_timer = RAGDOLL_TIME
	_air_clip = ""
	_landing_time = 0.0
	var spawned: Node3D = null
	if _model != null:
		_loco.stop()
		spawned = RealisticRagdoll.spawn(_model, get_parent(), body_velocity, impact_velocity, impact_point, vehicle_mass)
	if spawned != null:
		_ragdoll = spawned
		_ragdoll.auto_remove = false
		_ragdoll_pelvis = _ragdoll.pelvis
	else:
		if _model != null:
			push_warning("player: realistic ragdoll failed; using the stick ragdoll")
			_loco.tree.active = true
		_ragdoll_pelvis = Ragdoll.spawn(get_parent(), global_transform, colors, stick_launch)
	visible = false
	collision_layer = 0
	collision_mask = 1
	camera_rig.follow(_ragdoll_pelvis, 0.6)


func _update_ragdoll(delta: float) -> void:
	_ragdoll_timer -= delta
	if _ragdoll != null or _getting_up:
		# Lie still, then play GetUp so the player is up after RAGDOLL_TIME
		if not _getting_up and (_ragdoll_timer <= _get_up_length() or not is_instance_valid(_ragdoll_pelvis)):
			_begin_get_up()
		if _getting_up:
			_loco.advance(delta)
			if _ragdoll_timer <= 0.0:
				_finish_get_up()
		return
	if _ragdoll_timer <= 0.0 or not is_instance_valid(_ragdoll_pelvis):
		_get_up()


func _get_up_length() -> float:
	var lib := Locomotion.library()
	return lib.get_animation("GetUp").length if lib != null and lib.has_animation("GetUp") else 1.0


## Takes the model back from the ragdoll where it lies and starts GetUp, lined
## up so the clip's lying body matches the ragdoll's (hips on the pelvis, head
## the same way).
func _begin_get_up() -> void:
	_getting_up = true
	var pelvis_pos: Vector3 = _ragdoll.pelvis.global_position
	var head_pos: Vector3 = _ragdoll.bodies["head"].global_position
	var ground := pelvis_pos.y - 0.15
	var query := PhysicsRayQueryParameters3D.create(pelvis_pos + Vector3.UP, pelvis_pos + Vector3.DOWN * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		ground = hit.position.y
	var model: Node3D = _ragdoll.take_model(_visual)
	_ragdoll = null
	_ragdoll_pelvis = null
	_attach_model(model)
	# The ragdoll wrote every body bone; the clips leave out tracks that never
	# move, so those bones would keep the fallen pose. Start from the rest pose.
	SkeletonMap.skeleton_of(model).reset_bone_poses()
	global_position = Vector3(pelvis_pos.x, ground, pelvis_pos.z)
	rotation = Vector3.ZERO
	visible = true
	# Fire the clip and let its short fade-in finish, then see how it lies
	_loco.set_locomotion(0.0, "idle")
	_loco.play_action("GetUp")
	_loco.advance(0.2)
	var sk := SkeletonMap.skeleton_of(model)
	var clip_hips := sk.to_global(sk.get_bone_global_pose(sk.find_bone("Hips")).origin)
	var clip_head := sk.to_global(sk.get_bone_global_pose(sk.find_bone("Head")).origin)
	var clip_dir := Vector3(clip_head.x - clip_hips.x, 0.0, clip_head.z - clip_hips.z)
	var body_dir := Vector3(head_pos.x - pelvis_pos.x, 0.0, head_pos.z - pelvis_pos.z)
	if clip_dir.length_squared() > 0.001 and body_dir.length_squared() > 0.001:
		rotation.y = clip_dir.signed_angle_to(body_dir, Vector3.UP)
	var hips_now := sk.to_global(sk.get_bone_global_pose(sk.find_bone("Hips")).origin)
	global_position += Vector3(pelvis_pos.x - hips_now.x, 0.0, pelvis_pos.z - hips_now.z)
	camera_rig.follow(self, 1.6)


func _finish_get_up() -> void:
	_getting_up = false
	interaction_state = InteractionState.ON_FOOT
	_interaction_busy = false
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 4
	collision_mask = 1 | 2 | 4


## Stick-figure fallback: stand up at the pelvis.
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
