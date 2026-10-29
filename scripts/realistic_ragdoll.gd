extends Node3D
## Ragdoll on a realistic character's own skeleton.
##
## 16 invisible rigid bodies (pelvis, lower spine, chest, head, upper arms,
## forearms, hands, thighs, shins, feet) are sized from the character's bone
## lengths and joined with Jolt-friendly cone-twist and hinge joints (the same
## joint types as the stick ragdoll in ragdoll.gd). A SkeletonModifier3D
## writes the bodies' rotations onto the standard bones every frame, so the
## skinned mesh itself tumbles. Only the hips bone moves in position; every
## other bone only rotates, so the skin never stretches.
##
## Start it with spawn(); the character model (an imported .glb scene with the
## standard skeleton, see skeleton_map.gd) is moved under the returned node.
## Pedestrians stay down and are removed off-screen after REMOVE_AFTER seconds.
## The player can call recover() (or set recover_delay) to blend back to a
## standing pose and take the model back when `recovered` fires.

const Ragdoll = preload("res://scripts/ragdoll.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")

signal recovered

## Pedestrians are removed this long after the fall, once off-screen
const REMOVE_AFTER := 20.0
## Mesh and physics stop beyond this distance from the camera
const CULL_DISTANCE := 120.0
const SETTLE_SPEED := 0.12
## Body damping during the fall, and once the body has nearly stopped (so the
## last slow roll dies out instead of creeping). Back to falling damping if it
## is knocked again.
const FALL_LINEAR_DAMP := 0.2
const FALL_ANGULAR_DAMP := 2.6
const REST_LINEAR_DAMP := 1.5
const REST_ANGULAR_DAMP := 9.0
const REST_DAMP_BELOW := 0.5
const REST_DAMP_ABOVE := 2.0
## Average adult used for the size proportions below
const REFERENCE_HEIGHT := 1.75

# part: [bone, end bone ("" = estimated), shape, mass share, radius at 1.75 m]
const PARTS := {
	"pelvis": [&"Hips", &"Spine", "box", 0.14, 0.0],
	"spine": [&"Spine", &"UpperChest", "box", 0.12, 0.0],
	"chest": [&"UpperChest", &"Neck", "box", 0.20, 0.0],
	"head": [&"Head", &"", "sphere", 0.08, 0.1],
	"upper_arm_l": [&"LeftUpperArm", &"LeftLowerArm", "capsule", 0.028, 0.047],
	"lower_arm_l": [&"LeftLowerArm", &"LeftHand", "capsule", 0.017, 0.036],
	"hand_l": [&"LeftHand", &"", "box", 0.008, 0.0],
	"upper_arm_r": [&"RightUpperArm", &"RightLowerArm", "capsule", 0.028, 0.047],
	"lower_arm_r": [&"RightLowerArm", &"RightHand", "capsule", 0.017, 0.036],
	"hand_r": [&"RightHand", &"", "box", 0.008, 0.0],
	"thigh_l": [&"LeftUpperLeg", &"LeftLowerLeg", "capsule", 0.10, 0.072],
	"shin_l": [&"LeftLowerLeg", &"LeftFoot", "capsule", 0.046, 0.052],
	"foot_l": [&"LeftFoot", &"LeftToes", "box", 0.015, 0.0],
	"thigh_r": [&"RightUpperLeg", &"RightLowerLeg", "capsule", 0.10, 0.072],
	"shin_r": [&"RightLowerLeg", &"RightFoot", "capsule", 0.046, 0.052],
	"foot_r": [&"RightFoot", &"RightToes", "box", 0.015, 0.0],
}

# [type, parent part, child part, swing or lower limit, twist or upper limit]
# Limits are in degrees, measured from the reference pose built in
# _reference_pose(): thighs 25° forward, arms 40° out and 20° forward from
# hanging, elbows and knees straight. Hinges bend one way only: the forearm
# towards the front, the shin towards the back.
const JOINTS := [
	["cone", "pelvis", "spine", 18.0, 10.0],
	["cone", "spine", "chest", 18.0, 10.0],
	["cone", "chest", "head", 38.0, 25.0],
	["cone", "chest", "upper_arm_l", 80.0, 35.0],
	["cone", "chest", "upper_arm_r", 80.0, 35.0],
	["elbow", "upper_arm_l", "lower_arm_l", 0.0, 140.0],
	["elbow", "upper_arm_r", "lower_arm_r", 0.0, 140.0],
	["cone", "lower_arm_l", "hand_l", 35.0, 12.0],
	["cone", "lower_arm_r", "hand_r", 35.0, 12.0],
	["cone", "pelvis", "thigh_l", 58.0, 20.0],
	["cone", "pelvis", "thigh_r", 58.0, 20.0],
	["knee", "thigh_l", "shin_l", 0.0, 135.0],
	["knee", "thigh_r", "shin_r", 0.0, 135.0],
	["cone", "shin_l", "foot_l", 22.0, 8.0],
	["cone", "shin_r", "foot_r", 22.0, 8.0],
]

## Bones written from the bodies, parents first: [bone, part, blend part]
## A blend bone takes half its rotation from a second body: the neck follows
## the head part-way, the middle chest bone sits between spine and chest.
const DRIVEN := [
	[&"Hips", "pelvis", ""],
	[&"Spine", "spine", ""],
	[&"Chest", "spine", "chest"],
	[&"UpperChest", "chest", ""],
	[&"Neck", "chest", "head"],
	[&"Head", "head", ""],
	[&"LeftUpperArm", "upper_arm_l", ""],
	[&"LeftLowerArm", "lower_arm_l", ""],
	[&"LeftHand", "hand_l", ""],
	[&"RightUpperArm", "upper_arm_r", ""],
	[&"RightLowerArm", "lower_arm_r", ""],
	[&"RightHand", "hand_r", ""],
	[&"LeftUpperLeg", "thigh_l", ""],
	[&"LeftLowerLeg", "shin_l", ""],
	[&"LeftFoot", "foot_l", ""],
	[&"RightUpperLeg", "thigh_r", ""],
	[&"RightLowerLeg", "shin_r", ""],
	[&"RightFoot", "foot_r", ""],
]

## Seconds after which the ragdoll blends back to standing; < 0 = stay down
var recover_delay := -1.0
## Remove after REMOVE_AFTER s when off-screen (pedestrians); the player clears this
var auto_remove := true

var model: Node3D
var skeleton: Skeleton3D
var bodies := {}
var pelvis: RigidBody3D
var total_mass := 0.0
var age := 0.0
var settled := false

## [bone, body a, offset a, body b, offset b] in parent-first order
var _drive := []
## Per joint: [body a, pivot in a, body b, pivot in b]
var _pivots := []
var _poser: SkeletonModifier3D
var _speed_cap := 8.0
var _still_time := 0.0
var _rest_damped := false
var _culled := false
## Recovery blend: bone -> [from local rotation, to local rotation]; hips also positions
var _blend := {}
var _blend_time := -1.0
var _blend_duration := 0.5
var _stand_pose := {}
## Set once the recovery blend has finished; stops re-posing from the bodies
var _recovered_done := false


class Poser extends SkeletonModifier3D:
	var ragdoll: Node

	# Godot renamed this virtual across 4.x: 4.3-4.5 call
	# _process_modification() (no args); later builds call
	# _process_modification_with_delta(delta). Override both so the pose is
	# written whichever one this runtime invokes; the unused one is a no-op.
	func _process_modification() -> void:
		if is_instance_valid(ragdoll):
			ragdoll.apply_pose()

	func _process_modification_with_delta(_delta: float) -> void:
		if is_instance_valid(ragdoll):
			ragdoll.apply_pose()


## Turns `model` into a ragdoll at its current pose and returns the ragdoll
## node (in group "ragdolls", added to `parent`), or null if the model has no
## standard skeleton. `impact_velocity`, `impact_point` and `vehicle_mass`
## describe the vehicle that hit the character; pass Vector3.ZERO and 0 for a
## fall without a vehicle.
static func spawn(model: Node3D, parent: Node, character_velocity: Vector3, impact_velocity: Vector3,
		impact_point: Vector3, vehicle_mass: float) -> Node3D:
	var skeleton := SkeletonMap.skeleton_of(model)
	if skeleton == null or not SkeletonMap.missing_bones(skeleton).is_empty():
		return null
	var old := parent.get_tree().get_nodes_in_group("ragdolls")
	if old.size() >= Ragdoll.max_ragdolls:
		old[0].queue_free()
	var ragdoll: Node3D = new()
	ragdoll.name = "RealisticRagdoll"
	ragdoll.add_to_group("ragdolls")
	parent.add_child(ragdoll)
	ragdoll._build(model, skeleton)
	ragdoll._launch(character_velocity, impact_velocity, impact_point, vehicle_mass)
	return ragdoll


func _build(new_model: Node3D, new_skeleton: Skeleton3D) -> void:
	model = new_model
	skeleton = new_skeleton
	var model_xform := model.global_transform
	model.get_parent().remove_child(model)
	add_child(model)
	model.global_transform = model_xform
	for mixer: AnimationMixer in model.find_children("*", "AnimationMixer", true, false):
		mixer.active = false
	for modifier: SkeletonModifier3D in skeleton.find_children("*", "SkeletonModifier3D", false, false):
		modifier.active = false

	var world := skeleton.global_transform
	var current := {}
	for i in skeleton.get_bone_count():
		current[i] = skeleton.get_bone_global_pose(i)
	var reference := _reference_pose(world)
	for entry: Array in DRIVEN:
		var bone := skeleton.find_bone(entry[0])
		_stand_pose[bone] = [skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone)]

	# Size from the reference pose, in world units (metres)
	var ref_world := func(bone_name: StringName) -> Vector3:
		return world * reference[skeleton.find_bone(bone_name)].origin
	var left: Vector3 = model_xform.basis.x.normalized()
	var up: Vector3 = model_xform.basis.y.normalized()
	var foot_y: float = minf(ref_world.call(&"LeftFoot").dot(up), ref_world.call(&"RightFoot").dot(up))
	var height: float = (ref_world.call(&"Head").dot(up) - foot_y + 0.06) / 0.885
	var s := height / REFERENCE_HEIGHT
	var hip_width: float = ref_world.call(&"LeftUpperLeg").distance_to(ref_world.call(&"RightUpperLeg"))
	var shoulder_width: float = ref_world.call(&"LeftUpperArm").distance_to(ref_world.call(&"RightUpperArm"))
	var build := clampf(hip_width / (0.19 * s), 0.85, 1.25)
	total_mass = clampf(22.0 * height * height * build, 55.0, 95.0)

	var specs := {}
	for part: String in PARTS:
		var def: Array = PARTS[part]
		var a: Vector3 = ref_world.call(def[0])
		var b: Vector3
		var size := Vector3.ZERO
		match part:
			"pelvis":
				a = (ref_world.call(&"LeftUpperLeg") + ref_world.call(&"RightUpperLeg")) * 0.5 - up * 0.04 * s
				b = ref_world.call(&"Spine")
				size = Vector3(hip_width + 0.09 * s * build, maxf(a.distance_to(b), 0.12 * s), 0.2 * s * build)
			"spine":
				b = ref_world.call(def[1])
				size = Vector3(0.27 * s * build, a.distance_to(b), 0.18 * s * build)
			"chest":
				b = ref_world.call(def[1])
				size = Vector3(maxf(shoulder_width * 0.78, 0.26 * s), a.distance_to(b), 0.2 * s * build)
			"head":
				var neck: Vector3 = ref_world.call(&"Neck")
				a = neck
				b = ref_world.call(&"Head") + (ref_world.call(&"Head") - neck).normalized() * 0.16 * s
			"hand_l", "hand_r":
				var finger: Vector3 = ref_world.call(&"LeftMiddleProximal" if part == "hand_l" else &"RightMiddleProximal") \
					if skeleton.find_bone(&"LeftMiddleProximal") >= 0 else a + (a - ref_world.call(&"LeftLowerArm" if part == "hand_l" else &"RightLowerArm")).normalized() * 0.1 * s
				b = a + (finger - a).normalized() * 0.18 * s
				size = Vector3(0.035 * s, 0.18 * s, 0.085 * s)
			"foot_l", "foot_r":
				var toes: Vector3 = ref_world.call(def[1])
				b = toes + (toes - a).normalized() * 0.06 * s
				size = Vector3(0.095 * s, a.distance_to(b), 0.07 * s)
			_:
				b = ref_world.call(def[1])
		specs[part] = {"a": a, "b": b, "size": size, "radius": float(def[4]) * s * (build if part.begins_with("thigh") else 1.0)}

	# Bodies, created in the reference pose so joint limits are measured from it
	var share_total := 0.0
	for part: String in PARTS:
		share_total += float(PARTS[part][3])
	for part: String in PARTS:
		var def: Array = PARTS[part]
		var spec: Dictionary = specs[part]
		var body := RigidBody3D.new()
		body.name = part
		# A higher floor on the light extremities (hands, feet) keeps the mass
		# ratio across the wrist and ankle joints gentle enough that Jolt's
		# solver doesn't let those joints pull apart under a hard impact.
		body.mass = maxf(total_mass * float(def[3]) / share_total, 1.3)
		body.collision_layer = Ragdoll.LAYER_RAGDOLL
		body.collision_mask = Ragdoll.MASK_RAGDOLL
		body.linear_damp = FALL_LINEAR_DAMP
		body.angular_damp = FALL_ANGULAR_DAMP
		body.physics_material_override = _material()
		var shape := CollisionShape3D.new()
		var length: float = spec.a.distance_to(spec.b)
		match def[2]:
			"box":
				var box := BoxShape3D.new()
				box.size = spec.size
				shape.shape = box
			"sphere":
				var sphere := SphereShape3D.new()
				sphere.radius = spec.radius
				shape.shape = sphere
				# Centred on the skull, not the neck
				shape.position.y = length * 0.5 - spec.radius * 0.35
			_:
				var capsule := CapsuleShape3D.new()
				capsule.radius = spec.radius
				capsule.height = maxf(length, spec.radius * 2.0 + 0.01)
				shape.shape = capsule
		body.add_child(shape)
		add_child(body)
		body.global_transform = _segment_frame(spec.a, spec.b, left)
		body.set_meta("bone", skeleton.find_bone(def[0]))
		bodies[part] = body
	pelvis = bodies["pelvis"]

	for j: Array in JOINTS:
		_add_joint(j, specs, left, up, model_xform.basis.z.normalized())

	# Bone offsets from the reference pose, then move every body to the
	# character's current animated pose so nothing jumps
	var bone_from_body := {}
	for part: String in bodies:
		var body: RigidBody3D = bodies[part]
		var bone: int = body.get_meta("bone")
		var bone_ref_world: Transform3D = world * reference[bone]
		bone_from_body[part] = body.global_transform.affine_inverse() * bone_ref_world
	for entry: Array in DRIVEN:
		var bone := skeleton.find_bone(entry[0])
		var blend_part: String = entry[2]
		var offset_a: Transform3D = bodies[entry[1]].global_transform.affine_inverse() * world * reference[bone]
		var offset_b := Transform3D.IDENTITY
		if blend_part != "":
			offset_b = bodies[blend_part].global_transform.affine_inverse() * world * reference[bone]
		_drive.append([bone, bodies[entry[1]], offset_a, bodies.get(blend_part), offset_b])
	for part: String in bodies:
		var body: RigidBody3D = bodies[part]
		var bone: int = body.get_meta("bone")
		var xform: Transform3D = (world * current[bone]) * bone_from_body[part].affine_inverse()
		xform.basis = xform.basis.orthonormalized()
		body.global_transform = xform
	_exclude_overlaps(specs)

	_poser = Poser.new()
	_poser.ragdoll = self
	skeleton.add_child(_poser)
	# The bodies move in the physics step, so pose the skeleton there too; the
	# default IDLE callback lags the physics and, in a physics-frame-only loop,
	# is starved entirely.
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS


## Rest pose with the thighs 25° forward and the arms lowered 50° from the
## T-pose (40° out from hanging) and 20° forward: the centre of each joint's
## range. Returns skeleton-space global transforms by bone index.
func _reference_pose(world: Transform3D) -> Dictionary:
	var to_skeleton := world.basis.inverse()
	var down := (to_skeleton * -model.global_basis.y).normalized()
	var forward := (to_skeleton * model.global_basis.z).normalized()
	var left := (to_skeleton * model.global_basis.x).normalized()
	var turns := {}
	for side in ["Left", "Right"]:
		var outward := left * (1.0 if side == "Left" else -1.0)
		var arm := skeleton.find_bone(StringName(side + "UpperArm"))
		var elbow := skeleton.find_bone(StringName(side + "LowerArm"))
		var from := (skeleton.get_bone_global_rest(elbow).origin - skeleton.get_bone_global_rest(arm).origin).normalized()
		var target := (down * cos(deg_to_rad(40.0)) + outward * sin(deg_to_rad(40.0))).normalized()
		target = (target * cos(deg_to_rad(20.0)) + forward * sin(deg_to_rad(20.0))).normalized()
		turns[arm] = Quaternion(from, target)
		turns[skeleton.find_bone(StringName(side + "UpperLeg"))] = Quaternion(down.cross(forward).normalized(), deg_to_rad(25.0))
	var reference := {}
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		var parent_global: Transform3D = reference[parent] if parent >= 0 else Transform3D.IDENTITY
		var global := parent_global * skeleton.get_bone_rest(i)
		if turns.has(i):
			global.basis = Basis(turns[i]) * global.basis
		reference[i] = global
	return reference


## Body frame: origin halfway along the segment, Y along it, X towards the
## character's left.
static func _segment_frame(a: Vector3, b: Vector3, left: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var x := (left - y * left.dot(y))
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _add_joint(j: Array, specs: Dictionary, left: Vector3, up: Vector3, forward: Vector3) -> void:
	var body_a: RigidBody3D = bodies[j[1]]
	var body_b: RigidBody3D = bodies[j[2]]
	var spec: Dictionary = specs[j[2]]
	var pivot: Vector3 = spec.a
	var axis: Vector3 = (spec.b - spec.a).normalized()
	var joint: Joint3D
	if j[0] == "cone":
		var cone := ConeTwistJoint3D.new()
		cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(j[3]))
		cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(j[4]))
		# The twist axis is the joint's X
		cone.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, axis)), pivot)
		joint = cone
	else:
		# Bending turns the child segment towards `bend` (front for elbows,
		# back for knees) about hinge = axis × bend. With Jolt, a turn of +θ
		# about the hinge's Z axis reads as an angle of −θ, so the limits are
		# negated.
		var bend := forward if j[0] == "elbow" else -forward
		var hinge_axis := axis.cross(bend).normalized()
		var hinge := HingeJoint3D.new()
		hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-j[4]))
		hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(j[3] + 2.0))
		hinge.transform = Transform3D(Basis(Quaternion(Vector3.BACK, hinge_axis)), pivot)
		joint = hinge
	add_child(joint)
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	_pivots.append([body_a, body_a.global_transform.affine_inverse() * pivot, body_b, body_b.global_transform.affine_inverse() * pivot])


## Non-neighbouring parts that already overlap in the starting pose (a hand
## resting on a thigh) would push each other apart with a jolt; they ignore
## each other instead.
func _exclude_overlaps(specs: Dictionary) -> void:
	var parts := bodies.keys()
	var segments := {}
	for part: String in parts:
		var body: RigidBody3D = bodies[part]
		var spec: Dictionary = specs[part]
		var half: float = spec.a.distance_to(spec.b) * 0.5
		var radius: float = spec.radius if spec.radius > 0.0 else minf(spec.size.x, spec.size.z) * 0.5
		if part == "pelvis" or part == "spine" or part == "chest":
			radius = maxf(spec.size.x, spec.size.z) * 0.5
		segments[part] = [body.global_transform * Vector3(0, -half, 0), body.global_transform * Vector3(0, half, 0), radius]
	for i in parts.size():
		for k in range(i + 1, parts.size()):
			var sa: Array = segments[parts[i]]
			var sb: Array = segments[parts[k]]
			var closest := Geometry3D.get_closest_points_between_segments(sa[0], sa[1], sb[0], sb[1])
			if closest[0].distance_to(closest[1]) < sa[2] + sb[2] + 0.01:
				bodies[parts[i]].add_collision_exception_with(bodies[parts[k]])


static var _physics_material: PhysicsMaterial


static func _material() -> PhysicsMaterial:
	if _physics_material == null:
		_physics_material = PhysicsMaterial.new()
		_physics_material.friction = 0.8
		_physics_material.bounce = 0.05
	return _physics_material


## Body velocities: the character's own velocity plus the vehicle's impact.
## A car bumper (light vehicles) hits the legs at full speed and the upper
## body much less, so the body folds onto the bonnet; a bus or truck front
## hits the whole body, so the person is knocked flat and further.
func _launch(character_velocity: Vector3, impact_velocity: Vector3, impact_point: Vector3, vehicle_mass: float) -> void:
	var up := Vector3.UP
	var ground := model.global_position.y
	var flat := Vector3(impact_velocity.x, 0.0, impact_velocity.z)
	var speed := flat.length()
	var direction := flat.normalized() if speed > 0.01 else Vector3.ZERO
	# 0 for a 1,200–1,500 kg car, 1 for a 9,000 kg+ bus or truck
	var heavy := clampf((vehicle_mass - 1500.0) / 7500.0, 0.0, 1.0) if vehicle_mass > 0.0 else 0.0
	var bumper_top := lerpf(0.55, 1.1, heavy)
	var front_top := lerpf(0.95, 2.4, heavy)
	# Momentum shared with the vehicle, capped to a believable throw
	var transfer := vehicle_mass / (vehicle_mass + total_mass) if vehicle_mass > 0.0 else 0.0
	var throw := minf(speed * transfer, lerpf(7.5, 10.0, heavy))
	# Cap each body's speed close to the throw while the impact plays out, so
	# joints aren't yanked apart by very large per-step relative velocities.
	_speed_cap = maxf(throw * 1.1, 5.0)
	var side := direction.cross(up)
	var offset := (impact_point - pelvis.global_position).dot(side) if impact_point.is_finite() else 0.0
	for part: String in bodies:
		var body: RigidBody3D = bodies[part]
		var h := body.global_position.y - ground
		var share := 1.0
		if h > bumper_top:
			# A car folds the upper body over the bonnet (low upper-body share);
			# a bus drives the whole body at nearly one speed (high, uniform
			# share), which also keeps the torso joints from shearing.
			share = lerpf(1.0, lerpf(0.3, 0.9, heavy), clampf((h - bumper_top) / maxf(front_top - bumper_top, 0.1), 0.0, 1.0))
		if h > front_top:
			share = lerpf(0.25, 0.9, heavy)
		var lift := throw * lerpf(0.16, 0.06, heavy) * (1.0 if h < bumper_top else 0.4)
		body.linear_velocity = character_velocity + direction * throw * share + up * lift
		# A hit off-centre turns the body around
		body.angular_velocity = up * clampf(offset * throw * 0.1, -2.5, 2.5)


func _physics_process(delta: float) -> void:
	age += delta
	if not is_instance_valid(pelvis):
		return
	if age < 1.5:
		for body: RigidBody3D in bodies.values():
			var v := body.linear_velocity
			if v.length() > _speed_cap:
				body.linear_velocity = v.normalized() * _speed_cap
			if body.angular_velocity.length() > 25.0:
				body.angular_velocity = body.angular_velocity.normalized() * 25.0

	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var far := camera != null and camera.global_position.distance_to(pelvis.global_position) > CULL_DISTANCE
	if far != _culled and _blend_time < 0.0:
		_culled = far
		for body: RigidBody3D in bodies.values():
			body.freeze = far
		_poser.active = not far

	# Pose the skeleton from the bodies every physics step. The Poser
	# SkeletonModifier3D is kept for correct placement in the skeleton's update,
	# but its callback is not reliably pumped for a skeleton with no active
	# AnimationMixer, so the ragdoll drives the pose itself from here (the same
	# way humanoid_walk.gd poses these skeletons while alive).
	if not _culled and not _recovered_done:
		apply_pose()

	var fastest := 0.0
	for body: RigidBody3D in bodies.values():
		if not body.sleeping:
			fastest = maxf(fastest, maxf(body.linear_velocity.length(), body.angular_velocity.length() * 0.2))
	var resting := _rest_damped
	if not _rest_damped and age > 1.0 and fastest < REST_DAMP_BELOW:
		resting = true
	elif _rest_damped and fastest > REST_DAMP_ABOVE:
		resting = false
	if resting != _rest_damped:
		_rest_damped = resting
		for body: RigidBody3D in bodies.values():
			body.linear_damp = REST_LINEAR_DAMP if resting else FALL_LINEAR_DAMP
			body.angular_damp = REST_ANGULAR_DAMP if resting else FALL_ANGULAR_DAMP
	_still_time = _still_time + delta if fastest < SETTLE_SPEED else 0.0
	settled = _still_time > 0.4 or _culled
	if settled and _still_time > 1.0 and age > 2.0:
		# Let Jolt put the island to sleep instead of creeping
		for body: RigidBody3D in bodies.values():
			body.sleeping = true

	if _blend_time >= 0.0:
		_blend_time += delta
		if _blend_time >= _blend_duration:
			_finish_recovery()
		return
	if recover_delay >= 0.0 and age >= recover_delay:
		recover()
	elif auto_remove and age > REMOVE_AFTER and (camera == null or far or not _on_screen(camera)):
		queue_free()


func _on_screen(camera: Camera3D) -> bool:
	for part in ["pelvis", "head", "foot_l", "foot_r", "hand_l", "hand_r"]:
		if camera.is_position_in_frustum(bodies[part].global_position):
			return true
	return false


## Called by the SkeletonModifier3D: writes body rotations onto the bones.
func apply_pose() -> void:
	if _blend_time >= 0.0:
		_apply_blend()
		return
	var locals := _body_locals()
	for bone: int in locals:
		skeleton.set_bone_pose_rotation(bone, locals[bone][1])
	var hips: int = _drive[0][0]
	skeleton.set_bone_pose_position(hips, locals[hips][0])


## Local pose of every driven bone from the bodies: bone -> [position, rotation].
## Only the hips get a new position; other bones keep their own.
func _body_locals() -> Dictionary:
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var globals := {}
	var locals := {}
	for entry: Array in _drive:
		var bone: int = entry[0]
		var target: Transform3D = to_skeleton * (entry[1].global_transform * entry[2])
		var rotation := target.basis.get_rotation_quaternion()
		if entry[3] != null:
			var other: Transform3D = to_skeleton * (entry[3].global_transform * entry[4])
			rotation = rotation.slerp(other.basis.get_rotation_quaternion(), 0.5)
		globals[bone] = rotation
		var parent := skeleton.get_bone_parent(bone)
		var parent_rotation := _global_rotation(parent, globals)
		var position := skeleton.get_bone_pose_position(bone)
		if entry[1] == pelvis:
			var parent_global := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
			position = parent_global.affine_inverse() * target.origin
		locals[bone] = [position, (parent_rotation.inverse() * rotation).normalized()]
	return locals


## Skeleton-space rotation of `bone`, using the driven bones' new rotations
## and the stored local poses of the bones in between (shoulders, the root).
func _global_rotation(bone: int, globals: Dictionary) -> Quaternion:
	if bone < 0:
		return Quaternion.IDENTITY
	if not globals.has(bone):
		globals[bone] = _global_rotation(skeleton.get_bone_parent(bone), globals) * skeleton.get_bone_pose_rotation(bone)
	return globals[bone]


## Blends from the lying pose back to the pose the character had when hit,
## standing where the pelvis lies, over `duration` seconds. `recovered` fires
## at the end; the caller then takes the model back with take_model().
func recover(duration := 0.5) -> void:
	if _blend_time >= 0.0:
		return
	_blend_duration = maxf(duration, 0.01)
	# Stand at the pelvis, facing where the chest faced
	var facing: Vector3 = bodies["chest"].global_basis.z
	facing.y = 0.0
	var stand := model.global_transform
	var query := PhysicsRayQueryParameters3D.create(pelvis.global_position + Vector3.UP, pelvis.global_position + Vector3.DOWN * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	stand.origin = Vector3(pelvis.global_position.x, hit.position.y if not hit.is_empty() else stand.origin.y, pelvis.global_position.z)
	if facing.length_squared() > 0.01:
		var scale := stand.basis.get_scale()
		# Models face +Z, so the model's +Z goes where the chest faced
		stand.basis = Basis.looking_at(-facing.normalized(), Vector3.UP).scaled(scale)
	for body: RigidBody3D in bodies.values():
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
	model.global_transform = stand
	# The lying pose relative to the moved model is where the blend starts
	_blend = _body_locals()
	_blend_time = 0.0


func _apply_blend() -> void:
	var t := smoothstep(0.0, 1.0, clampf(_blend_time / _blend_duration, 0.0, 1.0))
	for bone: int in _blend:
		var from: Array = _blend[bone]
		var to: Array = _stand_pose[bone]
		skeleton.set_bone_pose_rotation(bone, (from[1] as Quaternion).slerp(to[1], t))
		if bone == _drive[0][0]:
			skeleton.set_bone_pose_position(bone, (from[0] as Vector3).lerp(to[0], t))


func _finish_recovery() -> void:
	_blend_time = -1.0
	_recovered_done = true
	for bone: int in _stand_pose:
		skeleton.set_bone_pose_position(bone, _stand_pose[bone][0])
		skeleton.set_bone_pose_rotation(bone, _stand_pose[bone][1])
	recovered.emit()


## Hands the model back (for example to the player after recovery), removes
## the modifier and frees the ragdoll. Returns the model, still in its
## standing global transform.
func take_model(new_parent: Node) -> Node3D:
	var xform := model.global_transform
	if is_instance_valid(_poser):
		_poser.queue_free()
		_poser = null
	remove_child(model)
	new_parent.add_child(model)
	model.global_transform = xform
	for mixer: AnimationMixer in model.find_children("*", "AnimationMixer", true, false):
		mixer.active = true
	var taken := model
	model = null
	queue_free()
	return taken


## Largest gap between the two ends of any joint, in metres (0 = perfect).
func joint_error() -> float:
	var worst := 0.0
	for p: Array in _pivots:
		worst = maxf(worst, (p[0].global_transform * p[1]).distance_to(p[2].global_transform * p[3]))
	return worst


func _exit_tree() -> void:
	if is_instance_valid(_poser):
		_poser.ragdoll = null
