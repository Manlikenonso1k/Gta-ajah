extends RefCounted
## Motion-capture locomotion for a character on the standard skeleton.
##
## Every character model is imported with the standard humanoid skeleton
## (scripts/skeleton_map.gd), so one shared AnimationLibrary
## (assets/animations/pedestrian_library.res, built by
## scripts/animation_library_build.gd) plays on all of them. This adds an
## AnimationTree to the model that blends idle -> walk -> jog -> sprint by
## ground speed, matches playback to that speed so the feet don't slide, and
## blends in "wait at the kerb" (looking left and right) and one-shot actions
## such as getting up.
##
## Use:
##   var loco := Locomotion.create(model, {"walk": "Walk_Slow"})  # null if the
##                                    # model has no standard skeleton
##   loco.set_locomotion(speed, "walk")    # whenever it changes
##   loco.advance(delta)                   # each frame (or less often far away)
##   loco.play_action("GetUp")             # one-shot; returns its length

const SkeletonMap = preload("res://scripts/skeleton_map.gd")
const LIBRARY_PATH := "res://assets/animations/pedestrian_library.res"
const STATES := ["idle", "walk", "jog", "run", "wait_at_kerb"]
const IDLES := ["Idle", "Idle", "Idle_Talking", "Idle_FoldArms", "Idle_Phone"]
## Blend-space positions of the gaits
const GAIT_IDLE := 0.0
const GAIT_WALK := 1.0
const GAIT_JOG := 2.0
const GAIT_SPRINT := 3.0
## Playback speed limits, so extreme speeds don't look like fast-forward
const MIN_SCALE := 0.55
const MAX_SCALE := 1.7
## The mocap clips keep the upper arms close to a slim mannequin; broader MPFB
## characters would otherwise push the forearms/hands into the torso and hips.
## At setup we measure how close the idle hands come to the body centreline and
## abduct (swing outward) the upper arms by an angle that opens them to a safe
## clearance: near zero for slim builds whose hands already hang clear, more for
## broad or short-armed ones whose hands tuck into the belly. Applied each frame
## on top of whatever the clip plays, so the swing timing is untouched and the
## shared clips are not edited.
const ABDUCT_TARGET := 0.15   ## want each hand at least this far (m) from the centreline
const ABDUCT_GAIN := 1.6      ## radians added per metre of shortfall
const ABDUCT_MIN := 0.04
const ABDUCT_MAX := 0.34

static var _library: AnimationLibrary

var tree: AnimationTree
var model: Node3D
var speed := 0.0
var state := "idle"
## Natural ground speed (m/s) of each gait clip for this character's leg length
var natural := {}
var _gait := 0.0
var _kerb := 0.0
var _stride := 1.0
var _clips := {}
## Upper-arm abduction post-process: bone indices, axis in skeleton space, angle
var _skeleton: Skeleton3D
var _abduct_l := -1
var _abduct_r := -1
var _abduct_axis := Vector3.BACK
var _abduct_angle := 0.0


static func library() -> AnimationLibrary:
	if _library == null and ResourceLoader.exists(LIBRARY_PATH):
		_library = load(LIBRARY_PATH)
	return _library


## Builds the AnimationTree under `model`. `clips` can override "idle", "walk",
## "jog" and "sprint" clip names. Returns null if the model has no standard
## skeleton or the library is missing (callers fall back to humanoid_walk.gd).
static func create(model_: Node3D, clips := {}, rng: RandomNumberGenerator = null) -> RefCounted:
	var lib := library()
	var skeleton := SkeletonMap.skeleton_of(model_)
	if lib == null or skeleton == null or skeleton.name != SkeletonMap.SKELETON_NAME:
		return null
	if not SkeletonMap.missing_bones(skeleton).is_empty():
		return null
	var loco := new()
	loco._setup(model_, skeleton, clips, rng if rng != null else RandomNumberGenerator.new())
	return loco


func _setup(model_: Node3D, skeleton: Skeleton3D, clips: Dictionary, rng: RandomNumberGenerator) -> void:
	model = model_
	_clips = {"idle": IDLES[rng.randi_range(0, IDLES.size() - 1)], "walk": "Walk", "jog": "Jog", "sprint": "Sprint"}
	_clips.merge(clips, true)
	# Small differences in stride so a crowd doesn't march in step
	_stride = rng.randf_range(0.93, 1.07)
	var lib := library()
	var leg := _leg_scale(skeleton)
	for gait in ["walk", "jog", "sprint"]:
		var anim := lib.get_animation(_clips[gait])
		natural[gait] = float(anim.get_meta("ground_speed", 1.3)) * leg * _stride

	tree = AnimationTree.new()
	tree.name = "LocomotionTree"
	tree.add_animation_library("", lib)
	tree.tree_root = _build_tree()
	model.add_child(tree)
	tree.root_node = tree.get_path_to(model)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	_apply()
	_setup_abduction(skeleton)
	# Random starting point in every cycle
	tree.advance(rng.randf_range(0.0, 3.0))
	_apply_abduction()


## Measures how close the idle hands come to the body centreline and sets the
## per-frame upper-arm abduction so broad or short-armed builds keep their arms
## clear of the torso, while slim builds are barely touched.
func _setup_abduction(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_abduct_l = skeleton.find_bone("LeftUpperArm")
	_abduct_r = skeleton.find_bone("RightUpperArm")
	if _abduct_l < 0 or _abduct_r < 0:
		return
	# Clips face +Z; abducting about the model's forward axis swings the arms
	# out sideways. Expressed in skeleton space so wrapper transforms (e.g.
	# Renderpeople's Z-up) don't flip it. Left arm +, right arm - (verified).
	_abduct_axis = (_chain(skeleton, model).basis.inverse() * Vector3.BACK).normalized()
	var hips := skeleton.find_bone("Hips")
	var hand_l := skeleton.find_bone("LeftHand")
	var hand_r := skeleton.find_bone("RightHand")
	if hips < 0 or hand_l < 0 or hand_r < 0:
		_abduct_angle = ABDUCT_MIN
		return
	# Sample a second of the idle (the worst, hands-together case) and take the
	# smallest sideways gap between either hand and the hip centreline, in metres.
	# Model space from local transforms, so this also works before the model
	# is added to the scene (seated drivers and passengers are built that way)
	var to_model := _chain(skeleton, model)
	var centreline := func(bone: int) -> float:
		return (to_model * skeleton.get_bone_global_pose(bone).origin).x
	var worst := INF
	for s in 4:
		tree.advance(0.25)
		var hip_x: float = centreline.call(hips)
		worst = minf(worst, minf(absf(centreline.call(hand_l) - hip_x), absf(centreline.call(hand_r) - hip_x)))
	_abduct_angle = clampf((ABDUCT_TARGET - worst) * ABDUCT_GAIN + ABDUCT_MIN, ABDUCT_MIN, ABDUCT_MAX)


## Swings each upper arm outward by _abduct_angle, on top of the pose the tree
## just wrote. Works in skeleton space so it reads as abduction whatever the
## clip is doing; children (forearm, hand) follow.
func _apply_abduction() -> void:
	if _abduct_angle <= 0.0 or _skeleton == null:
		return
	for pair in [[_abduct_l, 1.0], [_abduct_r, -1.0]]:
		var bone: int = pair[0]
		if bone < 0:
			continue
		var parent := _skeleton.get_bone_parent(bone)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var turn := Basis(_abduct_axis, _abduct_angle * pair[1])
		var new_global := turn * _skeleton.get_bone_global_pose(bone).basis
		var local := parent_basis.inverse() * new_global
		_skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


## Leg length of this character relative to the clips' source skeleton.
func _leg_scale(skeleton: Skeleton3D) -> float:
	var hips := skeleton.find_bone("Hips")
	var foot := skeleton.find_bone("LeftFoot")
	var to_model := _chain(skeleton, model)
	var hip_y := (to_model * skeleton.get_bone_global_rest(hips)).origin
	var foot_y := (to_model * skeleton.get_bone_global_rest(foot)).origin
	var height := (hip_y.y - foot_y.y) * model.scale.y
	var source := float(library().get_meta("source_hip_height", 0.95)) - 0.08
	return clampf(height / source, 0.6, 1.4) if height > 0.1 else 1.0


func _build_tree() -> AnimationNodeBlendTree:
	var blend_tree := AnimationNodeBlendTree.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 0.0
	move.max_space = GAIT_SPRINT
	for point in [["idle", _clips.idle, GAIT_IDLE], ["walk", _clips.walk, GAIT_WALK], ["jog", _clips.jog, GAIT_JOG], ["sprint", _clips.sprint, GAIT_SPRINT]]:
		var node := AnimationNodeAnimation.new()
		node.animation = point[1]
		node.resource_name = point[0]
		# Godot 4.7 warns (and will later require) a name for each blend point
		move.add_blend_point(node, point[2], -1, point[0])
	blend_tree.add_node("move", move, Vector2(0, 0))
	blend_tree.add_node("scale", AnimationNodeTimeScale.new(), Vector2(200, 0))
	var kerb := AnimationNodeAnimation.new()
	kerb.animation = "Wait_Kerb"
	blend_tree.add_node("kerb_clip", kerb, Vector2(200, 150))
	blend_tree.add_node("kerb", AnimationNodeBlend2.new(), Vector2(400, 0))
	var action := AnimationNodeAnimation.new()
	action.animation = "GetUp"
	blend_tree.add_node("action_clip", action, Vector2(400, 150))
	var one_shot := AnimationNodeOneShot.new()
	one_shot.fadein_time = 0.15
	one_shot.fadeout_time = 0.35
	blend_tree.add_node("action", one_shot, Vector2(600, 0))
	blend_tree.connect_node("scale", 0, "move")
	blend_tree.connect_node("kerb", 0, "scale")
	blend_tree.connect_node("kerb", 1, "kerb_clip")
	blend_tree.connect_node("action", 0, "kerb")
	blend_tree.connect_node("action", 1, "action_clip")
	blend_tree.connect_node("output", 0, "action")
	return blend_tree


## Movement code calls this. `speed` is the ground speed in m/s; `state` is
## one of STATES. Unknown states count as "walk" when moving, else "idle".
func set_locomotion(speed_: float, state_: String) -> void:
	speed = maxf(0.0, speed_)
	state = state_ if STATES.has(state_) else ("walk" if speed > 0.2 else "idle")


## Advances the animation by `delta` seconds (the caller decides how often).
func advance(delta: float) -> void:
	if tree == null:
		return
	var target := _target_gait()
	# Settle quickly but not instantly into the new gait
	_gait = move_toward(_gait, target, delta * 2.5)
	_kerb = move_toward(_kerb, 1.0 if state == "wait_at_kerb" and speed < 0.3 else 0.0, delta * 2.0)
	_apply()
	tree.advance(delta)
	_apply_abduction()


func _target_gait() -> float:
	if speed < 0.1:
		return GAIT_IDLE
	var walk: float = natural.walk
	var jog: float = natural.jog
	var sprint: float = natural.sprint
	if state == "walk" or (state != "jog" and state != "run" and speed < walk * 1.6):
		return clampf(speed / (walk * 0.5), GAIT_IDLE, GAIT_WALK) if speed < walk * 0.5 else GAIT_WALK
	if speed <= jog:
		return GAIT_JOG
	return clampf(GAIT_JOG + (speed - jog) / maxf(sprint - jog, 0.1), GAIT_JOG, GAIT_SPRINT)


## Playback speed so the planted foot moves at the ground speed.
func _time_scale() -> float:
	if speed < 0.1:
		return 1.0
	var g := _gait
	var nat: float
	if g <= GAIT_WALK:
		# Blending in from standing: slow the step down rather than slide
		nat = natural.walk
		var scale := clampf(speed / nat, MIN_SCALE, MAX_SCALE)
		return lerpf(1.0, scale, g)
	elif g <= GAIT_JOG:
		nat = lerpf(natural.walk, natural.jog, g - GAIT_WALK)
	else:
		nat = lerpf(natural.jog, natural.sprint, g - GAIT_JOG)
	return clampf(speed / nat, MIN_SCALE, MAX_SCALE)


func _apply() -> void:
	tree.set("parameters/move/blend_position", _gait)
	tree.set("parameters/scale/scale", _time_scale())
	tree.set("parameters/kerb/blend_amount", _kerb)


## Plays a one-shot clip from the library over the locomotion (for example
## "GetUp" after a ragdoll). Returns its length in seconds, or 0 if missing.
func play_action(clip: String) -> float:
	if tree == null or not library().has_animation(clip):
		return 0.0
	var node := (tree.tree_root as AnimationNodeBlendTree).get_node("action_clip") as AnimationNodeAnimation
	node.animation = clip
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return library().get_animation(clip).length


func is_action_playing() -> bool:
	return tree != null and bool(tree.get("parameters/action/active"))


## Stops animating (for example when a ragdoll takes over the skeleton).
func stop() -> void:
	if tree != null:
		tree.active = false


static func _chain(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while node != root and node != null:
		if node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	return t
