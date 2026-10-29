extends SceneTree
## Builds the Mixamo AnimationLibrary from the owner's clips in
## assets/animations/mixamo/. Run all steps with tools/build_mixamo_library.sh.
##
##   godot --headless --path . --script scripts/mixamo_library_build.gd -- --write-imports
##       gives every .fbx.import the characters' standard-skeleton BoneMap and
##       T-pose rest fixer (copied from PED_BA_M01.glb.import, whose bones have
##       the same mixamorig_ names); reimport afterwards
##   godot --headless --path . --script scripts/mixamo_library_build.gd
##       writes res://assets/animations/mixamo_library.res
##
## Mixamo's terms don't allow the clips in a public repo, so the source folder
## and the library are git-ignored. Without them the game uses the CC0
## Quaternius library (scripts/animation_sets.gd falls back automatically).
##
## Steps per clip: keep only the standard bones' rotations and the Hips
## position (as animation_library_build.gd does), strip the forward travel
## from walks and runs so the game moves the character, give single-frame
## poses a Hips height that puts the lowest bone on the ground, and set
## looping. A walk's or run's ground speed is the travel the mocap recorded
## divided by its cycle time (measuring planted feet fails for runs, where
## both feet leave the ground).

const SkeletonMap = preload("res://scripts/skeleton_map.gd")
const SOURCE_DIR := "res://assets/animations/mixamo/"
const OUTPUT := "res://assets/animations/mixamo_library.res"
const TEMPLATE := "res://assets/characters/pedestrians/black_african/PED_BA_M01.glb.import"
const FPS := 30.0
## Lowest bone of a lying or sitting pose sits this far above the ground
## (bones run through the middle of the body)
const POSE_CLEARANCE := 0.09

## Posture fixes baked into a clip: radians about each bone's sideways axis,
## positive leans the spine forward and tips the head down (as in
## animation_library_build.gd's elderly walk). Female Walk leans back and looks
## up at the sky without this.
const POSTURE := {
	"Walk_F": {"Spine": 0.06, "Chest": 0.06, "UpperChest": 0.04, "Neck": 0.1, "Head": 0.14},
}

## name: [file in SOURCE_DIR, kind]. Kinds: "move" (looping walk/run, travel
## stripped), "loop", "once", "pose" (one held frame). See docs/PLAN_street_life.md.
const CLIPS := {
	"Walk": ["Standard Walk.fbx", "move"],
	"Walk_F": ["Female Walk.fbx", "move"],
	"Walk_M": ["Male Locomotion Pack/walking.fbx", "move"],
	"Jog": ["Jogging.fbx", "move"],
	"Run": ["Running.fbx", "move"],
	"Run_M": ["Male Locomotion Pack/standard run.fbx", "move"],
	"Idle_Stand": ["Male Locomotion Pack/idle.fbx", "loop"],
	"Idle_Phone": ["Talking On Phone.fbx", "loop"],
	"Idle_Drunk": ["Drunk Idle Variation.fbx", "loop"],
	"Sit": ["Sitting.fbx", "loop"],
	"Sit_Talk": ["Sitting Talking.fbx", "loop"],
	"Sit_Laugh": ["Sitting Laughing.fbx", "loop"],
	"Sit_Clap": ["Sitting Clap.fbx", "loop"],
	"Sit_Angry": ["Sitting Angry.fbx", "loop"],
	"Sit_F": ["Female Sitting Pose.fbx", "pose"],
	"Lie_M": ["Male Laying Pose.fbx", "pose"],
	"Lie_F": ["Female Laying Pose.fbx", "pose"],
	"Slump": ["drug abuse Pose.fbx", "pose"],
	"Angry": ["Angry.fbx", "loop"],
	"Yell": ["Yelling While Standing.fbx", "once"],
	"Block": ["Block.fbx", "once"],
	"Kneel_Point": ["Kneeling Pointing.fbx", "loop"],
	"Pray": ["Praying.fbx", "once"],
	"Flinch": ["Dodging Right.fbx", "once"],
	"Square_Up": ["Standing Idle To Fight Idle.fbx", "once"],
	"Remove_Driver": ["Removing Driver.fbx", "once"],
	"Stand_Up": ["Standing Up.fbx", "once"],
	"Jump": ["Jump.fbx", "once"],
	"Fall": ["Falling.fbx", "loop"],
	"Land_Hard": ["Hard Landing.fbx", "once"],
}


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	if OS.get_cmdline_user_args().has("--write-imports"):
		_write_imports.call_deferred()
	else:
		_build.call_deferred()


## Puts the standard-skeleton BoneMap into each clip's .fbx.import.
func _write_imports() -> void:
	var template := FileAccess.get_file_as_string(TEMPLATE)
	var start := template.find("\"retarget/bone_map\"")
	var end := template.find("\n", template.find("fix_silhouette/threshold"))
	if start < 0 or end < 0:
		push_error("no bone map block in %s" % TEMPLATE)
		quit(1)
		return
	var block := template.substr(start, end - start)
	var written := 0
	for clip: String in CLIPS:
		var source: String = SOURCE_DIR + CLIPS[clip][0]
		var import_path := source + ".import"
		var text := FileAccess.get_file_as_string(import_path)
		if text.is_empty():
			push_error("%s is not imported yet; run godot --import first" % source)
			continue
		if text.contains("retarget/bone_map"):
			continue
		var scene := load(source) as PackedScene
		var root := scene.instantiate() if scene != null else null
		var skeleton := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D if root != null else null
		if skeleton == null:
			push_error("no skeleton in %s" % source)
			if root != null:
				root.free()
			continue
		var node_path := String(root.get_path_to(skeleton))
		root.free()
		var subresources := "_subresources={\n\"nodes\": {\n\"PATH:%s\": {\n%s\n}\n}\n}" % [node_path, block]
		text = text.replace("_subresources={}", subresources)
		var file := FileAccess.open(import_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		written += 1
	print("bone maps written to %d .fbx.import files; now run godot --import" % written)
	quit()


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

	var library := AnimationLibrary.new()
	var failed := 0
	for clip: String in CLIPS:
		var spec: Array = CLIPS[clip]
		var source: String = SOURCE_DIR + spec[0]
		var scene := load(source) as PackedScene
		if scene == null:
			push_error("missing clip file %s" % source)
			failed += 1
			continue
		var model: Node3D = scene.instantiate()
		root.add_child(model)
		var skeleton := SkeletonMap.skeleton_of(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if skeleton == null or skeleton.name != SkeletonMap.SKELETON_NAME or player == null:
			push_error("%s has no standard skeleton; run the --write-imports step and reimport" % source)
			model.queue_free()
			failed += 1
			continue
		var source_name := ""
		for name in player.get_animation_list():
			if name != "RESET":
				source_name = name
		var anim := _clean(player.get_animation(source_name), allowed)
		match spec[1]:
			"move":
				# Travel is stored in hip-height units; motion_scale gives metres
				var travel := _strip_travel(anim) * skeleton.motion_scale
				anim.set_meta("ground_speed", travel / anim.length)
				anim.loop_mode = Animation.LOOP_LINEAR
			"loop":
				anim.loop_mode = Animation.LOOP_LINEAR
			"once":
				anim.loop_mode = Animation.LOOP_NONE
			"pose":
				_ground_pose(anim, skeleton)
				anim.loop_mode = Animation.LOOP_LINEAR
		if POSTURE.has(clip):
			_lean(anim, POSTURE[clip])
		anim.set_meta("kind", spec[1])
		library.add_animation(clip, anim)
		if spec[1] == "move":
			print("%-10s cycle %.2fs  ground speed %.2f m/s" % [clip, anim.length, anim.get_meta("ground_speed")])
		if not library.has_meta("source_hip_height"):
			var hips := skeleton.find_bone("Hips")
			library.set_meta("source_hip_height", (skeleton.global_transform * skeleton.get_bone_global_rest(hips)).origin.y)
		model.queue_free()
	if failed > 0:
		quit(1)
		return

	var error := ResourceSaver.save(library, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (%d clips): %s" % [OUTPUT, library.get_animation_list().size(), error_string(error)])
	quit(0 if error == OK else 1)


## Copy of `source` with only rotation tracks for shared bones and the Hips
## position, all addressed as "%GeneralSkeleton:<bone>" (as in
## animation_library_build.gd).
func _clean(source: Animation, allowed: Dictionary) -> Animation:
	var anim := source.duplicate(true) as Animation
	for i in range(anim.get_track_count() - 1, -1, -1):
		var bone := String(anim.track_get_path(i).get_concatenated_subnames())
		var type := anim.track_get_type(i)
		if allowed.has(bone) and (type == Animation.TYPE_ROTATION_3D or (type == Animation.TYPE_POSITION_3D and bone == "Hips")):
			anim.track_set_path(i, NodePath("%" + SkeletonMap.SKELETON_NAME + ":" + bone))
		else:
			anim.remove_track(i)
	return anim


func _hips_position(anim: Animation) -> int:
	return anim.find_track(NodePath("%" + SkeletonMap.SKELETON_NAME + ":Hips"), Animation.TYPE_POSITION_3D)


## Mixamo walks and runs move the hips forward through the cycle. Remove that
## steady travel (keeping the bob and sway) so the clip plays on the spot.
## Returns the distance removed, in track units.
func _strip_travel(anim: Animation) -> float:
	var track := _hips_position(anim)
	var count := anim.track_get_key_count(track) if track >= 0 else 0
	if count < 2:
		return 0.0
	var first: Vector3 = anim.track_get_key_value(track, 0)
	var drift: Vector3 = anim.track_get_key_value(track, count - 1) - first
	var span := anim.track_get_key_time(track, count - 1) - anim.track_get_key_time(track, 0)
	for k in count:
		var u := (anim.track_get_key_time(track, k) - anim.track_get_key_time(track, 0)) / maxf(span, 0.001)
		var p: Vector3 = anim.track_get_key_value(track, k)
		anim.track_set_key_value(track, k, Vector3(p.x - first.x - drift.x * u, p.y, p.z - first.z - drift.z * u))
	return Vector2(drift.x, drift.z).length()


## A single-frame pose has no Hips height, so it would float at standing
## height. Add one that puts the lowest bone just above the ground. The bone
## positions are worked out from the pose's rotations and the skeleton's rest
## (an AnimationPlayer doesn't update the skeleton until a later frame).
func _ground_pose(anim: Animation, skeleton: Skeleton3D) -> void:
	var globals := {}
	var lowest := INF
	for bone in skeleton.get_bone_count():
		var global := _posed_global(anim, skeleton, bone, globals)
		lowest = minf(lowest, global.origin.y)
	var hips := skeleton.find_bone("Hips")
	var rest := skeleton.get_bone_global_rest(hips).origin
	var height := rest.y - lowest + POSE_CLEARANCE
	var scale := skeleton.motion_scale if skeleton.motion_scale > 0.0 else 1.0
	var track := _hips_position(anim)
	if track < 0:
		track = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(track, NodePath("%" + SkeletonMap.SKELETON_NAME + ":Hips"))
	while anim.track_get_key_count(track) > 0:
		anim.track_remove_key(track, 0)
	anim.position_track_insert_key(track, 0.0, Vector3(rest.x, height, rest.z) / scale)
	anim.length = maxf(anim.length, 1.0)


## Skeleton-space transform of `bone` with the pose's first-frame rotations.
func _posed_global(anim: Animation, skeleton: Skeleton3D, bone: int, cache: Dictionary) -> Transform3D:
	if cache.has(bone):
		return cache[bone]
	var local := skeleton.get_bone_rest(bone)
	var path := NodePath("%" + SkeletonMap.SKELETON_NAME + ":" + skeleton.get_bone_name(bone))
	var track := anim.find_track(path, Animation.TYPE_ROTATION_3D)
	if track >= 0:
		local.basis = Basis(anim.rotation_track_interpolate(track, 0.0))
	var parent := skeleton.get_bone_parent(bone)
	var global := (_posed_global(anim, skeleton, parent, cache) * local) if parent >= 0 else local
	cache[bone] = global
	return global


## Turns each listed bone by a fixed angle about its sideways axis, on every key.
func _lean(anim: Animation, bends: Dictionary) -> void:
	for bone: String in bends:
		var track := anim.find_track(NodePath("%" + SkeletonMap.SKELETON_NAME + ":" + bone), Animation.TYPE_ROTATION_3D)
		if track < 0:
			continue
		var turn := Quaternion(Vector3.RIGHT, float(bends[bone]))
		for k in anim.track_get_key_count(track):
			anim.track_set_key_value(track, k, (anim.track_get_key_value(track, k) as Quaternion) * turn)
