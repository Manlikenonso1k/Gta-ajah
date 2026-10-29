extends RefCounted
## Picks the clips a character uses, from assets/animations/animation_sets.json.
##
##   var clips := AnimationSets.pick("PED_BA_F03", "female", ["market"])
##   # {"set": "female", "idle": "Idle", "walk": "mx/Walk_F", ..., "lie": "mx/Lie_F"}
##
## The kind is <gender>, or elder_<gender> with an "elder" tag. The same ID
## always gets the same clips. Clips not in the loaded libraries are skipped
## (for example the Mixamo ones when assets/animations/mixamo_library.res
## isn't there), falling back to the CC0 clips.

const Locomotion = preload("res://scripts/locomotion.gd")
const SETS_PATH := "res://assets/animations/animation_sets.json"

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETS_PATH))
		_data = parsed if parsed is Dictionary else {"slots": [], "sets": {}, "fallback": {}, "clip_sex": {}}
	return _data


static func kind_of(gender: String, tags: Array) -> String:
	var sex := "female" if gender == "female" else "male"
	return ("elder_" + sex) if tags.has("elder") else sex


static func pick(id: String, gender: String, tags: Array) -> Dictionary:
	var sets := data()
	var kind := kind_of(gender, tags)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var chosen := {"set": kind}
	for slot: String in sets.slots:
		var options: Array = (sets.sets.get(kind, {}) as Dictionary).get(slot, []).filter(Locomotion.has_clip)
		if options.is_empty():
			options = (sets.fallback.get(slot, []) as Array).filter(Locomotion.has_clip)
		chosen[slot] = options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else ""
	return chosen


## "female", "male", or "" for clips either sex may use.
static func clip_sex(clip: String) -> String:
	return data().clip_sex.get(clip, "")
