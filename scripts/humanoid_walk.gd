extends RefCounted
## Procedural walk for imported humanoid models.
##
## Pedestrian models come from different sources with different skeletons:
## MPFB/Mixamo ("mixamorig:LeftUpLeg"), Renderpeople ("upperleg_l") and others.
## Instead of one animation per skeleton, this finds the thigh, knee,
## upper-arm and forearm bones by name, lowers the arms out of the T/A-pose,
## and swings the limbs, like ragdoll.gd does for the procedural pedestrian.
##
## The model must face +Z with its left side on +X (glTF convention).

## Name endings to look for, after lower-casing and removing numeric suffixes
## such as "_56" that glTF exporters add
const BONES := {
	"thigh_l": ["leftupleg", "upperleg_l", "thigh_l"],
	"thigh_r": ["rightupleg", "upperleg_r", "thigh_r"],
	"knee_l": ["leftleg", "lowerleg_l", "calf_l"],
	"knee_r": ["rightleg", "lowerleg_r", "calf_r"],
	"arm_l": ["leftarm", "upperarm_l"],
	"arm_r": ["rightarm", "upperarm_r"],
	"forearm_l": ["leftforearm", "lowerarm_l"],
	"forearm_r": ["rightforearm", "lowerarm_r"],
}
## Arms hang this far out from straight down, in radians
const ARM_SPREAD := 0.16
const LEG_SWING := 0.45
const ARM_SWING := 0.25
const KNEE_BEND := 0.5

var _skeleton: Skeleton3D
var _model: Node3D
var _bones := {}
var _lateral := Vector3.RIGHT
## Per bone: [rest local rotation, parent global rest rotation]
var _rest := {}
var _arm_down := {}
## Skeleton-space turn last applied to each bone this pose
var _applied := {}
var _model_rest_y := 0.0


## Returns a walker for the model under `model`, or null if its skeleton
## doesn't have recognisable legs.
static func create(model: Node3D) -> RefCounted:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var walker := new()
	if not walker._setup(model, skeletons[0]):
		return null
	return walker


func _setup(model: Node3D, skeleton: Skeleton3D) -> bool:
	_model = model
	_skeleton = skeleton
	_model_rest_y = model.position.y
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i).to_lower()
		while name.length() > 0 and (name[-1].is_valid_int() or name[-1] == "_"):
			name = name.left(-1)
		for key in BONES:
			if _bones.has(key):
				continue
			for ending: String in BONES[key]:
				if name.ends_with(ending):
					_bones[key] = i
					break
	if not (_bones.has("thigh_l") and _bones.has("thigh_r")):
		return false

	# Model-space directions expressed in skeleton space (the skeleton may sit
	# under rotated or scaled nodes, for example Sketchfab's Z-up wrappers)
	var to_skeleton := _chain(skeleton, model).basis.inverse()
	_lateral = (to_skeleton * Vector3.RIGHT).normalized()
	var down := (to_skeleton * Vector3.DOWN).normalized()

	for key in _bones:
		var bone: int = _bones[key]
		var parent := skeleton.get_bone_parent(bone)
		var parent_rot := skeleton.get_bone_global_rest(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		_rest[key] = [skeleton.get_bone_rest(bone).basis.get_rotation_quaternion(), parent_rot]

	# Rotation that takes each upper arm from its rest direction to hanging down
	for side in ["l", "r"]:
		var arm: int = _bones.get("arm_" + side, -1)
		var forearm: int = _bones.get("forearm_" + side, -1)
		if arm < 0 or forearm < 0:
			continue
		var from := skeleton.get_bone_global_rest(forearm).origin - skeleton.get_bone_global_rest(arm).origin
		var outward := _lateral * (1.0 if side == "l" else -1.0)
		var target := (down * cos(ARM_SPREAD) + outward * sin(ARM_SPREAD)).normalized()
		_arm_down["arm_" + side] = Quaternion(from.normalized(), target)
	return true


## Poses the skeleton. `phase` advances with distance walked; `amount` is 0
## standing still to 1 at full stride.
func pose(phase: float, amount: float) -> void:
	var swing := sin(phase) * amount
	# Positive angles about the lateral axis tip a hanging limb backwards (-Z)
	_turn("thigh_l", -swing * LEG_SWING)
	_turn("thigh_r", swing * LEG_SWING)
	# A knee bends while its leg swings forward under the body (cos > 0 for the
	# left leg) and straightens again for the heel strike
	_turn("knee_l", maxf(0.0, cos(phase - 0.3)) * KNEE_BEND * amount)
	_turn("knee_r", maxf(0.0, -cos(phase - 0.3)) * KNEE_BEND * amount)
	_turn("arm_l", swing * ARM_SWING)
	_turn("arm_r", -swing * ARM_SWING)
	_turn("forearm_l", -0.15 - maxf(0.0, -swing) * 0.2, "arm_l")
	_turn("forearm_r", -0.15 - maxf(0.0, swing) * 0.2, "arm_r")
	# A slight bob, lowest when the legs are furthest apart
	_model.position.y = _model_rest_y - absf(swing) * 0.025 * amount


## Rotates a bone by `angle` about the model's lateral axis, on top of its rest
## pose (and, for upper arms, the arms-down correction). Rotations are built in
## skeleton space and converted to the bone's local space through its parent's
## rest orientation, so children follow their parents naturally.
##
## A child's rotation is applied in its rest frame, i.e. before the parent's
## turn. When the parent's turn changed the limb's direction (a lowered arm),
## pass `parent_key` so the child's turn is moved into the posed frame:
## otherwise a forearm would twist around the T-pose arm instead of bending.
func _turn(key: String, angle: float, parent_key := "") -> void:
	if not _bones.has(key):
		return
	var rest: Array = _rest[key]
	var parent_rot: Quaternion = rest[1]
	var global_turn := Quaternion(_lateral, angle)
	if _arm_down.has(key):
		global_turn = global_turn * _arm_down[key]
	_applied[key] = global_turn
	if _applied.has(parent_key):
		var parent_turn: Quaternion = _applied[parent_key]
		global_turn = parent_turn.inverse() * global_turn * parent_turn
	var local: Quaternion = parent_rot.inverse() * global_turn * parent_rot * rest[0]
	_skeleton.set_bone_pose_rotation(_bones[key], local)


static func _chain(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while node != root and node != null:
		if node is Node3D:
			t = node.transform * t
		node = node.get_parent()
	return t
