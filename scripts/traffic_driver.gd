extends RefCounted
## One AI driver. Follows a rolling path made of lane centre lines (driving on
## the right) and junction curves from RoadGraph, picks a random turn at every
## junction, keeps a gap, gives way at junctions and stops for people.
##
## Nearby cars: `control()` runs every physics frame and steers the car's
## VehicleBody3D (pure pursuit, looking a few metres ahead on the path).
## Distant cars: `advance_lightweight()` moves a frozen car along the path.
## `think()` (speed planning) runs on traffic.gd's slower ticks.

const City = preload("res://scripts/city.gd")
const RoadGraph = preload("res://scripts/road_graph.gd")

const NORMAL := {
	"cruise_factor": 0.32, "cruise_min": 9.0, "cruise_max": 12.5, "accel": 2.0,
	"decel": 3.0, "min_gap": 5.0, "gap_time": 1.5, "right_turn": 4.5, "left_turn": 5.5,
	"ped_lateral": 2.6, "ped_margin": 4.5,
}
## Danfo-style: faster, closer, brakes later, overtakes, slows less for people
## (but still stops for anyone actually in the way).
const RECKLESS := {
	"cruise_factor": 0.46, "cruise_min": 13.0, "cruise_max": 16.5, "accel": 3.2,
	"decel": 5.5, "min_gap": 2.5, "gap_time": 0.6, "right_turn": 5.5, "left_turn": 6.5,
	"ped_lateral": 1.9, "ped_margin": 2.5,
}
const LOOK_RANGE := 50.0

var car: VehicleBody3D
var traffic: Node
var graph: RefCounted
var reckless := false
var params: Dictionary = NORMAL
var cruise := 10.0
var rng := RandomNumberGenerator.new()

## Rolling path: points and cumulative distance; `s` is the car's progress.
var points := PackedVector3Array()
var cum := PackedFloat32Array()
var s := 0.0
var tail_lane := -1
## Junction movements on the path: {junction, entry, exit, kind, dense, held}
var marks: Array[Dictionary] = []

## Output of think(): the speed the car may drive now and why it is limited
var allowed_speed := 0.0
var limit_reason := ""
## Lightweight-model speed and ride height
var speed := 0.0
var ride_height := 0.65
## Lateral offset to the left of the path (overtaking)
var offset := 0.0
var offset_target := 0.0
var overtaking: Node3D = null
var lateral_error := 0.0
var _stationary_block_time := 0.0

## Physics-mode outputs read by car.gd
var out_throttle := 0.0
var out_steer := 0.0
var out_brake := 0.0
var reverse_timer := 0.0
var stuck_time := 0.0
var stuck_count := 0
var off_lane_time := 0.0


func _init(p_car: VehicleBody3D, p_traffic: Node, p_reckless: bool, seed_value: int) -> void:
	car = p_car
	traffic = p_traffic
	graph = RoadGraph.shared()
	reckless = p_reckless
	params = RECKLESS if reckless else NORMAL
	rng.seed = seed_value


func setup_cruise(top_speed: float) -> void:
	cruise = clampf(top_speed * float(params.cruise_factor), params.cruise_min, params.cruise_max)


## Start on `lane`, `distance` metres from the lane's origin junction centre.
func start(lane: int, distance: float) -> void:
	traffic.release_all(self)
	tail_lane = lane
	points = PackedVector3Array([graph.lane_point(lane, distance - 8.0), graph.lane_point(lane, distance)])
	cum = PackedFloat32Array([0.0, 8.0])
	s = 8.0
	marks.clear()
	offset = 0.0
	offset_target = 0.0
	overtaking = null
	_extend()


func heading() -> Vector3:
	return _sample(s)[1]


func _extend() -> void:
	while cum[cum.size() - 1] - s < LOOK_RANGE + 40.0:
		var options: Array = graph.next_lanes(tail_lane)
		var next: int = options[0]
		if options.size() > 1:
			var straight := -1
			for candidate: int in options:
				if graph.turn_kind(tail_lane, candidate) == "straight":
					straight = candidate
			if straight >= 0 and rng.randf() < 0.5:
				next = straight
			else:
				var turns := options.filter(func(c: int) -> bool: return c != straight)
				next = turns[rng.randi() % turns.size()] if not turns.is_empty() else options[0]
		var turn: PackedVector3Array = graph.turn_points(tail_lane, next)
		var entry := _append(turn[0])
		for i in range(1, turn.size()):
			_append(turn[i])
		var dense := PackedVector3Array()
		for i in turn.size() - 1:
			var steps := maxi(1, ceili(turn[i].distance_to(turn[i + 1])))
			for k in steps:
				dense.append(turn[i].lerp(turn[i + 1], float(k) / steps))
		dense.append(turn[turn.size() - 1])
		marks.append({
			"junction": graph.lanes[tail_lane].to, "entry": entry, "exit": cum[cum.size() - 1],
			"kind": graph.turn_kind(tail_lane, next), "dense": dense, "held": false,
		})
		tail_lane = next


func _append(p: Vector3) -> float:
	var last := points[points.size() - 1]
	var d := cum[cum.size() - 1] + last.distance_to(p)
	points.append(p)
	cum.append(d)
	return d


## Drops path behind the car so the arrays stay short.
func _trim() -> void:
	if s < 60.0:
		return
	var cut := 0
	while cut + 1 < cum.size() and cum[cut + 1] < s - 15.0:
		cut += 1
	if cut == 0:
		return
	var shift := cum[cut]
	points = points.slice(cut)
	cum = cum.slice(cut)
	for i in cum.size():
		cum[i] -= shift
	s -= shift
	var kept: Array[Dictionary] = []
	for mark in marks:
		mark.entry -= shift
		mark.exit -= shift
		if mark.exit > -20.0:
			kept.append(mark)
	marks = kept


## [position, unit tangent] at path distance `d`
func _sample(d: float) -> Array:
	var i := clampi(cum.bsearch(d) - 1, 0, cum.size() - 2)
	var a := points[i]
	var b := points[i + 1]
	var span := maxf(cum[i + 1] - cum[i], 0.001)
	var t := clampf((d - cum[i]) / span, 0.0, 1.0)
	return [a.lerp(b, t), (b - a).normalized()]


## Closest path distance to `p` within [from, to], with its lateral offset
## (positive = left of the path). Returns [distance, signed lateral, unsigned].
func _project(p: Vector3, from: float, to: float) -> Array:
	var i0 := clampi(cum.bsearch(from) - 1, 0, cum.size() - 2)
	var i1 := clampi(cum.bsearch(to), 0, cum.size() - 2)
	var best_d := from
	var best_sq := INF
	var best_side := 0.0
	var flat := Vector3(p.x, 0.0, p.z)
	for i in range(i0, i1 + 1):
		var a := Vector3(points[i].x, 0.0, points[i].z)
		var b := Vector3(points[i + 1].x, 0.0, points[i + 1].z)
		var ab := b - a
		var len_sq := maxf(ab.length_squared(), 0.0001)
		var t := clampf((flat - a).dot(ab) / len_sq, 0.0, 1.0)
		var q := a + ab * t
		var sq := flat.distance_squared_to(q)
		if sq < best_sq:
			best_sq = sq
			best_d = cum[i] + (cum[i + 1] - cum[i]) * t
			best_side = (flat - q).dot(Vector3.UP.cross(ab).normalized())
	return [best_d, best_side, sqrt(best_sq)]


func _left(tangent: Vector3) -> Vector3:
	return Vector3.UP.cross(tangent)


func half_length() -> float:
	return car.ai_half_length()


## Speed planning: turns, junction give-way, the car ahead, people, overtaking.
func think(cars: Array, people: Array, dt: float) -> void:
	var p := car.global_position
	var my_speed := speed if car.freeze else car.linear_velocity.length()
	var decel: float = params.decel
	var limit := cruise
	var reason := "cruise"
	var my_half := half_length()

	# The car or obstacle ahead, and whether the oncoming lane is clear
	var leader: Node3D = null
	var leader_gap := INF
	var leader_speed := 0.0
	var oncoming_clear := true
	for other: Node3D in cars:
		if other == car:
			continue
		var rel := other.global_position - p
		if rel.length_squared() > 70.0 * 70.0:
			continue
		var proj := _project(other.global_position, s - 12.0, s + LOOK_RANGE + 10.0)
		var along: float = proj[0] - s
		var side: float = proj[1]
		var other_half: float = other.ai_half_length() if other.has_method("ai_half_length") else 2.3
		if absf(side - offset) < 1.9 + absf(offset - offset_target) * 0.5 and along > 0.0:
			var gap: float = along - my_half - other_half
			if gap < leader_gap:
				leader_gap = gap
				leader = other
				leader_speed = maxf(0.0, _velocity_of(other).dot(_sample(proj[0])[1]))
		if side > 1.9 and side < 6.0 and along > -my_half - other_half - 6.0 and along < 60.0:
			oncoming_clear = false
	if leader != null:
		var free := leader_gap - float(params.min_gap) - my_speed * float(params.gap_time) * 0.5
		var v := sqrt(leader_speed * leader_speed + 2.0 * decel * maxf(free, 0.0))
		if leader_gap < float(params.min_gap):
			v = minf(v, leader_speed * 0.5)
		if v < limit:
			limit = v
			reason = "gap"

	# People on the road ahead (and where they will be in a second)
	var person_block := false
	for person: Node3D in people:
		var pos := person.global_position
		var rel := pos - p
		if rel.length_squared() > 45.0 * 45.0:
			continue
		var vel: Vector3 = person.velocity if "velocity" in person else Vector3.ZERO
		for probe: Vector3 in [pos, pos + vel * 1.2]:
			if not RoadGraph.on_road(probe) and City.on_block(probe, -0.2):
				continue
			var proj := _project(probe, s, s + 40.0)
			if absf(float(proj[1]) - offset) > float(params.ped_lateral):
				continue
			var along: float = proj[0] - s - my_half
			var v := sqrt(2.0 * decel * maxf(along - float(params.ped_margin), 0.0))
			if v < limit:
				limit = v
				reason = "person"
				person_block = vel.length() < 0.3

	# Turn speeds and junction give-way
	for mark in marks:
		if mark.exit + my_half < s:
			continue
		var to_entry: float = mark.entry - s - my_half
		if to_entry > LOOK_RANGE:
			break
		if mark.kind != "straight":
			var turn_speed: float = params.right_turn if mark.kind == "right" else params.left_turn
			var v := sqrt(turn_speed * turn_speed + 2.0 * decel * maxf(to_entry, 0.0))
			if v < limit:
				limit = v
				reason = "turn"
		if not mark.held:
			var queue_clear := leader == null or leader_gap > to_entry + 1.0
			if to_entry < 14.0 and (queue_clear or to_entry < 0.0) and traffic.request_junction(self, mark):
				mark.held = true
			else:
				var v := sqrt(2.0 * decel * maxf(to_entry - 1.0, 0.0))
				if v < limit:
					limit = v
					reason = "give_way"
				break

	_plan_overtake(leader, leader_gap, leader_speed, oncoming_clear, person_block, dt)
	if offset > 0.5 and not oncoming_clear and overtaking == null:
		# Returning to the lane with traffic coming: don't speed up
		limit = minf(limit, my_speed)
	allowed_speed = maxf(limit, 0.0)
	limit_reason = reason


func _plan_overtake(leader: Node3D, gap: float, leader_speed: float, oncoming_clear: bool, person_block: bool, dt: float) -> void:
	var next_junction := INF
	for mark in marks:
		if mark.exit + half_length() >= s:
			next_junction = mark.entry - s
			break
	if overtaking != null:
		var done := not is_instance_valid(overtaking)
		if not done:
			var proj := _project(overtaking.global_position, s - 30.0, s + LOOK_RANGE)
			var other_half: float = overtaking.ai_half_length() if overtaking.has_method("ai_half_length") else 1.0
			done = float(proj[0]) < s - half_length() - other_half - 5.0
		if done or next_junction < 12.0 or (not oncoming_clear and offset < 1.5):
			overtaking = null
			offset_target = 0.0
		return
	var stationary := leader != null and leader_speed < 0.3 and gap < 14.0
	_stationary_block_time = _stationary_block_time + dt if (stationary or person_block) else 0.0
	if leader == null and not person_block:
		return
	var want := false
	if reckless and leader != null and leader_speed < cruise * 0.7 and gap < 25.0 and gap > 1.5:
		want = true
	# Anyone: go round something that has not moved for a while (a parked or
	# abandoned car, a person standing in the road), but not a queue at a junction
	if _stationary_block_time > 5.0 and limit_reason != "give_way":
		var queued: bool = leader != null and leader.get("ai_driver") != null and leader.ai_driver.limit_reason in ["give_way", "gap", "person"]
		want = want or not queued
	if want and oncoming_clear and next_junction > maxf(gap, 0.0) + 30.0:
		overtaking = leader
		offset_target = City.LANE_WIDTH
		_stationary_block_time = 0.0


func _velocity_of(node: Node3D) -> Vector3:
	var other_driver = node.get("ai_driver")
	if other_driver != null and node.freeze:
		return other_driver.heading() * other_driver.speed
	if node is RigidBody3D:
		return node.linear_velocity
	return Vector3.ZERO


## Physics-mode steering and pedals for car.gd, every physics frame.
func control(delta: float) -> void:
	var p := car.global_position
	var proj := _project(p, s - 4.0, s + 12.0)
	s = maxf(s, float(proj[0]))
	lateral_error = absf(float(proj[1]) - offset)
	_extend()
	_trim()
	offset = move_toward(offset, offset_target, 1.4 * delta)
	var forward_speed := car.linear_velocity.dot(car.global_basis.z)
	var v := car.linear_velocity.length()
	var look := clampf(3.5 + v * 0.45, 4.5, 12.0)
	var sample := _sample(s + look)
	var target: Vector3 = sample[0] + _left(sample[1]) * offset
	var local := car.global_basis.inverse() * (target - p)
	var alpha := atan2(local.x, maxf(local.z, 0.1))
	var dist := maxf(Vector2(local.x, local.z).length(), 1.0)
	var wheel_angle := atan(2.0 * car.ai_wheelbase() * sin(alpha) / dist)
	out_steer = clampf(wheel_angle / maxf(car.ai_max_steer(), 0.05), -1.0, 1.0)

	if reverse_timer > 0.0:
		reverse_timer -= delta
		out_steer = -out_steer
		out_throttle = -0.6
		out_brake = 0.0
		return
	stuck_time = stuck_time + delta if (allowed_speed > 1.5 and v < 0.4) else 0.0
	if stuck_time > 3.0:
		stuck_time = 0.0
		stuck_count += 1
		reverse_timer = 1.6
	elif v > 3.0:
		stuck_count = 0
	off_lane_time = off_lane_time + delta if lateral_error > 5.0 else 0.0

	var error := allowed_speed - forward_speed
	out_throttle = 0.0
	out_brake = 0.0
	if allowed_speed < 0.3:
		out_brake = 1.0
	elif error > 0.0:
		out_throttle = clampf(error * 0.35 + 0.15, 0.0, 1.0)
	elif error < -0.6:
		out_brake = clampf(-error * 0.25, 0.1, 1.0)


## Physics → lightweight: remember where the car is on the path.
func enter_lightweight() -> void:
	var proj := _project(car.global_position, s - 6.0, s + 20.0)
	s = maxf(s, float(proj[0]))
	speed = maxf(car.linear_velocity.dot(car.global_basis.z), 0.0)
	ride_height = clampf(car.global_position.y, 0.3, 1.2)


## Lightweight → physics: carry the current speed into the rigid body.
func exit_lightweight() -> void:
	car.linear_velocity = heading() * speed
	car.angular_velocity = Vector3.ZERO


func advance_lightweight(dt: float) -> void:
	var rate: float = params.accel if allowed_speed > speed else params.decel * 1.5
	speed = move_toward(speed, allowed_speed, rate * dt)
	s += speed * dt
	offset = move_toward(offset, offset_target, 1.4 * dt)
	_extend()
	_trim()
	var sample := _sample(s)
	var tangent: Vector3 = sample[1]
	var pos: Vector3 = sample[0] + _left(tangent) * offset
	pos.y = ride_height
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(tangent.x, tangent.z)), pos)
	lateral_error = absf(offset)


## Path ahead for the debug view.
func planned_path(length := 45.0) -> PackedVector3Array:
	var result := PackedVector3Array()
	var d := s
	while d < s + length:
		var sample := _sample(d)
		result.append(sample[0] + _left(sample[1]) * (offset if d - s < 8.0 else offset_target))
		d += 2.0
	return result


## Distance to the path's lane centre (for tests; 0 while overtaking offsets are applied).
func lane_error() -> float:
	return lateral_error
