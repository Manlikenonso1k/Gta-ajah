extends SceneTree
## Ragdolls every pedestrian model and checks the result after 5 s:
##   godot --headless --path . --script tests/ragdoll_models_test.gd
## For each character: the realistic mesh is still visible and no stick figure
## was made, no body is below the ground or NaN, joints stay together (each
## joint's two ends within 2 cm), and the ragdoll settles within 5 s. Also
## checks the player-style recovery blend on one character.

const Registry = preload("res://scripts/pedestrian_registry.gd")
const Walk = preload("res://scripts/humanoid_walk.gd")
const RealisticRagdoll = preload("res://scripts/realistic_ragdoll.gd")

const SECONDS := 5.0
const MAX_JOINT_GAP := 0.02


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	_run.call_deferred()


func _ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	root.add_child(ground)


## A character standing at `position` like pedestrian.gd sets it up, mid-stride.
func _character(entry: Dictionary, position: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = position
	root.add_child(holder)
	var model: Node3D = load(entry.model_path).instantiate()
	model.scale = Vector3.ONE * float(entry.scale)
	model.rotation.y = PI
	holder.add_child(model)
	var walker = Walk.create(model)
	if walker != null:
		walker.pose(1.3, 1.0)
	return model


func _run() -> void:
	_ground()
	var failures := 0
	var cases := []
	var entries := Registry.all()
	# Hit from the side by a 1,300 kg car at 40 km/h, a few at bus mass
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var model := _character(entry, Vector3(i * 6.0, 0, 0))
		await physics_frame
		var heavy := i % 4 == 3
		var impact := Vector3(0, 0, -11.0)
		var ragdoll := RealisticRagdoll.spawn(model, root, Vector3(0, 0, -1.2), impact,
			model.global_position + Vector3(0.2, 0.6, 1.0), 11000.0 if heavy else 1300.0)
		if ragdoll == null:
			print("FAIL %s: no ragdoll (missing standard skeleton)" % entry.id)
			failures += 1
			continue
		cases.append({"entry": entry, "ragdoll": ragdoll, "gap": 0.0, "heavy": heavy, "start": model.global_position})

	var frames := int(SECONDS * Engine.physics_ticks_per_second)
	for frame in frames:
		await physics_frame
		if frame > 15:
			for c: Dictionary in cases:
				c.gap = maxf(c.gap, c.ragdoll.joint_error())

	for c: Dictionary in cases:
		var ragdoll: Node3D = c.ragdoll
		var problems := []
		var model: Node3D = ragdoll.model
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty() or not meshes.all(func(m: MeshInstance3D) -> bool: return m.is_visible_in_tree()):
			problems.append("mesh hidden")
		for mesh: MeshInstance3D in ragdoll.find_children("*", "MeshInstance3D", true, false):
			if not model.is_ancestor_of(mesh):
				problems.append("stick-figure mesh %s" % mesh.name)
				break
		var lowest := INF
		for body: RigidBody3D in ragdoll.bodies.values():
			if not body.global_position.is_finite():
				problems.append("NaN in %s" % body.name)
			lowest = minf(lowest, body.global_position.y)
		if lowest < 0.0:
			problems.append("body below ground (%.2f m)" % lowest)
		if c.gap > MAX_JOINT_GAP:
			problems.append("joint gap %.3f m" % c.gap)
		if not ragdoll.settled:
			problems.append("not settled")
		if ragdoll.total_mass < 55.0 or ragdoll.total_mass > 95.0:
			problems.append("mass %.0f kg" % ragdoll.total_mass)
		# The skinned head must have followed the head body
		var skeleton: Skeleton3D = ragdoll.skeleton
		var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(&"Head")).origin
		if head.distance_to(ragdoll.bodies["head"].global_position) > 0.25:
			problems.append("mesh head %.2f m from head body" % head.distance_to(ragdoll.bodies["head"].global_position))
		var thrown: float = Vector2(ragdoll.pelvis.global_position.x - c.start.x, ragdoll.pelvis.global_position.z - c.start.z).length()
		print("%s %-12s %s mass %4.1f kg  thrown %4.1f m  pelvis y %.2f  joint gap %.3f m  %s" % [
			"ok  " if problems.is_empty() else "FAIL", c.entry.id, "bus" if c.heavy else "car",
			ragdoll.total_mass, thrown, ragdoll.pelvis.global_position.y, c.gap, "; ".join(problems)])
		if not problems.is_empty():
			failures += 1

	# Player-style recovery: blend back to standing and take the model back
	var first: Node3D = cases[0].ragdoll
	var back := [false]
	first.recovered.connect(func() -> void: back[0] = true)
	first.recover(0.5)
	for frame in 45:
		await physics_frame
	var holder := Node3D.new()
	root.add_child(holder)
	var model: Node3D = first.take_model(holder) if back[0] else null
	var skeleton: Skeleton3D = cases[0].ragdoll.skeleton if model == null else first.skeleton
	var standing := false
	if model != null:
		await process_frame
		var hips := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(&"Hips")).origin
		standing = hips.y - model.global_position.y > 0.7
	print("%s recovery: recovered %s  standing %s" % ["ok  " if standing else "FAIL", back[0], standing])
	if not standing:
		failures += 1

	print("ragdoll models test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
