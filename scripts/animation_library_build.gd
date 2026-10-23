extends SceneTree
## Builds the one shared pedestrian AnimationLibrary from the downloaded clips:
##   godot --headless --path . --script scripts/animation_library_build.gd
## Output: res://assets/animations/pedestrian_library.res
##
## The source clips (Quaternius Universal Animation Library 1 and 2, CC0, see
## assets/animations/CREDITS.md) are imported with the same SkeletonProfileHumanoid
## BoneMap as the characters (written into their .glb.import files), so their
## tracks already target the standard bones ("%GeneralSkeleton:LeftUpperLeg").
## This script keeps only the clips the game uses, renames them, drops tracks
## for bones the characters don't share, derives a few clips (waiting at the
## kerb, an elderly walk), and measures each locomotion clip's ground speed so
## playback can be matched to how fast a character actually moves.

const SkeletonMap = preload("res://scripts/skeleton_map.gd")
const OUTPUT := "res://assets/animations/pedestrian_library.res"
const SOURCES := {
	"ual1": "res://assets/animations/quaternius_ual1/UAL1_Standard.glb",
	"ual2": "res://assets/animations/quaternius_ual2/UAL2_Standard.glb",
}
## new name: [source, source clip, loops]
const CLIPS := {
	"Idle": ["ual1", "Idle", true],
	"Idle_Talking": ["ual1", "Idle_Talking", true],
	"Idle_FoldArms": ["ual2", "Idle_FoldArms", true],
	"Idle_Phone": ["ual2", "Idle_TalkingPhone", true],
	"Walk": ["ual1", "Walk", true],
	"Walk_Formal": ["ual1", "Walk_Formal", true],
	"Jog": ["ual1", "Jog_Fwd", true],
	"Sprint": ["ual1", "Sprint", true],
	"Walk_Carry": ["ual2", "Walk_Carry", true],
	"Driving": ["ual1", "Driving", true],
	"Sit_Enter": ["ual1", "Sitting_Enter", false],
	"Sit_Idle": ["ual1", "Sitting_Idle", true],
	"Sit_Exit": ["ual1", "Sitting_Exit", false],
	"GetUp": ["ual2", "LayToIdle", false],
	"Jump_Start": ["ual1", "Jump_Start", false],
	"Fall": ["ual1", "Jump", true],
	"Jump_Land": ["ual1", "Jump_Land", false],
	"Hit_Knockback": ["ual2", "Hit_Knockback", false],
	"Hit_Chest": ["ual1", "Hit_Chest", false],
	"Death": ["ual1", "Death01", false],
}
const LOCOMOTION := ["Walk", "Walk_Formal", "Walk_Slow", "Jog", "Sprint", "Walk_Carry"]
const FPS := 30.0


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	_build.call_deferred()


func _build() -> void:
	var allowed := {}
	for bone in SkeletonMap.REQUIRED:
		allowed[String(bone)] = true
	for side in ["Left", "Right"]:
		for part in ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]:
			allowed[side + part] = true
		for finger in ["Index", "Middle", "Ring", "Little"]:
			for part in ["Proximal", "Intermediate", "Distal"]:
				allowed[side + finger + part] = true

	var players := {}
	var models := {}
	for key: String in SOURCES:
		var model: Node3D = (load(SOURCES[key]) as PackedScene).instantiate()
		root.add_child(model)
		models[key] = model
		players[key] = model.find_child("AnimationPlayer", true, false)

	var library := AnimationLibrary.new()
	for clip_name: String in CLIPS:
		var spec: Array = CLIPS[clip_name]
		var player: AnimationPlayer = players[spec[0]]
		if not player.has_animation(spec[1]):
			push_error("missing source clip %s/%s" % spec.slice(0, 2))
			quit(1)
			return
		var anim := _clean(player.get_animation(spec[1]), allowed)
		anim.loop_mode = Animation.LOOP_LINEAR if spec[2] else Animation.LOOP_NONE
		library.add_animation(clip_name, anim)

	library.add_animation("Wait_Kerb", _kerb(library.get_animation("Idle")))
	library.add_animation("Walk_Slow", _elderly(library.get_animation("Walk")))

	# Ground speed of each locomotion clip, measured on the source skeleton
	var model: Node3D = models["ual1"]
	var skeleton := SkeletonMap.skeleton_of(model)
	var hips := skeleton.find_bone("Hips")
	var hip_height := (skeleton.global_transform * skeleton.get_bone_global_rest(hips)).origin.y
	library.set_meta("source_hip_height", hip_height)
	var mixer := AnimationPlayer.new()
	model.add_child(mixer)
	mixer.root_node = mixer.get_path_to(model)
	mixer.add_animation_library("", library)
	for clip_name: String in LOCOMOTION:
		var speed := _ground_speed(mixer, skeleton, clip_name)
		library.get_animation(clip_name).set_meta("ground_speed", speed)
		print("%-12s cycle %.2fs  ground speed %.2f m/s" % [clip_name, library.get_animation(clip_name).length, speed])
	mixer.remove_animation_library("")
	print("source hip height %.3f m, tracks e.g. %s" % [hip_height, library.get_animation("Walk").track_get_path(0)])

	var error := ResourceSaver.save(library, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (%d clips): %s" % [OUTPUT, library.get_animation_list().size(), error_string(error)])
	quit(0 if error == OK else 1)


## Copy of `source` with only rotation tracks for shared bones and the Hips
## position, all addressed as "%GeneralSkeleton:<bone>".
func _clean(source: Animation, allowed: Dictionary) -> Animation:
	var anim := source.duplicate(true) as Animation
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		var bone := String(path.get_concatenated_subnames())
		var type := anim.track_get_type(i)
		var keep := allowed.has(bone) and (type == Animation.TYPE_ROTATION_3D or (type == Animation.TYPE_POSITION_3D and bone == "Hips"))
		if not keep:
			anim.remove_track(i)
		else:
			anim.track_set_path(i, NodePath("%" + SkeletonMap.SKELETON_NAME + ":" + bone))
	return anim


func _track(anim: Animation, bone: String, type := Animation.TYPE_ROTATION_3D) -> int:
	return anim.find_track(NodePath("%" + SkeletonMap.SKELETON_NAME + ":" + bone), type)


## Re-samples rotation track `bone` of `anim` over `length` (wrapping the
## source), multiplying each key on the right by offset(t) (a local rotation).
func _resample(anim: Animation, source: Animation, bone: String, length: float, offset: Callable) -> void:
	var track := _track(anim, bone)
	var src := _track(source, bone)
	if track < 0 or src < 0:
		return
	while anim.track_get_key_count(track) > 0:
		anim.track_remove_key(track, 0)
	var count := int(length * FPS)
	for k in count + 1:
		var t := k / FPS
		var base := source.rotation_track_interpolate(src, fmod(t, source.length))
		anim.rotation_track_insert_key(track, t, base * (offset.call(t) as Quaternion))


## Waiting at the kerb: the idle with the head turning to look left, then
## right, then back. 7.5 s = three idle cycles.
func _kerb(idle: Animation) -> Animation:
	var anim := idle.duplicate(true) as Animation
	var length := idle.length * 3.0
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	# Yaw (radians) over time: centre, look left, hold, look right, hold, centre
	var keys := [[0.0, 0.0], [0.8, 0.0], [1.6, 1.0], [2.8, 1.0], [4.0, -1.0], [5.2, -1.0], [6.2, 0.0], [length, 0.0]]
	var yaw := func(t: float) -> float:
		for i in keys.size() - 1:
			var a: Array = keys[i]
			var b: Array = keys[i + 1]
			if t <= b[0]:
				var u := smoothstep(0.0, 1.0, (t - a[0]) / maxf(b[0] - a[0], 0.001))
				return lerpf(a[1], b[1], u)
		return 0.0
	# Every other track is re-sampled too so the idle keeps looping over 7.5 s
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		var bone := String(path.get_concatenated_subnames())
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var share := {"Neck": 0.45, "Head": 0.55, "UpperChest": 0.15}.get(bone, 0.0) as float
			_resample(anim, idle, bone, length, func(t: float) -> Quaternion:
				return Quaternion(Vector3.UP, 0.9 * share * yaw.call(t)))
		elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var src := idle.find_track(path, Animation.TYPE_POSITION_3D)
			while anim.track_get_key_count(i) > 0:
				anim.track_remove_key(i, 0)
			for k in int(length * FPS) + 1:
				anim.position_track_insert_key(i, k / FPS, idle.position_track_interpolate(src, fmod(k / FPS, idle.length)))
	return anim


## An older person's walk: the normal walk with the upper body leaning forward
## a little and the head lifted to look ahead. Played slower by locomotion.gd.
func _elderly(walk: Animation) -> Animation:
	var anim := walk.duplicate(true) as Animation
	var bends := {"Spine": 0.08, "Chest": 0.06, "UpperChest": 0.04, "Neck": -0.06, "Head": -0.08}
	for bone: String in bends:
		var angle: float = bends[bone]
		_resample(anim, walk, bone, walk.length, func(_t: float) -> Quaternion:
			return Quaternion(Vector3.RIGHT, angle))
	return anim


## Ground speed of a walk/run clip: how fast the planted foot moves backwards
## relative to the hips while it carries the weight.
func _ground_speed(mixer: AnimationPlayer, skeleton: Skeleton3D, clip: String) -> float:
	var anim := mixer.get_animation(clip)
	mixer.play(clip)
	var samples := 60
	var feet := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	var heights := []
	var forward := []
	for s in samples:
		mixer.seek(anim.length * s / samples, true)
		var row := []
		for foot: int in feet:
			var p := skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin
			row.append(p)
		heights.append(row)
	mixer.stop()
	# For each frame, the lower foot is the planted one; sum its backward motion
	var travelled := 0.0
	var planted_time := 0.0
	var dt := anim.length / samples
	for s in samples:
		var a: Array = heights[s]
		var b: Array = heights[(s + 1) % samples]
		var low := 0 if a[0].y < a[1].y else 1
		# Characters face +Z, so a planted foot slides towards -Z
		travelled += (a[low] as Vector3).z - (b[low] as Vector3).z
		planted_time += dt
	return travelled / planted_time
