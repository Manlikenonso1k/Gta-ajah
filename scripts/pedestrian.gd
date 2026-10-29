extends CharacterBody3D
## Wandering pedestrian. Turns into a ragdoll when hit by a car.
##
## Animation: a model imported with the standard skeleton (GeneralSkeleton,
## see scripts/skeleton_map.gd) is animated with real motion-capture clips
## through scripts/locomotion.gd (an AnimationTree blending idle -> walk ->
## jog -> run). A model whose skeleton can't take the clips falls back to the
## procedural scripts/humanoid_walk.gd; a pedestrian with no imported model at
## all uses the procedural body in scripts/ragdoll.gd.
##
## Movement: when the pavement graph is available this delegates walking to
## scripts/pedestrian_navigation.gd (owner: traffic), which calls
## set_locomotion(speed, state, facing) each physics frame. Otherwise it falls
## back to bounded wandering. Either way set_locomotion is the single entry
## point that drives the animation and turns the body.

const Ragdoll = preload("res://scripts/ragdoll.gd")
const RealisticRagdoll = preload("res://scripts/realistic_ragdoll.gd")
const HumanoidWalk = preload("res://scripts/humanoid_walk.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const AnimationSets = preload("res://scripts/animation_sets.gd")
const PedestrianNavigation = preload("res://scripts/pedestrian_navigation.gd")
const PavementGraph = preload("res://scripts/pavement_graph.gd")
const Registry = preload("res://scripts/pedestrian_registry.gd")

## A comfortable walking pace. Kept close to the mocap walk clip's natural
## ground speed so playback matches without the time-scale clamp, which would
## otherwise slide the feet.
const SPEED := 1.25
const VISIBLE_DISTANCE := 120.0
const BAG_MODEL := "res://assets/models/buildings/carry_bag.glb"
## Real legs need about 1.8 steps per second at walking speed; the phase
## below was tuned for the stick figure's shorter stride
const WALK_CADENCE := 1.8
## Beyond this distance from the camera, advance the AnimationTree only every
## ANIM_LOD_INTERVAL frames (with the accumulated time, so the feet keep pace).
## Beyond VISIBLE_DISTANCE the mesh is hidden and main.gd stops processing us.
const ANIM_LOD_DISTANCE := 40.0
const ANIM_LOD_INTERVAL := 3
## Seconds a held pose (scripts/street_places.gd people) animates in full
## before its cheaper update rate starts
const HELD_SETTLE := 1.0
## Traffic's T3 drives pedestrians along the pavement graph through the
## PedestrianNavigation hook below. Set false to fall back to the old bounded
## wander; set_locomotion and all of the animation work the same either way.
const USE_PAVEMENT_NAVIGATION := true

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
var tags: Array = []
var gender := ""
## Clips this pedestrian uses (scripts/animation_sets.gd), picked once by ID
var clip_set := {}
## Replaces slots of the picked clip set, e.g. {"sit": "mx/Slump"}
var clip_overrides := {}
## People placed at a spot (scripts/street_places.gd) instead of walking the
## pavements: "" walks as normal; "idle", "sit" or "lie" stays put in that
## state. Cheap: no navigation and no physics movement.
var anchor_state := ""
## With anchor_state set, walk this loop instead of standing: each stop is
## {"p": Vector3, "wait": seconds, "hide": bool (out of sight while waiting,
## e.g. inside a shop), "bag": bool (carry a bag from here on), "face": Node3D
## (turn to it while waiting), "free": bool (leave the game on arrival)}
var loop_path: Array = []

## Pavement navigation (owner: traffic). Non-null once the pavement graph is
## ready; world_systems_test.gd reads this property.
var navigation: RefCounted

var _loco: RefCounted              ## mocap locomotion (scripts/locomotion.gd) or null
var _model: Node3D                 ## the imported glTF model, if any
var _model_animation_player: AnimationPlayer
var _walker: RefCounted            ## procedural HumanoidWalk fallback
var _limbs: Dictionary             ## procedural ragdoll body (no imported model)

var _direction := Vector3.FORWARD
var _facing := Vector3.FORWARD
var _turn_timer := 0.0
var _phase := 0.0
var _pause_timer := 0.0
var _avoid_timer := 0.0
var _last_delta := 1.0 / 60.0
var _anim_accum := 0.0
var _lod_counter := 0
var _ragdolled := false
var _loop_index := 0
var _loop_wait := 0.0
var _settle_time := 0.0
var _bag: Node3D


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
	var entry := Registry.by_id(character_id)
	if tags.is_empty() and not entry.is_empty():
		tags = entry.get("tags", [])
	if gender == "":
		gender = entry.get("gender", "")
	if model_scene != null:
		var model := model_scene.instantiate()
		model.name = "ImportedCharacterModel"
		model.scale = Vector3.ONE * character_scale
		# Imported models face +Z (glTF); characters in this game face -Z
		model.rotation.y = PI
		visual.add_child(model)
		_model = model
		for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
			# Too small to read beyond this, and skinned meshes are costly on phones
			mesh.visibility_range_end = VISIBLE_DISTANCE
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(get_instance_id())
		clip_set = AnimationSets.pick(character_id, gender, tags)
		for slot: String in clip_overrides:
			if Locomotion.has_clip(clip_overrides[slot]):
				clip_set[slot] = clip_overrides[slot]
		_loco = Locomotion.create(model, clip_set, rng)
		if _loco == null:
			push_warning("pedestrian %s: model can't use the shared clips; using the procedural walk" % character_id)
			# No standard skeleton: procedural swing, and silence any baked clip
			_walker = HumanoidWalk.create(model)
			_model_animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if _walker != null and _model_animation_player != null:
				_model_animation_player.stop()
				_model_animation_player = null
			_set_model_animation("walk")
	else:
		_limbs = Ragdoll.build_visual(visual, colors)
	_phase = randf() * TAU
	_facing = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	_pick_direction()
	# Delegate walking to traffic's pavement navigation (T3) once enabled.
	if anchor_state != "":
		if not loop_path.is_empty():
			global_position = loop_path[0].p
	elif USE_PAVEMENT_NAVIGATION:
		var graph := PavementGraph.shared()
		if graph != null and not graph.points.is_empty():
			navigation = PedestrianNavigation.new(self)


## The clips in use, for the F4 inspector.
func animation_summary() -> String:
	if _loco != null:
		return "%s: %s" % [clip_set.get("set", "?"), _loco.summary()]
	return "procedural walk" if _walker != null else "stick figure"


func _physics_process(delta: float) -> void:
	if _ragdolled:
		return
	_last_delta = delta
	if anchor_state != "":
		_anchored(delta)
		_advance_animation(delta)
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	if navigation != null:
		# Navigation sets velocity.x/z and calls set_locomotion(speed, state, facing)
		navigation.physics_step(delta)
	else:
		_wander(delta)
	move_and_slide()
	_advance_animation(delta)


## A placed person: holds its state, or walks its loop with no physics
## (the loops are laid out clear of obstacles).
func _anchored(delta: float) -> void:
	if loop_path.is_empty():
		set_locomotion(0.0, anchor_state, Vector3.INF)
		return
	var stop: Dictionary = loop_path[_loop_index]
	if _loop_wait > 0.0:
		_loop_wait -= delta
		if _loop_wait <= 0.0:
			visible = true
			_loop_index = (_loop_index + 1) % loop_path.size()
		var face: Variant = stop.get("face")
		var toward := Vector3.INF
		if face is Node3D and is_instance_valid(face):
			toward = (face as Node3D).global_position - global_position
		set_locomotion(0.0, "idle", toward)
		return
	var to_stop: Vector3 = stop.p - global_position
	to_stop.y = 0.0
	if to_stop.length() < 0.15:
		if stop.get("free", false):
			queue_free()
			return
		_loop_wait = float(stop.get("wait", 0.0)) + 0.001
		if stop.get("hide", false):
			visible = false
		if stop.has("bag"):
			set_carrying(bool(stop.bag))
		return
	var step := minf(SPEED * delta, to_stop.length())
	global_position += to_stop.normalized() * step
	set_locomotion(SPEED, "walk", to_stop)


## Someone holding a spot (lying, sitting, standing at a stall) moves little:
## after settling into the pose, every third frame up close, a fixed pose
## beyond ANIM_LOD_DISTANCE, and no updates at all once lying still.
func _advance_held(delta: float) -> void:
	_anim_accum += delta
	_settle_time += delta
	if _settle_time > HELD_SETTLE and (anchor_state == "lie" or _distance_to_view() > ANIM_LOD_DISTANCE):
		_anim_accum = 0.0
		return
	_lod_counter += 1
	if _settle_time <= HELD_SETTLE or _lod_counter >= ANIM_LOD_INTERVAL:
		_loco.advance(_anim_accum)
		_anim_accum = 0.0
		_lod_counter = 0


## Shows or hides a shopping bag in the right hand.
func set_carrying(carrying: bool) -> void:
	if _bag == null and carrying and _model != null:
		var skeleton := _model.find_children("*", "Skeleton3D", true, false)
		if skeleton.is_empty() or not ResourceLoader.exists(BAG_MODEL):
			return
		var attach := BoneAttachment3D.new()
		attach.bone_name = "RightHand"
		skeleton[0].add_child(attach)
		var bag := (load(BAG_MODEL) as PackedScene).instantiate() as Node3D
		# The model is scaled (Renderpeople files are in centimetres); keep the bag 1:1
		bag.scale = Vector3.ONE / maxf(character_scale, 0.001)
		attach.add_child(bag)
		_bag = attach
	if _bag != null:
		_bag.visible = carrying


## Bounded random wandering, used when no pavement graph is available. Computes
## a direction and speed and routes them through set_locomotion like navigation.
func _wander(delta: float) -> void:
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
		set_locomotion(Vector2(velocity.x, velocity.z).length(), "idle", Vector3.INF)
		return
	velocity.x = _direction.x * SPEED
	velocity.z = _direction.z * SPEED
	var actual_speed := Vector2(velocity.x, velocity.z).length()
	set_locomotion(actual_speed, "walk", _direction)


## The single entry point movement code uses (navigation or the wander above).
## `speed` is the ground speed in m/s; `state` is one of locomotion's states
## (idle, walk, jog, run, wait_at_kerb). `facing` turns the body smoothly; pass
## Vector3.INF to leave the heading unchanged.
func set_locomotion(speed: float, state: String, facing := Vector3.INF) -> void:
	if facing != Vector3.INF and Vector2(facing.x, facing.z).length_squared() > 0.0001:
		_facing = Vector3(facing.x, 0.0, facing.z).normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-_facing.x, -_facing.z), clampf(8.0 * _last_delta, 0.0, 1.0))
	if _loco != null:
		_loco.set_locomotion(speed, state)


## Advances whatever drives the pose. The mocap AnimationTree is advanced less
## often far from the camera; the procedural fallbacks are cheap and run every
## frame.
func _advance_animation(delta: float) -> void:
	if _loco != null:
		if anchor_state != "" and loop_path.is_empty():
			_advance_held(delta)
			return
		if _distance_to_view() > ANIM_LOD_DISTANCE:
			_anim_accum += delta
			_lod_counter += 1
			if _lod_counter >= ANIM_LOD_INTERVAL:
				_loco.advance(_anim_accum)
				_anim_accum = 0.0
				_lod_counter = 0
		else:
			_loco.advance(_anim_accum + delta)
			_anim_accum = 0.0
			_lod_counter = 0
		return
	var actual_speed := Vector2(velocity.x, velocity.z).length()
	if not _limbs.is_empty():
		_phase += maxf(actual_speed, 0.0) * 2.2 * delta if actual_speed > 0.05 else delta
		Ragdoll.animate(_limbs, _phase, clampf(actual_speed / SPEED, 0.0, 1.0) * 0.6)
	elif _walker != null:
		_phase += (actual_speed * 2.2 * delta) if actual_speed > 0.05 else delta
		_walker.pose(_phase * WALK_CADENCE, clampf(actual_speed / SPEED, 0.0, 1.0))
	else:
		_set_model_animation("walk" if actual_speed > 0.2 else "idle")


func _distance_to_view() -> float:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		return global_position.distance_to(camera.global_position)
	return 0.0


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


## Hit by a car. Realistic ragdoll on the model's own skeleton (continues from
## the current animated pose, so there is no jump); the procedural body falls
## back to the old stick ragdoll. car.gd passes the impact point and mass.
func hit_by_vehicle(vehicle_velocity: Vector3, impact_point := Vector3.INF, vehicle_mass := 1200.0) -> void:
	if _ragdolled:
		return
	_ragdolled = true
	set_physics_process(false)
	if _loco != null:
		_loco.stop()
	var spawned: Node = null
	if _model != null:
		var point: Vector3 = impact_point if impact_point != Vector3.INF else global_position
		var character_velocity := Vector3(velocity.x, 0.0, velocity.z)
		# RealisticRagdoll reparents the model, so freeing the pedestrian is correct
		spawned = RealisticRagdoll.spawn(_model, get_parent(), character_velocity, vehicle_velocity, point, vehicle_mass)
	if spawned == null:
		# Only a pedestrian with no standard-skeleton model (e.g. the procedural
		# placeholder) falls back to the old stick ragdoll.
		if _model != null:
			push_warning("realistic ragdoll failed for %s; using stick fallback" % character_id)
		Ragdoll.spawn(get_parent(), global_transform, colors, vehicle_velocity * 0.8 + Vector3.UP * 3.0)
	queue_free()


## A pedestrian for registry `character`, ready to add to the scene (main.gd
## and scripts/street_places.gd use this).
static func from_entry(character: Dictionary, rng: RandomNumberGenerator) -> CharacterBody3D:
	var ped = load("res://scripts/pedestrian.gd").new()
	ped.character_id = character.id
	ped.character_display_name = character.display_name
	ped.model_path = character.model_path
	ped.appearance_category = character.appearance_category
	ped.outfit_id = character.outfit_id
	ped.character_scale = float(character.get("scale", 1.0))
	ped.collision_radius = float(character.get("collision_radius", 0.3))
	ped.collision_height = float(character.get("collision_height", 1.8))
	if str(character.model_path).begins_with("res://"):
		var model_resource: Resource = load(character.model_path)
		if model_resource is PackedScene:
			ped.model_scene = model_resource
	ped.colors = Ragdoll.random_colors(rng)
	# The knocked-down stick fallback is procedural; at least match the skin
	if character.appearance_category == "black_african":
		ped.colors["skin"] = Color(0.24, 0.14, 0.09).lerp(Color(0.36, 0.22, 0.14), rng.randf())
	elif character.appearance_category == "white":
		ped.colors["skin"] = Color(0.85, 0.68, 0.58)
	return ped
