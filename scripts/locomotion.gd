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
	# Random starting point in every cycle
	tree.advance(rng.randf_range(0.0, 3.0))


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
	for point in [[_clips.idle, GAIT_IDLE], [_clips.walk, GAIT_WALK], [_clips.jog, GAIT_JOG], [_clips.sprint, GAIT_SPRINT]]:
		var node := AnimationNodeAnimation.new()
		node.animation = point[0]
		move.add_blend_point(node, point[1])
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
