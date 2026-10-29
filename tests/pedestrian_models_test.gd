extends SceneTree
## Checks every pedestrian in scripts/pedestrian_registry.gd:
##   godot --headless --path . --script tests/pedestrian_models_test.gd
## Each model must load, get a procedural walker, have its head at a plausible
## height after `scale`, and have its feet on the ground. Models with the
## standard skeleton are also driven through the shared motion-capture library
## (scripts/locomotion.gd): idle, walk and run must play without errors, move
## the skeleton, and keep a foot on the ground. Also checks the population
## split over many picks.

const Registry = preload("res://scripts/pedestrian_registry.gd")
const Walk = preload("res://scripts/humanoid_walk.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	_run.call_deferred()


func _bone_height(model: Node3D, skeleton: Skeleton3D, words: Array) -> float:
	var best := -INF
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i).to_lower()
		for word: String in words:
			if bone_name.contains(word):
				var y := (model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(i))).origin.y
				best = maxf(best, y) if word == "head" else (y if best == -INF else minf(best, y))
	return best


## Lowest foot height (model space) seen over one cycle of `state` at `speed`.
## Returns [min_foot_y, moved] where `moved` is true if the skeleton pose
## actually changed while animating (so we know the clip tracks resolved).
func _locomotion_probe(holder: Node3D, model: Node3D, state: String, speed: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var loco = Locomotion.create(model, {"idle": "Idle"}, rng)
	if loco == null:
		return []
	loco.set_locomotion(speed, state)
	for i in 45:
		loco.advance(1.0 / 30.0)
	await process_frame
	var skeleton: Skeleton3D = SkeletonMap.skeleton_of(model)
	var leg := skeleton.find_bone("LeftUpperLeg")
	var lowest := INF
	var first_pose := skeleton.get_bone_pose_rotation(leg)
	var moved := false
	for s in 18:
		loco.advance(1.0 / 30.0)
		await process_frame
		if skeleton.get_bone_pose_rotation(leg).angle_to(first_pose) > 0.01:
			moved = true
		var foot := minf(
			_bone_height(holder, skeleton, ["foot", "toe", "ball_"]),
			INF)
		lowest = minf(lowest, foot)
	loco.stop()
	loco.tree.queue_free()
	return [lowest, moved]


func _run() -> void:
	var failures := 0
	var mocap_models := 0
	for entry: Dictionary in Registry.all():
		var holder := Node3D.new()
		root.add_child(holder)
		var scene: PackedScene = load(entry.model_path)
		if scene == null:
			print("FAIL %s: cannot load %s" % [entry.id, entry.model_path])
			failures += 1
			continue
		var model: Node3D = scene.instantiate()
		model.scale = Vector3.ONE * float(entry.scale)
		holder.add_child(model)
		var walker = Walk.create(model)
		await process_frame
		if walker == null:
			print("FAIL %s: no leg bones found for the procedural walk" % entry.id)
			failures += 1
			holder.queue_free()
			continue
		walker.pose(0.0, 0.0)
		await process_frame
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var head := _bone_height(holder, skeleton, ["head"])
		var feet := _bone_height(holder, skeleton, ["foot", "toe", "ball_"])
		var ok := head > 1.2 and head < 1.95 and feet > -0.05 and feet < 0.2
		# Motion-capture locomotion, when the model has the standard skeleton
		var mocap_note := ""
		if Locomotion.library() != null and skeleton.name == SkeletonMap.SKELETON_NAME and SkeletonMap.missing_bones(skeleton).is_empty():
			mocap_models += 1
			for probe: Array in [["idle", 0.0], ["walk", 1.4], ["run", 4.3]]:
				var result: Array = await _locomotion_probe(holder, model, probe[0], probe[1])
				if result.is_empty():
					ok = false
					mocap_note += " %s:none" % probe[0]
					continue
				var foot_ok: bool = result[0] > -0.08 and result[0] < 0.22
				var moving_ok: bool = probe[0] == "idle" or result[1]
				if not foot_ok or not moving_ok:
					ok = false
					mocap_note += " %s(foot %.2f%s)" % [probe[0], result[0], "" if moving_ok else " STILL"]
			if mocap_note == "":
				mocap_note = " mocap idle/walk/run OK"
		print("%s %-40s head %.2f m  feet %.2f m  %s%s" % ["ok  " if ok else "FAIL", entry.id + " " + entry.display_name, head, feet, entry.appearance_category, mocap_note])
		if not ok:
			failures += 1
		holder.queue_free()
		await process_frame

	print("motion-capture library drove %d models with the standard skeleton" % mocap_models)
	if mocap_models == 0:
		print("WARNING no model used the motion-capture library (library missing or no standard skeleton)")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var black := 0
	for i in 1000:
		if Registry.choose(rng).appearance_category == "black_african":
			black += 1
	var share := black / 1000.0
	print("population split over 1000 picks: %.1f%% Black African (target %.0f%%)" % [share * 100.0, Registry.BLACK_AFRICAN_WEIGHT * 100.0])
	if absf(share - Registry.BLACK_AFRICAN_WEIGHT) > 0.04:
		failures += 1
	print("PEDESTRIAN MODELS: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)
