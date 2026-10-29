extends RefCounted
## The danfo conductor (Task 5 Phase 3): on a moving danfo he stands on the
## step in the open sliding doorway, one foot on the step, his inner hand on
## the roof edge, leaning out and swaying with the van's braking and turns.
## When the danfo stops he steps down beside the door, and he climbs back on
## once it pulls away.
##
## vehicle_occupants.gd creates him for traffic danfos whose vehicles.json
## cabin has "conductor": {"step", "grip", "ground"} (car-local metres: where
## he stands, the roof point he holds, where he waits beside the door) and
## calls update() each frame while the van is in full detail.
##
## There is no hanging clip, so he plays a standing idle and his arm is then
## bent onto the grip with two-bone IK, the same way the ragdoll writes bones:
## after the AnimationTree has written the clip, by setting bone rotations.

const Locomotion = preload("res://scripts/locomotion.gd")
const AnimationSets = preload("res://scripts/animation_sets.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")

## Lean out from the van while hanging on, and how much the van's
## acceleration sways him (radians per m/s^2)
const LEAN_OUT := 0.24
const SWAY_TURN := 0.035
const SWAY_BRAKE := 0.03
const SWAY_MAX := 0.16
## He steps down after the van has stood this long, and back up once it moves
const STOP_TIME := 0.8
const MOVE_SPEED := 1.2
const STEP_TIME := 0.6
## The arm that holds on: the inner one (towards +X, the van's middle)
const ARM := "Left"

var car: Node3D
var model: Node3D
var loco: RefCounted
var skeleton: Skeleton3D
var character_id := ""
var step := Vector3.ZERO
var grip := Vector3.ZERO
var ground := Vector3.ZERO
## 1 on the step, 0 on the ground beside the door
var on_board := 1.0
## Keeps him on the step whatever the van does (renders and tests)
var hold_on := false
var _stopped := 0.0
var _sway := Vector2.ZERO
var _last_velocity := Vector3.ZERO


## A conductor for `car` from registry `entry`, or null if the model can't
## take the clips. `points` is the cabin's "conductor" dictionary.
static func create(car_: Node3D, model_: Node3D, entry: Dictionary, points: Dictionary) -> RefCounted:
	car_.add_child(model_)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(entry.get("id", ""))
	var clips := AnimationSets.pick(entry.get("id", ""), entry.get("gender", ""), entry.get("tags", []))
	var loco_ = Locomotion.create(model_, clips, rng)
	if loco_ == null:
		model_.free()
		return null
	var c := new()
	c.car = car_
	c.model = model_
	c.loco = loco_
	c.skeleton = SkeletonMap.skeleton_of(model_)
	c.character_id = entry.get("id", "")
	c.step = _v(points.step)
	c.grip = _v(points.grip)
	c.ground = _v(points.ground)
	c.update(0.0)
	return c


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## True while he is on the step (not waiting on the ground).
func is_on_board() -> bool:
	return on_board > 0.5


func update(delta: float) -> void:
	var velocity: Vector3 = car.linear_velocity if car is RigidBody3D else Vector3.ZERO
	var speed := velocity.length()
	_stopped = _stopped + delta if speed < 0.5 else 0.0
	var target := on_board
	if hold_on:
		target = 1.0
	elif _stopped > STOP_TIME:
		target = 0.0
	elif speed > MOVE_SPEED:
		target = 1.0
	if delta > 0.0:
		on_board = move_toward(on_board, target, delta / STEP_TIME)
		# The van's acceleration in its own frame: braking leans him forward,
		# turning swings him out or in
		var accel: Vector3 = car.global_basis.inverse() * ((velocity - _last_velocity) / delta)
		var want := Vector2(clampf(-accel.x * SWAY_TURN, -SWAY_MAX, SWAY_MAX), clampf(-accel.z * SWAY_BRAKE, -SWAY_MAX, SWAY_MAX))
		_sway = _sway.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
	_last_velocity = velocity

	# Climbing on and off: up over the step with a small lift in the middle
	var k := smoothstep(0.0, 1.0, on_board)
	var feet := ground.lerp(step, k) + Vector3(0, sin(k * PI) * 0.12, 0)
	var lean := (LEAN_OUT + _sway.x) * k
	var basis := Basis(Vector3.FORWARD, -lean) * Basis(Vector3.RIGHT, _sway.y * k)
	model.transform = Transform3D(basis.scaled(model.scale), feet)
	loco.set_locomotion(0.0, "idle")
	if delta > 0.0:
		loco.advance(delta)
	if k > 0.05:
		_hold_grip(k)


## Bends the holding arm so the hand reaches the grip, by `weight`.
func _hold_grip(weight: float) -> void:
	var upper := skeleton.find_bone(ARM + "UpperArm")
	var lower := skeleton.find_bone(ARM + "LowerArm")
	var hand := skeleton.find_bone(ARM + "Hand")
	if upper < 0 or lower < 0 or hand < 0:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	var target := to_skeleton * car.to_global(grip)
	# Where the hand would be without IK, so `weight` can ease it in
	target = wrist.lerp(target, weight)
	var reach := target - shoulder
	var d := clampf(reach.length(), 0.05, a + b - 0.001)
	var dir := reach.normalized()
	# The elbow points down and out, away from the van
	var hint := (to_skeleton.basis * car.global_basis * Vector3(-1.0, -1.0, 0.0)).normalized()
	var pole := (hint - dir * hint.dot(dir)).normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow_target := shoulder + dir * a * cos_a + pole * a * sqrt(1.0 - cos_a * cos_a)
	_aim(upper, lower, elbow_target)
	_aim(lower, hand, shoulder + dir * d)


## Turns `bone` so its child joint points at `target` (skeleton space).
func _aim(bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var now := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var want := (target - pose.origin).normalized()
	if now.dot(want) > 0.9999:
		return
	var turned := Basis(Quaternion(now, want)) * pose.basis
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * turned).get_rotation_quaternion())


func release() -> Node3D:
	if model != null and model.get_parent() != null:
		model.get_parent().remove_child(model)
	return model
