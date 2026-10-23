extends SceneTree
## Checks that every pedestrian model has the standard skeleton:
##   godot --headless --path . --script tests/skeleton_test.gd
## Each model's skeleton must be the retargeted "GeneralSkeleton" with every
## bone in SkeletonMap.REQUIRED, the standard parent chain, and its left side
## on +X with the head above the feet (model faces +Z).
##
## Writing the bone maps (only needed for new models):
##   godot --headless --path . --script tests/skeleton_test.gd -- --write-imports
##   godot --headless --path . --import

const Registry = preload("res://scripts/pedestrian_registry.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")

## child -> expected parent in the standard skeleton
const PARENTS := {
	"Spine": "Hips", "Chest": "Spine", "UpperChest": "Chest", "Neck": "UpperChest", "Head": "Neck",
	"LeftShoulder": "UpperChest", "LeftUpperArm": "LeftShoulder", "LeftLowerArm": "LeftUpperArm", "LeftHand": "LeftLowerArm",
	"RightShoulder": "UpperChest", "RightUpperArm": "RightShoulder", "RightLowerArm": "RightUpperArm", "RightHand": "RightLowerArm",
	"LeftUpperLeg": "Hips", "LeftLowerLeg": "LeftUpperLeg", "LeftFoot": "LeftLowerLeg", "LeftToes": "LeftFoot",
	"RightUpperLeg": "Hips", "RightLowerLeg": "RightUpperLeg", "RightFoot": "RightLowerLeg", "RightToes": "RightFoot",
}


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	if OS.get_cmdline_user_args().has("--write-imports"):
		_write_imports.call_deferred()
	else:
		_run.call_deferred()


func _model_paths() -> Array:
	var paths := []
	for entry: Dictionary in Registry.all():
		if str(entry.model_path).begins_with("res://"):
			paths.append(entry.model_path)
	return paths


func _write_imports() -> void:
	for path: String in _model_paths():
		var model: Node = load(path).instantiate()
		var skeleton := SkeletonMap.skeleton_of(model)
		var import_path := path + ".import"
		var config := ConfigFile.new()
		config.load(import_path)
		var subresources: Dictionary = config.get_value("params", "_subresources", {})
		var nodes: Dictionary = subresources.get("nodes", {})
		var already := false
		for key: String in nodes:
			if nodes[key] is Dictionary and nodes[key].has("retarget/bone_map"):
				already = true
		if already or skeleton == null or skeleton.name == SkeletonMap.SKELETON_NAME:
			print("skip %s (already mapped)" % path)
			model.free()
			continue
		var mapping := SkeletonMap.guess_bone_map(skeleton)
		var missing := SkeletonMap.REQUIRED.filter(func(b: StringName) -> bool: return not mapping.has(String(b)))
		if not missing.is_empty():
			print("FAIL %s: can't map %s" % [path, missing])
			model.free()
			continue
		nodes["PATH:" + str(model.get_path_to(skeleton))] = {
			"retarget/bone_map": SkeletonMap.make_bone_map(mapping),
		}
		subresources["nodes"] = nodes
		config.set_value("params", "_subresources", subresources)
		config.save(import_path)
		print("wrote %s: %d bones mapped" % [import_path, mapping.size()])
		model.free()
	quit()


func _run() -> void:
	var failures := 0
	for entry: Dictionary in Registry.all():
		if not str(entry.model_path).begins_with("res://"):
			continue
		var holder := Node3D.new()
		root.add_child(holder)
		var model: Node3D = load(entry.model_path).instantiate()
		model.scale = Vector3.ONE * float(entry.scale)
		holder.add_child(model)
		var skeleton := SkeletonMap.skeleton_of(model)
		var problems := []
		if skeleton == null:
			problems.append("no skeleton")
		else:
			if skeleton.name != SkeletonMap.SKELETON_NAME:
				problems.append("skeleton not retargeted (named %s)" % skeleton.name)
			var missing := SkeletonMap.missing_bones(skeleton)
			if not missing.is_empty():
				problems.append("missing %s" % ", ".join(missing))
			else:
				for child: String in PARENTS:
					var parent := skeleton.get_bone_parent(skeleton.find_bone(child))
					var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else "-"
					if parent_name != PARENTS[child]:
						problems.append("%s parent is %s" % [child, parent_name])
				var to_model := holder.global_transform.affine_inverse() * skeleton.global_transform
				var pos := func(bone: String) -> Vector3: return to_model * skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin
				if pos.call("LeftUpperArm").x <= pos.call("RightUpperArm").x or pos.call("LeftUpperLeg").x <= pos.call("RightUpperLeg").x:
					problems.append("left side is not on +X")
				if pos.call("Head").y < pos.call("Hips").y + 0.3 or pos.call("Hips").y < pos.call("LeftFoot").y + 0.5:
					problems.append("not upright")
				if pos.call("LeftToes").z <= pos.call("LeftFoot").z:
					problems.append("toes don't point +Z")
		print("%s %-12s %s" % ["ok  " if problems.is_empty() else "FAIL", entry.id, "; ".join(problems)])
		if not problems.is_empty():
			failures += 1
		holder.free()
	print("skeleton test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
