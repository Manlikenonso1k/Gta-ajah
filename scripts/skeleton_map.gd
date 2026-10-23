extends RefCounted
## One standard skeleton for every character.
##
## Every character model is imported with a BoneMap that uses Godot's
## SkeletonProfileHumanoid, so after import its Skeleton3D is renamed
## "GeneralSkeleton" (a unique node: `%GeneralSkeleton`) and its bones have the
## standard names in REQUIRED below (Hips, Spine, Chest, UpperChest, Neck, Head,
## LeftUpperLeg, ...). Twist, eye-lid, breast and other extra bones keep their
## original names and are not used by game code.
##
## The bone map is written into each model's .glb.import file by
##   godot --headless --path . --script tests/skeleton_test.gd -- --write-imports
## followed by `godot --headless --path . --import`. guess_bone_map() recognises
## MPFB/Mixamo ("mixamorig_LeftUpLeg"), Renderpeople ("upperleg_l_074") and
## Unreal-style ("thigh_l") skeletons. For a model whose import can't be
## retargeted, find() still finds the standard bones by name at runtime.

## Bones every character must have (the ragdoll and the animation code use them)
const REQUIRED: Array[StringName] = [
	&"Hips", &"Spine", &"Chest", &"UpperChest", &"Neck", &"Head",
	&"LeftShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
	&"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"RightHand",
	&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"LeftToes",
	&"RightUpperLeg", &"RightLowerLeg", &"RightFoot", &"RightToes",
]
## Also mapped when the model has them
const OPTIONAL: Array[StringName] = [&"Root", &"Jaw", &"LeftEye", &"RightEye"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]
const SKELETON_NAME := "GeneralSkeleton"

## Source-name tables: normalised source name -> standard name. "{s}" is the
## side ("l"/"r" for Renderpeople and Unreal, "Left"/"Right" for Mixamo).
const _RENDERPEOPLE := {
	"root": "Root", "hip": "Hips", "pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest",
	"spine_03": "UpperChest", "neck": "Neck", "neck_01": "Neck", "head": "Head", "jaw": "Jaw",
	"eye_{s}": "{S}Eye", "shoulder_{s}": "{S}Shoulder", "clavicle_{s}": "{S}Shoulder",
	"upperarm_{s}": "{S}UpperArm", "lowerarm_{s}": "{S}LowerArm", "hand_{s}": "{S}Hand",
	"upperleg_{s}": "{S}UpperLeg", "thigh_{s}": "{S}UpperLeg",
	"lowerleg_{s}": "{S}LowerLeg", "calf_{s}": "{S}LowerLeg",
	"foot_{s}": "{S}Foot", "ball_{s}": "{S}Toes",
	"thumb_01_{s}": "{S}ThumbMetacarpal", "thumb_02_{s}": "{S}ThumbProximal", "thumb_03_{s}": "{S}ThumbDistal",
	"index_01_{s}": "{S}IndexProximal", "index_02_{s}": "{S}IndexIntermediate", "index_03_{s}": "{S}IndexDistal",
	"middle_01_{s}": "{S}MiddleProximal", "middle_02_{s}": "{S}MiddleIntermediate", "middle_03_{s}": "{S}MiddleDistal",
	"ring_01_{s}": "{S}RingProximal", "ring_02_{s}": "{S}RingIntermediate", "ring_03_{s}": "{S}RingDistal",
	"pinky_01_{s}": "{S}LittleProximal", "pinky_02_{s}": "{S}LittleIntermediate", "pinky_03_{s}": "{S}LittleDistal",
}
const _MIXAMO := {
	"root": "Root", "hips": "Hips", "spine": "Spine", "spine1": "Chest", "spine2": "UpperChest",
	"neck": "Neck", "head": "Head", "jaw": "Jaw", "{s}eye": "{S}Eye", "{s}shoulder": "{S}Shoulder",
	"{s}arm": "{S}UpperArm", "{s}forearm": "{S}LowerArm", "{s}hand": "{S}Hand",
	"{s}upleg": "{S}UpperLeg", "{s}leg": "{S}LowerLeg", "{s}foot": "{S}Foot", "{s}toebase": "{S}Toes",
	"{s}handthumb1": "{S}ThumbMetacarpal", "{s}handthumb2": "{S}ThumbProximal", "{s}handthumb3": "{S}ThumbDistal",
	"{s}handindex1": "{S}IndexProximal", "{s}handindex2": "{S}IndexIntermediate", "{s}handindex3": "{S}IndexDistal",
	"{s}handmiddle1": "{S}MiddleProximal", "{s}handmiddle2": "{S}MiddleIntermediate", "{s}handmiddle3": "{S}MiddleDistal",
	"{s}handring1": "{S}RingProximal", "{s}handring2": "{S}RingIntermediate", "{s}handring3": "{S}RingDistal",
	"{s}handpinky1": "{S}LittleProximal", "{s}handpinky2": "{S}LittleIntermediate", "{s}handpinky3": "{S}LittleDistal",
}

static var _table := {}


## Normalised source name -> standard name, for all three naming styles.
static func _lookup() -> Dictionary:
	if _table.is_empty():
		for key: String in _RENDERPEOPLE:
			for side in [["l", "Left"], ["r", "Right"]]:
				_table["rp:" + key.replace("{s}", side[0])] = String(_RENDERPEOPLE[key]).replace("{S}", side[1])
		for key: String in _MIXAMO:
			for side in [["left", "Left"], ["right", "Right"]]:
				_table["mx:" + key.replace("{s}", side[0])] = String(_MIXAMO[key]).replace("{S}", side[1])
	return _table


## Lower-cases a source bone name and drops one numeric suffix that glTF
## exporters add ("upperleg_l_074" -> "upperleg_l", "mixamorig_LeftLeg_55" ->
## "mixamorig_leftleg").
static func _normalise(bone_name: String) -> String:
	var lower := bone_name.to_lower()
	var cut := lower.rfind("_")
	if cut > 0 and lower.substr(cut + 1).is_valid_int():
		lower = lower.left(cut)
	return lower


## Standard name for one source bone name, or "" if it isn't a mapped bone.
static func standard_name(bone_name: String) -> String:
	var table := _lookup()
	var name := _normalise(bone_name)
	var mixamo := name.find("mixamorig")
	if mixamo >= 0:
		name = name.substr(mixamo + 9).trim_prefix(":").trim_prefix("_")
		return table.get("mx:" + name, "")
	if table.has("rp:" + name):
		return table["rp:" + name]
	# Renderpeople animated samples prefix every bone ("rp_nathan_..._hip_02")
	for key: String in table:
		if key.begins_with("rp:") and name.ends_with("_" + key.substr(3)):
			return table[key]
	return ""


## Standard name -> source bone name for `skeleton`.
static func guess_bone_map(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for i in skeleton.get_bone_count():
		var source := skeleton.get_bone_name(i)
		var standard := standard_name(source)
		if standard != "" and not result.has(standard):
			result[standard] = source
	return result


## Index of a standard bone, whether or not the skeleton was retargeted.
static func find(skeleton: Skeleton3D, standard: StringName) -> int:
	var index := skeleton.find_bone(standard)
	if index >= 0:
		return index
	for i in skeleton.get_bone_count():
		if standard_name(skeleton.get_bone_name(i)) == String(standard):
			return i
	return -1


## The character's skeleton under `model` (the retargeted GeneralSkeleton, or
## the first Skeleton3D found).
static func skeleton_of(model: Node) -> Skeleton3D:
	var named := model.find_child(SKELETON_NAME, true, false)
	if named is Skeleton3D:
		return named
	var all := model.find_children("*", "Skeleton3D", true, false)
	return all[0] if not all.is_empty() else null


## Standard names this skeleton is missing from REQUIRED.
static func missing_bones(skeleton: Skeleton3D) -> Array:
	var missing := []
	for bone in REQUIRED:
		if skeleton.find_bone(bone) < 0:
			missing.append(String(bone))
	return missing


## A BoneMap for import retargeting.
static func make_bone_map(mapping: Dictionary) -> BoneMap:
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for standard: String in mapping:
		bone_map.set_skeleton_bone_name(StringName(standard), StringName(mapping[standard]))
	return bone_map
