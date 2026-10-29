extends SceneTree
## Clip sets (scripts/animation_sets.gd) for every pedestrian and the player:
##   godot --headless --path . --script tests/animation_sets_test.gd
## Checks: every clip the sets or the Mixamo builder name loads (Mixamo ones
## only when assets/animations/mixamo_library.res has been built on this
## machine), walks and runs loop, picks are the same every time for an ID, no
## female-only clip goes to a man or male-only clip to a woman, elders get the
## slow walk, and every character can stand, sit and lie with the hips at a
## sensible height.

const Registry = preload("res://scripts/pedestrian_registry.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const AnimationSets = preload("res://scripts/animation_sets.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")
const MixamoBuild = preload("res://scripts/mixamo_library_build.gd")
const PLAYER_JSON := "res://assets/characters/player/player.json"

var _failures := 0


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	_run.call_deferred()


func _fail(message: String) -> void:
	print("FAIL " + message)
	_failures += 1


func _run() -> void:
	var has_mixamo := Locomotion.mixamo() != null
	print("Mixamo library: %s" % ("loaded" if has_mixamo else "not built here; CC0 fallback only"))

	# Every named clip loads (Mixamo ones only when the library exists)
	var data := AnimationSets.data()
	var named := {}
	for kind: String in data.sets:
		for slot: String in data.sets[kind]:
			for clip: String in data.sets[kind][slot]:
				named[clip] = true
	for slot: String in data.fallback:
		for clip: String in data.fallback[slot]:
			named[clip] = true
	if has_mixamo:
		for clip: String in MixamoBuild.CLIPS:
			named[Locomotion.MIXAMO_PREFIX + clip] = true
	for clip: String in named:
		if clip.begins_with(Locomotion.MIXAMO_PREFIX) and not has_mixamo:
			continue
		var anim := Locomotion.clip(clip)
		if anim == null:
			_fail("clip %s doesn't load" % clip)
		elif ["walk", "jog", "sprint"].any(func(slot: String) -> bool: return _in_slot(data, slot, clip)) and anim.loop_mode != Animation.LOOP_LINEAR:
			_fail("locomotion clip %s doesn't loop" % clip)
	print("clips checked: %d" % named.size())

	# Every pedestrian and the player
	var people := []
	for entry: Dictionary in Registry.all():
		people.append(entry)
	var player: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_JSON))
	if player is Dictionary:
		var p: Dictionary = player
		people.append({"id": p.id, "gender": p.get("gender", ""), "tags": p.get("tags", []), "model_path": p.model_path, "scale": 1.0})
	else:
		_fail("player.json unreadable")

	for entry: Dictionary in people:
		var gender: String = entry.get("gender", "")
		var tags: Array = entry.get("tags", [])
		if gender != "male" and gender != "female":
			_fail("%s has no gender" % entry.id)
		if not (tags.has("young") or tags.has("adult") or tags.has("elder")):
			_fail("%s has no age tag (young/adult/elder)" % entry.id)
		var clips := AnimationSets.pick(entry.id, gender, tags)
		if clips != AnimationSets.pick(entry.id, gender, tags):
			_fail("%s gets different clips on a second pick" % entry.id)
		for slot: String in data.slots:
			var sex := AnimationSets.clip_sex(clips[slot])
			if sex != "" and sex != gender:
				_fail("%s (%s) got %s-only clip %s" % [entry.id, gender, sex, clips[slot]])
		if tags.has("elder") and clips.walk != "Walk_Slow":
			_fail("elder %s walks with %s" % [entry.id, clips.walk])
		var heights := _hip_heights(entry, clips)
		if heights.is_empty():
			_fail("%s: model has no standard skeleton" % entry.id)
			continue
		var line := "%-18s %-13s idle %s walk %s sit %s lie %s | hips stand %.2f sit %.2f lie %.2f" % [
			entry.id, clips.set, clips.idle, clips.walk, clips.sit, clips.lie if clips.lie != "" else "-",
			heights.idle, heights.sit, heights.get("lie", -1.0)]
		var problems := []
		if heights.idle < 0.7:
			problems.append("standing hips too low")
		if heights.sit > heights.idle - 0.15 or heights.sit < 0.2:
			problems.append("sitting hips at %.2f m" % heights.sit)
		if heights.has("lie") and heights.lie > 0.35:
			problems.append("lying hips at %.2f m (floating)" % heights.lie)
		if has_mixamo and clips.lie == "":
			problems.append("no lying clip")
		print(("ok   " if problems.is_empty() else "FAIL ") + line + ("" if problems.is_empty() else "  " + "; ".join(problems)))
		_failures += 0 if problems.is_empty() else 1

	print("animation sets test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _in_slot(data: Dictionary, slot: String, clip: String) -> bool:
	for kind: String in data.sets:
		if (data.sets[kind].get(slot, []) as Array).has(clip):
			return true
	return (data.fallback.get(slot, []) as Array).has(clip)


## Hips height above the feet's ground (model space, metres) when standing,
## sitting and lying with this character's clips.
func _hip_heights(entry: Dictionary, clips: Dictionary) -> Dictionary:
	var model: Node3D = (load(entry.model_path) as PackedScene).instantiate()
	model.scale = Vector3.ONE * float(entry.get("scale", 1.0))
	root.add_child(model)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var loco = Locomotion.create(model, clips, rng)
	if loco == null:
		model.queue_free()
		return {}
	var skeleton := SkeletonMap.skeleton_of(model)
	var hips := skeleton.find_bone("Hips")
	var result := {}
	for state in ["idle", "sit", "lie"]:
		if state == "lie" and clips.lie == "":
			continue
		loco.set_locomotion(0.0, state)
		for i in 45:
			loco.advance(1.0 / 30.0)
		var to_model := Locomotion._chain(skeleton, model)
		result[state] = (to_model * skeleton.get_bone_global_pose(hips).origin).y * model.scale.y
	model.queue_free()
	return result
