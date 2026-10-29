extends RefCounted
## Pedestrian movement on the pavement graph (scripts/pavement_graph.gd).
## People walk along the pavement to random destinations, keep to the right
## and step aside to pass each other, stop now and then at a shop front or a
## corner, and cross roads only at crossings: wait at the kerb, look both
## ways, wait for a gap in traffic and then run across. Older people hurry
## but don't sprint; some walk out and break into a run when a car comes.
## Anyone near a car that drives at them or onto the pavement runs clear.
##
## Hooked from pedestrian.gd: `navigation = PedestrianNavigation.new(self)` in
## _ready() and `navigation.physics_step(delta)` before move_and_slide(). It
## sets velocity.x/z, then calls set_locomotion(speed, state, facing) (animator's
## entry point, which turns the body and drives the animation); a pedestrian
## without that method has its rotation.y set here instead.

const City = preload("res://scripts/city.gd")
const RoadGraph = preload("res://scripts/road_graph.gd")
const PavementGraph = preload("res://scripts/pavement_graph.gd")

enum Mode { WALK, PAUSE, KERB, CROSS, FLEE }
const MODE_NAMES := ["walk", "pause", "kerb", "cross", "flee"]
## Keep to the right of the walking line; shift further right to pass someone
const KEEP_RIGHT := 0.45
const PASS_SHIFT := 0.5
## Sideways part of the direction (about 30°) when passing someone on a crossing
const CROSS_PASS := 0.6
const THINK_INTERVAL := 0.25
const DESTINATION_RANGE := 110.0

var ped: CharacterBody3D
var graph: RefCounted
var rng := RandomNumberGenerator.new()
var mode := Mode.WALK
var older := false
## "run" (most people), "walk_then_run" or "hurry" (older people)
var crossing_style := "run"
var walk_speed := 1.35
var run_speed := 4.2
var hurry_speed := 2.1
var current_speed := 0.0
var current_state := "idle"
var facing := Vector3.FORWARD

var _path := PackedInt64Array()
var _index := 0
var _from_node := -1
var _timer := 0.0
var _think := 0.0
var _shift := 0.0
var _shift_target := 0.0
var _cross_from := Vector3.ZERO
var _cross_to := Vector3.ZERO
var _cross_threat := false
## While crossing: steer this much to the side (+ right, - left) to pass a
## slower person directly ahead on the same line
var _cross_pass := 0.0
var _kerb_waited := 0.0
var _look_side := 1.0
var _look_timer := 0.0
var _looks := 0
var _flee_direction := Vector3.ZERO
var _stuck_timer := 0.0
var _last_position := Vector3.ZERO


func _init(p_ped: CharacterBody3D) -> void:
	ped = p_ped
	graph = PavementGraph.shared()
	rng.seed = hash(p_ped.get_instance_id())
	older = rng.randf() < 0.15
	if older:
		crossing_style = "hurry"
		walk_speed = rng.randf_range(1.0, 1.2)
		hurry_speed = rng.randf_range(1.9, 2.3)
	else:
		crossing_style = "walk_then_run" if rng.randf() < 0.3 else "run"
		walk_speed = rng.randf_range(1.2, 1.55)
		run_speed = rng.randf_range(3.8, 4.8)
	_think = rng.randf() * THINK_INTERVAL


func mode_name() -> String:
	return MODE_NAMES[mode]


func is_crossing() -> bool:
	return mode == Mode.CROSS


func physics_step(delta: float) -> void:
	if _from_node < 0:
		_from_node = graph.nearest_node(ped.global_position)
		_plan_from(_from_node, true)
	_think -= delta
	var thinking := _think <= 0.0
	if thinking:
		_think = THINK_INTERVAL
		_scan()
	var move := Vector3.ZERO
	var state := "idle"
	match mode:
		Mode.WALK:
			move = _walk(delta)
			state = "walk"
		Mode.PAUSE:
			_timer -= delta
			if _timer <= 0.0:
				mode = Mode.WALK
		Mode.KERB:
			move = _kerb(delta, thinking)
			state = "wait_at_kerb" if move.length_squared() < 0.01 else "walk"
		Mode.CROSS:
			move = _cross()
			state = "jog" if move.length() < 3.0 else "run"
			if move.length() < 1.7:
				state = "walk"
		Mode.FLEE:
			_timer -= delta
			move = _flee_direction * run_speed
			state = "run"
			if _timer <= 0.0:
				_plan_from(graph.nearest_node(ped.global_position), false)
	# Containment: a walker that ends up off the pavement (shoved by a car, or
	# returning after a flee) heads straight back to the nearest kerb rather than
	# across a road. Crossing and fleeing are the only sanctioned road excursions.
	if mode != Mode.CROSS and mode != Mode.FLEE:
		var back := _toward_pavement(ped.global_position)
		if back != Vector3.ZERO:
			move = back * run_speed
			state = "run"
	if move.length_squared() > 0.01:
		facing = Vector3(move.x, 0.0, move.z).normalized()
	_check_stuck(delta, move)
	ped.velocity.x = move.x
	ped.velocity.z = move.z
	current_speed = Vector2(move.x, move.z).length()
	current_state = state
	# set_locomotion(speed, state, facing) is animator's entry point: it turns the
	# body toward `facing` and drives the animation. A pedestrian without it (a
	# test harness, or before animator's integration) falls back to turning here.
	if ped.has_method("set_locomotion"):
		ped.set_locomotion(current_speed, state, facing)
	elif facing.length_squared() > 0.01:
		ped.rotation.y = lerp_angle(ped.rotation.y, atan2(-facing.x, -facing.z), 8.0 * delta)


func _plan_from(node: int, first: bool) -> void:
	_from_node = node
	var here: Vector3 = graph.points[node]
	var destination := node
	for attempt in 12:
		var candidate := rng.randi_range(0, graph.points.size() - 1)
		if candidate != node and graph.points[candidate].distance_to(here) < DESTINATION_RANGE:
			destination = candidate
			break
	_path = graph.path(node, destination)
	# When starting off the line (spawn, after fleeing) walk to the node first
	_index = 0 if (first or ped.global_position.distance_to(here) > 1.2) else 1
	mode = Mode.WALK
	if _path.size() < 2:
		_path = PackedInt64Array([node])
		_index = 0


## Unit direction from `p` straight back onto the nearest block (pavement), or
## ZERO when already comfortably on a block. Pushes until 0.5 m inside the edge
## so a returning walker doesn't oscillate on the kerb line.
func _toward_pavement(p: Vector3) -> Vector3:
	var push := Vector3.ZERO
	var axes := [p.x, p.z]
	for idx in 2:
		var v: float = axes[idx]
		var cell := roundf(v / City.PITCH + (City.GRID - 1) / 2.0)
		var center := (cell - (City.GRID - 1) / 2.0) * City.PITCH
		if absf(v - center) > City.BLOCK / 2.0 - 0.5:
			if idx == 0:
				push.x = signf(center - v)
			else:
				push.z = signf(center - v)
	return push.normalized() if push.length_squared() > 0.0 else Vector3.ZERO


func _segment_right() -> Vector3:
	var to: Vector3 = graph.points[_path[_index]]
	var from: Vector3 = graph.points[_from_node] if _from_node >= 0 else ped.global_position
	var direction := to - from
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return Vector3.ZERO
	return direction.normalized().cross(Vector3.UP)


func _walk(delta: float) -> Vector3:
	if _index >= _path.size():
		_arrive_destination()
		return Vector3.ZERO
	_shift = move_toward(_shift, _shift_target, 1.5 * delta)
	var node := _path[_index]
	var target: Vector3 = graph.points[node] + _segment_right() * (KEEP_RIGHT + _shift)
	# If physically off the pavement (just after fleeing or a crossing), aim
	# straight at the node, which sits well inside the kerb, rather than hugging
	# the kerb-side walking line. This pulls a displaced walker back promptly.
	if not City.on_block(ped.global_position, -0.1):
		target = graph.points[node]
	var to_target := target - ped.global_position
	to_target.y = 0.0
	if to_target.length() < 0.5:
		_reach_node(node)
		return Vector3.ZERO
	return to_target.normalized() * walk_speed


func _reach_node(node: int) -> void:
	_from_node = node
	_index += 1
	if _index >= _path.size():
		_arrive_destination()
		return
	var next := _path[_index]
	if graph.is_crossing(node, next):
		mode = Mode.KERB
		_cross_from = graph.points[node]
		_cross_to = graph.points[next]
		var right := (_cross_to - _cross_from).normalized().cross(Vector3.UP)
		_cross_from += right * 0.4
		_cross_to += right * 0.4
		_kerb_waited = 0.0
		_looks = 0
		_look_timer = rng.randf_range(0.5, 0.9)
		_look_side = 1.0 if rng.randf() < 0.5 else -1.0
		_cross_threat = false
	elif rng.randf() < (0.12 if graph.is_corner(node) else 0.25):
		# A moment at a corner or a shop front
		mode = Mode.PAUSE
		_timer = rng.randf_range(2.0, 7.0)
		if not graph.is_corner(node):
			# Look into the shop: towards the block centre
			var c: Vector3 = graph.points[node]
			var i := roundi(c.x / City.PITCH + (City.GRID - 1) / 2.0)
			var j := roundi(c.z / City.PITCH + (City.GRID - 1) / 2.0)
			facing = (City.block_center(i, j) - c).normalized()
	if mode != Mode.KERB:
		_shift_target = 0.0


func _arrive_destination() -> void:
	var node := _from_node
	_plan_from(node, false)
	if rng.randf() < 0.5:
		mode = Mode.PAUSE
		_timer = rng.randf_range(3.0, 9.0)


func _kerb(delta: float, thinking: bool) -> Vector3:
	var to_kerb := _cross_from - ped.global_position
	to_kerb.y = 0.0
	if to_kerb.length() > 0.35:
		return to_kerb.normalized() * walk_speed
	_kerb_waited += delta
	_look_timer -= delta
	var road_direction := (_cross_to - _cross_from).normalized()
	if _look_timer <= 0.0:
		_look_timer = rng.randf_range(0.6, 1.0)
		_look_side = -_look_side
		_looks += 1
	facing = road_direction.rotated(Vector3.UP, _look_side * 1.1) if _looks < 3 else road_direction
	if thinking and _looks >= 2 and _kerb_waited > 1.2:
		var arrival := _earliest_arrival(_cross_from, _cross_to)
		var cross_time := _cross_from.distance_to(_cross_to) / _planned_cross_speed()
		var patient := _kerb_waited < 15.0
		if arrival > cross_time + 2.0 or (not patient and arrival > 3.0):
			mode = Mode.CROSS
			_cross_pass = 0.0
	return Vector3.ZERO


func _planned_cross_speed() -> float:
	match crossing_style:
		"hurry":
			return hurry_speed
		"walk_then_run":
			return walk_speed * 1.1
	return run_speed


func _cross() -> Vector3:
	var to_far := _cross_to - ped.global_position
	to_far.y = 0.0
	if to_far.length() < 0.45:
		mode = Mode.WALK
		_reach_node(_path[_index])
		return Vector3.ZERO
	var direction := to_far.normalized()
	if _cross_pass != 0.0:
		direction = (direction + Vector3(-direction.z, 0.0, direction.x) * _cross_pass).normalized()
	var speed := _planned_cross_speed()
	if _cross_threat:
		match crossing_style:
			"hurry":
				speed = hurry_speed * 1.25
			"walk_then_run":
				speed = run_speed
			_:
				speed = run_speed * 1.2
	return direction * speed


## Seconds until the first moving car reaches the crossing; INF when clear.
## A car standing on the crossing counts as arriving now.
func _earliest_arrival(a: Vector3, b: Vector3) -> float:
	var earliest := INF
	for car: Node3D in ped.get_tree().get_nodes_in_group("cars"):
		var velocity := _car_velocity(car)
		var q := Geometry3D.get_closest_point_to_segment(car.global_position, a, b)
		var toward := q - car.global_position
		toward.y = 0.0
		var distance := toward.length()
		if velocity.length() < 0.5:
			if distance < 2.6:
				earliest = 0.0
			continue
		if distance > 80.0:
			continue
		var closing := velocity.dot(toward / maxf(distance, 0.01))
		if closing < 0.5:
			continue
		earliest = minf(earliest, maxf(distance - 3.0, 0.0) / closing)
	return earliest


static func _car_velocity(car: Node3D) -> Vector3:
	var driver = car.get("ai_driver")
	if driver != null and car.freeze:
		return driver.heading() * driver.speed
	if car is RigidBody3D:
		return car.linear_velocity
	return Vector3.ZERO


## Every THINK_INTERVAL: traffic threats and people to pass.
func _scan() -> void:
	var p := ped.global_position
	if mode == Mode.CROSS:
		_cross_threat = _earliest_arrival(p, _cross_to) < 2.5 or _earliest_arrival(p, p + facing) < 2.5
		if crossing_style == "walk_then_run" and _cross_threat:
			crossing_style = "run"
		_cross_pass = _passing_side(p)
		return
	if mode != Mode.FLEE:
		for car: Node3D in ped.get_tree().get_nodes_in_group("cars"):
			var velocity := _car_velocity(car)
			var speed := velocity.length()
			if speed < 3.0:
				continue
			var away := p - car.global_position
			away.y = 0.0
			var distance := away.length()
			if distance > 11.0:
				continue
			var heading_at := velocity.normalized().dot(away / maxf(distance, 0.01))
			var on_pavement := City.on_block(car.global_position, 0.3)
			if (on_pavement and heading_at > 0.3) or (distance < 5.0 and heading_at > 0.75):
				var side := velocity.normalized().cross(Vector3.UP)
				if side.dot(away) < 0.0:
					side = -side
				_flee_direction = (side + velocity.normalized() * 0.3).normalized()
				mode = Mode.FLEE
				_timer = rng.randf_range(1.2, 2.0)
				return
	if mode == Mode.WALK:
		_shift_target = 0.0
		for other: Node3D in ped.get_tree().get_nodes_in_group("pedestrians"):
			if other == ped:
				continue
			var rel := other.global_position - p
			rel.y = 0.0
			if rel.length_squared() < 2.6 * 2.6 and rel.dot(facing) > 0.2:
				_shift_target = PASS_SHIFT
				break


## Sideways steer for crossing: 0 when nobody is close ahead on this line,
## otherwise a turn away from the side the person ahead is on.
func _passing_side(p: Vector3) -> float:
	var right := Vector3(-facing.z, 0.0, facing.x)
	for other: Node3D in ped.get_tree().get_nodes_in_group("pedestrians"):
		if other == ped:
			continue
		var rel := other.global_position - p
		rel.y = 0.0
		var ahead := rel.dot(facing)
		var aside := rel.dot(right)
		if ahead > 0.0 and ahead < 1.8 and absf(aside) < 0.7:
			return -CROSS_PASS if aside > 0.0 else CROSS_PASS
	return 0.0


## Something (a palm, a parked car, a person standing still) is in the way:
## step to the side, then plan again from the nearest pavement node.
func _check_stuck(delta: float, move: Vector3) -> void:
	if move.length_squared() < 0.25:
		_stuck_timer = 0.0
		_last_position = ped.global_position
		return
	_stuck_timer += delta
	if _stuck_timer < 1.5:
		return
	var moved := ped.global_position.distance_to(_last_position)
	_stuck_timer = 0.0
	_last_position = ped.global_position
	if moved > 0.5:
		return
	if mode == Mode.WALK:
		_shift_target = -_shift_target if absf(_shift_target) > 0.1 else PASS_SHIFT
		if moved < 0.15:
			_plan_from(graph.nearest_node(ped.global_position), true)
	elif mode == Mode.FLEE:
		_timer = 0.0
