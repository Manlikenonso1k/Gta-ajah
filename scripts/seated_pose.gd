extends RefCounted
## Poses one character sitting in a vehicle cabin.
##
## The body plays the shared seated clip from the animation library through
## the character's scripts/locomotion.gd tree: the tree's idle clip is swapped
## for Driving (driver) or Sit_Idle (passenger) while seated, so its one-shot
## slot stays free for Sit_Enter / Sit_Exit and every change cross-fades
## between seated poses. On top of that pose this script writes:
##   - the hips onto the measured seat (vehicles.json "cabin"),
##   - both feet onto the cabin floor (two-bone leg IK),
##   - the back at a natural recline for the vehicle (about 20 degrees in a
##     car, nearly upright behind a bus's flat wheel) and the head level,
##     looking along the road: the shared clips lean much further back on these
##     characters, so the recline and head pitch are measured and corrected;
##   - for a driver, both hands on the steering-wheel rim around 10 and 2
##     o'clock (two-bone arm IK plus a hand turn), following the rim as it
##     turns, and a slight head turn into corners.
##
## The IK is an analytic two-bone solve done here in script, after the
## AnimationTree has written the clip, by setting bone pose rotations (the same
## way locomotion.gd's arm abduction and realistic_ragdoll.gd pose these
## skeletons). Godot 4.7's TwoBoneIK3D modifier was checked and does work with
## the manually advanced mixer (its result shows up in the skeleton's
## skeleton_updated pass), but a modifier's result is not visible to
## get_bone_global_pose() afterwards and it only places the wrist. Solving in
## script also turns the hand so the palm (not the wrist) sits on the rim, lets
## the seat fitting and tests/steering_hands_test.gd measure exactly the pose
## that is drawn, and lets the distance LOD freeze the pose by not re-solving.
##
## Coordinates: `vehicle` is the frame the cabin data is in (car-local metres,
## +Z forward, +X the driver's side, y = 0 at the tyre contact). The model is
## parented under `seat_node`, a child of the vehicle, facing +Z.

const Locomotion = preload("res://scripts/locomotion.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")

## Hands follow the rim this far either side of 10 and 2; beyond it (or where
## the arm can't reach further round) the rim slides through the grip (shuffle
## steering), so the hands stay on the rim at any lock, including the 450
## degree bus wheel.
const HAND_FOLLOW := deg_to_rad(90.0)
## A grip slides round the rim rather than ask the arm for more than this
## fraction of its length
const REACH_LIMIT := 0.985
## 10 and 2 o'clock: 60 degrees either side of the top of the rim
const GRIP_ANGLE := deg_to_rad(60.0)
## Where along the hand (wrist = 0, middle knuckle = 1) the rim sits
const PALM := 0.62
const HEAD_TURN := deg_to_rad(16.0)
## Arms reach at most this fraction of their length when the seat is fitted:
## drivers keep a clear bend at the elbow (a straight arm looks stiff)
const REACH_MAX := 0.83
const REACH_MIN := 0.52
## Head clearance under the roof kept by fit_reach (metres), and how far it may
## recline or sink the seat to get it
const HEADROOM := 0.025
const MAX_DROP := 0.1
const MAX_EXTRA_RECLINE := deg_to_rad(10.0)

var vehicle: Node3D
var seat_node: Node3D
var model: Node3D
var skeleton: Skeleton3D
var loco: RefCounted
var driver := true
var clip := "Driving"

## Cabin geometry in vehicle space
var seat := Vector3.ZERO
var heel := Vector3.ZERO
var wheel_center := Vector3.ZERO
var wheel_axis := Vector3.BACK
var wheel_radius := 0.19
## Back recline from vertical to hold (radians); bus drivers sit upright
var recline := deg_to_rad(20.0)
## Head pitch to hold (radians, negative = looking a little down)
var head_pitch := deg_to_rad(-4.0)
## 0..1: how much the arm IK holds the hands on the rim (blends in and out
## while getting in and out)
var hand_weight := 1.0
## 0..1: how much the leg IK plants the feet
var leg_weight := 1.0
## Extra slide of the seat along the car (set by fit_reach)
var seat_slide := 0.0
## How far the hips sink into the cushion to clear the roof (set by fit_reach)
var seat_drop := 0.0
## Roof and headliner triangles over the seat (vehicle space, three points each)
var roof_triangles := PackedVector3Array()
## Largest seat slide fit_reach may use (bus drivers sit close to the wheel)
var max_slide := 0.25
## How far each hand has actually followed the rim this frame (radians)
var hand_turn := {"Left": 0.0, "Right": 0.0}

var _bones := {}
## Clip pose (local rotations) of the bones this script turns, taken right
## after the last advance and before any of our changes. The imported clips
## drop tracks that never move, so the tree does not rewrite every bone each
## frame; restoring this before each advance keeps our relative turns (lean,
## head) from piling up.
var _clip_pose := {}
var _len := {}
var _hand_len := {"Left": 0.08, "Right": 0.08}
var _face_local := Vector3.BACK
## Head bone to the top of the skull, in skeleton units
var _crown_height := 0.2
var _ankle_height := 0.09


## Builds a seated pose for `model` (already instanced; it is moved under a new
## seat node on `vehicle`). `cabin` holds vehicle-space seat, heel,
## wheel_center, wheel_axis, wheel_radius and recline (see VehicleOccupants).
## `existing_loco` reuses a character's own Locomotion (the player's). Returns
## null if the model has no standard skeleton.
static func create(vehicle_: Node3D, model_: Node3D, cabin: Dictionary, is_driver: bool, existing_loco: RefCounted = null) -> RefCounted:
	var sk := SkeletonMap.skeleton_of(model_)
	if sk == null:
		return null
	var loco_ := existing_loco
	if loco_ == null:
		# Build the new character's locomotion with it already in the scene, under
		# the vehicle (it is moved onto its seat below)
		if model_.get_parent() == null:
			vehicle_.add_child(model_)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(model_.get_instance_id())
		loco_ = Locomotion.create(model_, {}, rng)
	if loco_ == null:
		return null
	var pose := new()
	pose._setup(vehicle_, model_, sk, loco_, cabin, is_driver)
	return pose


func _setup(vehicle_: Node3D, model_: Node3D, sk: Skeleton3D, loco_: RefCounted, cabin: Dictionary, is_driver: bool) -> void:
	vehicle = vehicle_
	model = model_
	skeleton = sk
	loco = loco_
	driver = is_driver
	clip = "Driving" if driver else "Sit_Idle"
	seat = cabin.get("seat", Vector3(0.4, 0.6, 0.1))
	heel = cabin.get("heel", seat + Vector3(0.0, -0.3, 0.8))
	wheel_center = cabin.get("wheel_center", seat + Vector3(0, 0.3, 0.45))
	wheel_axis = cabin.get("wheel_axis", Vector3.BACK)
	wheel_radius = cabin.get("wheel_radius", 0.19)
	recline = cabin.get("recline", recline)
	max_slide = cabin.get("max_slide", 0.25)
	roof_triangles = cabin.get("roof_triangles", PackedVector3Array())
	for side in ["Left", "Right"]:
		for part in ["UpperArm", "LowerArm", "Hand", "MiddleProximal", "UpperLeg", "LowerLeg", "Foot", "Toes"]:
			_bones[side + part] = sk.find_bone(side + part)
	for bone in ["Hips", "Spine", "Chest", "Neck", "Head"]:
		_bones[bone] = sk.find_bone(bone)
	# Segment lengths from the rest pose (skeleton space; bones only rotate)
	for pair in [["UpperArm", "LowerArm"], ["LowerArm", "Hand"], ["UpperLeg", "LowerLeg"], ["LowerLeg", "Foot"]]:
		for side in ["Left", "Right"]:
			var a: int = _bones[side + pair[0]]
			var b: int = _bones[side + pair[1]]
			_len[side + pair[0]] = sk.get_bone_global_rest(a).origin.distance_to(sk.get_bone_global_rest(b).origin)
	for side in ["Left", "Right"]:
		var hand: int = _bones[side + "Hand"]
		var knuckle: int = _bones[side + "MiddleProximal"]
		if knuckle >= 0:
			_hand_len[side] = sk.get_bone_global_rest(hand).origin.distance_to(sk.get_bone_global_rest(knuckle).origin)
		else:
			_hand_len[side] = _len[side + "LowerArm"] * 0.3
	# Ankle height above the sole, from the rest pose, in skeleton units
	# Which way the face points in the head bone's own frame (rest faces +Z)
	var head_bone: int = _bones["Head"]
	if head_bone >= 0:
		var model_forward := Locomotion._chain(sk, model_).basis.orthonormalized().inverse() * Vector3.BACK
		_face_local = (sk.get_bone_global_rest(head_bone).basis.orthonormalized().inverse() * model_forward).normalized()
	# The crown sits about a third of the hips-to-head distance above the head
	# bone (the bone is at the base of the skull)
	if head_bone >= 0 and _bones["Hips"] >= 0:
		_crown_height = sk.get_bone_global_rest(head_bone).origin.distance_to(sk.get_bone_global_rest(_bones["Hips"]).origin) * 0.33
	var foot: int = _bones["LeftFoot"]
	var toes: int = _bones["LeftToes"]
	_ankle_height = absf(sk.get_bone_global_rest(foot).origin.y - (sk.get_bone_global_rest(toes).origin.y if toes >= 0 else 0.0)) + _len["LeftLowerLeg"] * 0.03

	seat_node = Node3D.new()
	seat_node.name = "Seat_" + str(model.name)
	vehicle.add_child(seat_node)
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	seat_node.add_child(model)
	# Models face +Z, like the car
	model.transform = Transform3D(Basis.IDENTITY.scaled(model.scale), Vector3.ZERO)
	# Measure from a clean seated pose whatever the character was doing (a
	# player can arrive mid-jog, or with the looping Fall one-shot still held):
	# stop any one-shot, drop the gait blend to standing still, start from rest.
	loco.tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	loco.set_locomotion(0.0, "idle")
	loco._gait = 0.0
	loco._kerb = 0.0
	sk.reset_bone_poses()
	set_base(clip)
	loco.advance(0.6)
	_snapshot()
	place_on_seat()


## Swaps the clip the character's locomotion tree uses for standing still
## (the base pose under one-shots). `name` "" restores its own idle.
func set_base(name: String) -> void:
	var tree: AnimationTree = loco.tree
	var move := (tree.tree_root as AnimationNodeBlendTree).get_node("move") as AnimationNodeBlendSpace1D
	var idle := move.get_blend_point_node(0) as AnimationNodeAnimation
	if not idle.has_meta("standing_clip"):
		idle.set_meta("standing_clip", idle.animation)
	idle.animation = name if not name.is_empty() else String(idle.get_meta("standing_clip"))


## Moves the model so its hips land on the seat (plus seat_slide forward and
## seat_drop down).
func place_on_seat() -> void:
	var at := seat + Vector3(0, -seat_drop, seat_slide)
	seat_node.transform = Transform3D(Basis.IDENTITY, at)
	model.position = Vector3.ZERO
	var hips := _vehicle_point(_bones["Hips"])
	model.position = seat_node.to_local(vehicle.to_global(at)) - seat_node.to_local(vehicle.to_global(hips))


## Slides the seat along the car so both hands reach the rim at 10 and 2
## without a locked-straight or cramped arm (drivers adjust their seats).
## Call with the wheel centred, after the first pose.
func fit_reach() -> void:
	if not driver:
		return
	for i in 6:
		pose(0.0, 0.0)
		var worst_far := 0.0
		var worst_near := INF
		for side in ["Left", "Right"]:
			var shoulder := _vehicle_point(_bones[side + "UpperArm"])
			var arm: float = (float(_len[side + "UpperArm"]) + float(_len[side + "LowerArm"])) * _scale()
			var d := shoulder.distance_to(_wrist_target_turn(side, 0.0)) / maxf(arm, 0.01)
			worst_far = maxf(worst_far, d)
			worst_near = minf(worst_near, d)
		var shift := 0.0
		if worst_far > REACH_MAX:
			shift = (worst_far - REACH_MAX) * 0.6
		elif worst_near < REACH_MIN:
			shift = -(REACH_MIN - worst_near) * 0.6
		if absf(shift) < 0.003:
			break
		seat_slide = clampf(seat_slide + shift, -max_slide, max_slide)
		place_on_seat()
	_fit_headroom()


## Tall people in low cars: recline a little more, then sink into the cushion,
## until the top of the head clears the roof.
func _fit_headroom() -> void:
	if roof_triangles.is_empty():
		return
	var base_recline := recline
	for i in 8:
		pose(0.0, 0.0)
		var lack := -head_clearance()
		if lack <= 0.0:
			return
		if recline < base_recline + MAX_EXTRA_RECLINE:
			recline = minf(recline + maxf(lack * 1.2, deg_to_rad(2.0)), base_recline + MAX_EXTRA_RECLINE)
		elif seat_drop < MAX_DROP:
			seat_drop = minf(seat_drop + lack + 0.005, MAX_DROP)
			place_on_seat()
		else:
			return


## Top of the head (vehicle space): up the neck-to-head line from the head bone.
func crown_point() -> Vector3:
	var head := _vehicle_point(_bones["Head"])
	var up := (head - _vehicle_point(_bones["Neck"])).normalized() if _bones["Neck"] >= 0 else Vector3.UP
	return head + up * _crown_height * _scale()


## Gap between the top of the head and the roof right above it (metres;
## negative = the head is in the roof): the lowest roof triangle hit by a ray
## straight up from just above the skull base (so a headrest behind the head
## doesn't count). INF where nothing is overhead (open, or no roof data).
func head_clearance() -> float:
	var crown := crown_point()
	var from := Vector3(crown.x, _vehicle_point(_bones["Head"]).y + 0.06, crown.z)
	var roof := INF
	for t in range(0, roof_triangles.size() - 2, 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.UP, roof_triangles[t], roof_triangles[t + 1], roof_triangles[t + 2])
		if hit != null:
			roof = minf(roof, (hit as Vector3).y)
	return roof - HEADROOM - crown.y


## True if the seated character's head clears the roof.
func fits() -> bool:
	return head_clearance() >= -0.005


## One frame of the seated pose. `wheel_angle` is the rim rotation (radians,
## positive = turned left), `steer` the steering fraction -1..1 for the head.
## The clip advances by `delta` first; with `delta` 0 (the distance LOD's
## still pose, seat fitting) the last clip pose is restored instead, so the
## posture and IK below always start from the clean clip pose and pose() can
## be called any number of times.
func pose(wheel_angle: float, steer: float, delta := 0.0) -> void:
	_restore()
	if delta > 0.0 or _clip_pose.is_empty():
		loco.advance(delta)
		_snapshot()
	_posture(steer)
	if leg_weight > 0.0:
		for side in ["Left", "Right"]:
			_leg_ik(side)
	if hand_weight > 0.0:
		for side in ["Left", "Right"]:
			if driver:
				_arm_ik(side, wheel_angle)
			else:
				_lap_ik(side)


## Point on the rim (vehicle space) where `side`'s palm holds the wheel when
## the hand has followed the rim by `turn` radians from 10 / 2 o'clock.
func grip_point(side: String, turn: float) -> Vector3:
	# Top of the rim, in the rim plane: perpendicular to the axis, upward
	var top := (Vector3.UP - wheel_axis * Vector3.UP.dot(wheel_axis)).normalized()
	var left := wheel_axis.cross(top).normalized()
	if left.x < 0.0:
		left = -left
	var base := GRIP_ANGLE if side == "Left" else -GRIP_ANGLE
	var dir := (top * cos(base) + left * sin(base)).normalized()
	return wheel_center + Basis(wheel_axis, turn) * dir * wheel_radius


## The palm point the grip is measured from (vehicle space).
func palm_point(side: String) -> Vector3:
	var wrist := _vehicle_point(_bones[side + "Hand"])
	var knuckle_bone: int = _bones[side + "MiddleProximal"]
	if knuckle_bone < 0:
		return wrist
	return wrist.lerp(_vehicle_point(knuckle_bone), PALM)


## Distance of `side`'s palm from the rim's centre circle (metres).
func rim_error(side: String) -> float:
	var d := palm_point(side) - wheel_center
	var along := d.dot(wheel_axis)
	var radial := (d - wheel_axis * along).length()
	return Vector2(radial - wheel_radius, along).length()


## Puts back the clip pose under our IK and posture changes (before something
## else animates the model, or it leaves the seat).
func clear_overrides() -> void:
	_restore()


## Detaches the model from the seat (keeps it alive) and frees the seat node.
func release() -> Node3D:
	_restore()
	_clip_pose.clear()
	var m := model
	if is_instance_valid(seat_node):
		var xform := m.global_transform
		seat_node.remove_child(m)
		seat_node.queue_free()
		m.transform = xform
	return m


# --- solving -----------------------------------------------------------------

func _snapshot() -> void:
	_clip_pose.clear()
	for key: String in _bones:
		var bone: int = _bones[key]
		if bone >= 0:
			_clip_pose[bone] = skeleton.get_bone_pose_rotation(bone)


func _restore() -> void:
	for bone: int in _clip_pose:
		skeleton.set_bone_pose_rotation(bone, _clip_pose[bone])


func _posture(steer: float) -> void:
	var to_skel := skeleton.global_basis.orthonormalized().inverse() * model.global_basis.orthonormalized()
	var side_axis := (to_skel * Vector3.RIGHT).normalized()
	var up_axis := (to_skel * Vector3.UP).normalized()
	var w := leg_weight
	# Back: measure the hips-to-neck recline (vehicle space, +Z forward) and
	# lean forward or back to the target, shared between spine and chest.
	# Positive turns about the side axis lean forward.
	var hips: int = _bones["Hips"]
	var neck: int = _bones["Neck"]
	if hips >= 0 and neck >= 0 and _bones["Spine"] >= 0:
		var back := _vehicle_point(neck) - _vehicle_point(hips)
		var lean := (atan2(-back.z, back.y) - recline) * w
		_rotate_global(_bones["Spine"], Quaternion(side_axis, lean * 0.6))
		if _bones["Chest"] >= 0:
			_rotate_global(_bones["Chest"], Quaternion(side_axis, lean * 0.4))
	var head: int = _bones["Head"]
	if head < 0:
		return
	# Head: level the face (it points along +Z in the rest pose), then turn it
	# into corners
	var face := (vehicle.global_basis.inverse() * (skeleton.global_basis * (skeleton.get_bone_global_pose(head).basis * _face_local))).normalized()
	var pitch := atan2(face.y, Vector2(face.x, face.z).length())
	var level := (pitch - head_pitch) * w
	if neck >= 0:
		_rotate_global(neck, Quaternion(side_axis, level * 0.35))
	_rotate_global(head, Quaternion(side_axis, level * 0.65))
	if driver:
		if neck >= 0:
			_rotate_global(neck, Quaternion(up_axis, steer * HEAD_TURN * 0.4))
		_rotate_global(head, Quaternion(up_axis, steer * HEAD_TURN * 0.6))


## Wrist position (vehicle space) that puts the palm on the grip point (hand
## followed the rim by `turn`), and the direction the fingers should point.
func _wrist_target_turn(side: String, turn: float) -> Vector3:
	return grip_point(side, turn) - _finger_dir(side, turn) * float(_hand_len[side]) * _scale() * PALM


func _finger_dir(side: String, turn: float) -> Vector3:
	var radial := (grip_point(side, turn) - wheel_center).normalized()
	# Fingers reach from the driver's side over the rim and outward
	return (radial * 0.55 - wheel_axis * 0.75 + Vector3.UP * 0.15).normalized()


## How far round the rim `side`'s hand follows a wheel turned by
## `wheel_angle`: up to HAND_FOLLOW, and only as far as the arm reaches (the
## grip slides along the rim instead), so the palm always stays on the rim.
func _reachable_turn(side: String, wheel_angle: float) -> float:
	var wanted := clampf(wheel_angle, -HAND_FOLLOW, HAND_FOLLOW)
	var shoulder := _vehicle_point(_bones[side + "UpperArm"])
	var a: float = float(_len[side + "UpperArm"]) * _scale()
	var b: float = float(_len[side + "LowerArm"]) * _scale()
	var near := absf(a - b) * 1.2 + 0.03
	var far := (a + b) * REACH_LIMIT
	if _reaches(side, shoulder, wanted, near, far) or not _reaches(side, shoulder, 0.0, near, far):
		return wanted
	var good := 0.0
	var bad := wanted
	for i in 10:
		var mid := (good + bad) * 0.5
		if _reaches(side, shoulder, mid, near, far):
			good = mid
		else:
			bad = mid
	return good


func _reaches(side: String, shoulder: Vector3, turn: float, near: float, far: float) -> bool:
	var d := shoulder.distance_to(_wrist_target_turn(side, turn))
	return d <= far and d >= near


func _arm_ik(side: String, wheel_angle: float) -> void:
	var upper: int = _bones[side + "UpperArm"]
	var lower: int = _bones[side + "LowerArm"]
	var hand: int = _bones[side + "Hand"]
	var sign_x := 1.0 if side == "Left" else -1.0
	var shoulder := _vehicle_point(upper)
	var turn := _reachable_turn(side, wheel_angle)
	hand_turn[side] = turn
	# Elbows hang down, a little out and back
	var pole := shoulder + Vector3(sign_x * 0.35, -0.6, -0.15)
	_two_bone(upper, lower, hand, _to_skel(_wrist_target_turn(side, turn)), _to_skel(pole), hand_weight)
	var knuckle: int = _bones[side + "MiddleProximal"]
	if knuckle >= 0:
		var current := _skel_point(knuckle) - _skel_point(hand)
		var wanted := _to_skel_dir(_finger_dir(side, turn))
		_aim(hand, current, wanted, hand_weight)


## A passenger's hand rests on top of its own thigh, fingers towards the knee
## (the seated clip's hands lift off the lap once the back is straightened).
func _lap_ik(side: String) -> void:
	var thigh: int = _bones[side + "UpperLeg"]
	var knee: int = _bones[side + "LowerLeg"]
	var upper: int = _bones[side + "UpperArm"]
	var lower: int = _bones[side + "LowerArm"]
	var hand: int = _bones[side + "Hand"]
	if thigh < 0 or knee < 0:
		return
	var hip := _vehicle_point(thigh)
	var knee_point := _vehicle_point(knee)
	var along := (knee_point - hip).normalized()
	# Top of the thigh, a thigh's radius above the bone
	var top := (Vector3.UP - along * Vector3.UP.dot(along)).normalized()
	var palm := hip.lerp(knee_point, 0.6) + top * float(_len[side + "UpperLeg"]) * _scale() * 0.17
	var fingers := (along - top * 0.3).normalized()
	var wrist := palm - fingers * float(_hand_len[side]) * _scale() * PALM
	var sign_x := 1.0 if side == "Left" else -1.0
	var shoulder := _vehicle_point(upper)
	var pole := shoulder + Vector3(sign_x * 0.35, -0.4, -0.3)
	_two_bone(upper, lower, hand, _to_skel(wrist), _to_skel(pole), hand_weight)
	var knuckle: int = _bones[side + "MiddleProximal"]
	if knuckle >= 0:
		_aim(hand, _skel_point(knuckle) - _skel_point(hand), _to_skel_dir(fingers), hand_weight)


func _leg_ik(side: String) -> void:
	var thigh: int = _bones[side + "UpperLeg"]
	var shin: int = _bones[side + "LowerLeg"]
	var foot: int = _bones[side + "Foot"]
	if thigh < 0 or shin < 0 or foot < 0:
		return
	var sign_x := 1.0 if side == "Left" else -1.0
	var hip := _vehicle_point(thigh)
	# Feet a hip-width apart under the seat line, the right one on the pedal
	var ankle := Vector3(seat.x + sign_x * 0.12, heel.y + _ankle_height * _scale(), heel.z + (0.04 if side == "Right" else 0.0) + seat_slide)
	var pole := hip + Vector3(sign_x * 0.08, 0.5, 0.8)
	_two_bone(thigh, shin, foot, _to_skel(ankle), _to_skel(pole), leg_weight)


## Rotates `root` and `mid` so the origin of `end` reaches `target`; `pole`
## (both skeleton space) is where the middle joint bends towards.
func _two_bone(root: int, mid: int, end: int, target: Vector3, pole: Vector3, weight: float) -> void:
	var s := _skel_point(root)
	var e := _skel_point(mid)
	var w := _skel_point(end)
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var to_target := target - s
	var reach := clampf(to_target.length(), absf(a - b) + 0.0001, a + b - 0.0001)
	var dir := to_target.normalized()
	var bend := pole - s
	bend -= dir * bend.dot(dir)
	if bend.length_squared() < 1e-10:
		bend = (e - s) - dir * (e - s).dot(dir)
	bend = bend.normalized()
	var cos_a := clampf((a * a + reach * reach - b * b) / (2.0 * a * reach), -1.0, 1.0)
	var elbow := s + dir * (a * cos_a) + bend * (a * sqrt(1.0 - cos_a * cos_a))
	_aim(root, e - s, elbow - s, weight)
	var e2 := _skel_point(mid)
	var w2 := _skel_point(end)
	_aim(mid, w2 - e2, (s + dir * reach) - e2, weight)


## Turns `bone` (in skeleton space) by the arc from `from` to `to`.
func _aim(bone: int, from: Vector3, to: Vector3, weight: float) -> void:
	if from.length_squared() < 1e-12 or to.length_squared() < 1e-12:
		return
	var arc := Quaternion(from.normalized(), to.normalized())
	if weight < 1.0:
		arc = Quaternion.IDENTITY.slerp(arc, clampf(weight, 0.0, 1.0))
	_rotate_global(bone, arc)


## Pre-multiplies `bone`'s skeleton-space rotation by `turn`.
func _rotate_global(bone: int, turn: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_q := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var global_q := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (parent_q.inverse() * (turn * global_q)).normalized())


func _skel_point(bone: int) -> Vector3:
	return skeleton.get_bone_global_pose(bone).origin


func _vehicle_point(bone: int) -> Vector3:
	return vehicle.to_local(skeleton.to_global(_skel_point(bone)))


func _to_skel(p: Vector3) -> Vector3:
	return skeleton.to_local(vehicle.to_global(p))


func _to_skel_dir(d: Vector3) -> Vector3:
	return (skeleton.global_basis.inverse() * (vehicle.global_basis * d))


## Skeleton-to-vehicle scale (Renderpeople models are in centimetres).
func _scale() -> float:
	return (vehicle.global_basis.inverse() * skeleton.global_basis).get_scale().x
