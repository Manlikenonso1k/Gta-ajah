extends RefCounted
## Road graph built from the city grid. Junctions are nodes; every road
## between two neighbouring junctions has one lane in each direction, driving
## on the right. Lanes are straight centre lines LANE_OFFSET right of the road
## centre; turns at a junction are quadratic curves between the two lane lines.
##
## Lane ids index `lanes`; each lane is a Dictionary:
##   from, to: junction ids; dir, right: unit vectors; origin: the lane line's
##   point level with the `from` junction centre; length: centre to centre.

const City = preload("res://scripts/city.gd")

const N := City.GRID + 1
## Curve ends sit this far from the corner where the two lane lines cross
const RIGHT_TURN_REACH := 9.0
const LEFT_TURN_REACH := 10.0
## Half the size of a junction box (the road width)
const JUNCTION_HALF := City.ROAD / 2.0

static var _shared: RefCounted

var junctions: Array[Vector3] = []
var lanes: Array[Dictionary] = []
## junction id -> Array of outgoing lane ids
var out_lanes: Array = []
var _lane_lookup := {}


static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://scripts/road_graph.gd").new()
	return _shared


func _init() -> void:
	for b in N:
		for a in N:
			junctions.append(Vector3(City.road_line(a), 0.0, City.road_line(b)))
			out_lanes.append([])
	for b in N:
		for a in N:
			if a + 1 < N:
				_add_road(_id(a, b), _id(a + 1, b))
			if b + 1 < N:
				_add_road(_id(a, b), _id(a, b + 1))


static func _id(a: int, b: int) -> int:
	return a + b * N


func _add_road(j0: int, j1: int) -> void:
	_add_lane(j0, j1)
	_add_lane(j1, j0)


func _add_lane(from: int, to: int) -> void:
	var dir := (junctions[to] - junctions[from]).normalized()
	var right := dir.cross(Vector3.UP)
	var lane := {
		"from": from, "to": to, "dir": dir, "right": right,
		"origin": junctions[from] + right * City.LANE_OFFSET,
		"length": junctions[from].distance_to(junctions[to]),
	}
	_lane_lookup[from * 1000 + to] = lanes.size()
	out_lanes[from].append(lanes.size())
	lanes.append(lane)


func lane_between(from: int, to: int) -> int:
	return _lane_lookup.get(from * 1000 + to, -1)


## Point on a lane's centre line, `distance` metres from its `from` junction centre.
func lane_point(lane_id: int, distance: float) -> Vector3:
	var lane: Dictionary = lanes[lane_id]
	return lane.origin + lane.dir * distance


## Lanes leaving the end of `lane_id`, without the U-turn.
func next_lanes(lane_id: int) -> Array:
	var lane: Dictionary = lanes[lane_id]
	var result := []
	for candidate: int in out_lanes[lane.to]:
		if lanes[candidate].to != lane.from:
			result.append(candidate)
	return result


## "straight", "left" or "right" for a move from one lane into the next.
func turn_kind(in_lane: int, out_lane: int) -> String:
	var a: Vector3 = lanes[in_lane].dir
	var b: Vector3 = lanes[out_lane].dir
	if a.dot(b) > 0.9:
		return "straight"
	return "right" if b.dot(lanes[in_lane].right) > 0.5 else "left"


## Points through the junction at the end of `in_lane` into `out_lane`:
## the curve's entry point on in_lane, samples, and its exit point on out_lane.
## For straight on it is the entry and exit at the junction edges.
func turn_points(in_lane: int, out_lane: int, samples := 7) -> PackedVector3Array:
	var lane_in: Dictionary = lanes[in_lane]
	var lane_out: Dictionary = lanes[out_lane]
	var j: Vector3 = junctions[lane_in.to]
	var points := PackedVector3Array()
	var kind := turn_kind(in_lane, out_lane)
	if kind == "straight":
		points.append(j + lane_in.right * City.LANE_OFFSET - lane_in.dir * (JUNCTION_HALF + 1.0))
		points.append(j + lane_in.right * City.LANE_OFFSET + lane_in.dir * (JUNCTION_HALF + 1.0))
		return points
	var corner: Vector3 = j + lane_in.right * City.LANE_OFFSET + lane_out.right * City.LANE_OFFSET
	var reach := RIGHT_TURN_REACH if kind == "right" else LEFT_TURN_REACH
	var p0: Vector3 = corner - lane_in.dir * reach
	var p2: Vector3 = corner + lane_out.dir * reach
	for i in samples + 1:
		var t := float(i) / float(samples)
		points.append(p0.lerp(corner, t).lerp(corner.lerp(p2, t), t))
	return points


## Nearest lane to `p`, preferring lanes heading along `heading` when given.
## Returns {"lane": id, "distance": metres along the lane from its origin}.
func nearest_lane(p: Vector3, heading := Vector3.ZERO) -> Dictionary:
	var best := -1
	var best_score := INF
	var best_distance := 0.0
	for id in lanes.size():
		var lane: Dictionary = lanes[id]
		var along := clampf((p - lane.origin).dot(lane.dir), 0.0, lane.length)
		var offset: Vector3 = lane.origin + lane.dir * along - p
		offset.y = 0.0
		var score := offset.length()
		if heading.length_squared() > 0.01 and heading.dot(lane.dir) < 0.0:
			score += 6.0
		if score < best_score:
			best_score = score
			best = id
			best_distance = along
	return {"lane": best, "distance": best_distance}


## Junction id whose box contains `p` (with `margin`), or -1.
func junction_at(p: Vector3, margin := 0.0) -> int:
	var a := roundi(p.x / City.PITCH + City.GRID / 2.0)
	var b := roundi(p.z / City.PITCH + City.GRID / 2.0)
	if a < 0 or a >= N or b < 0 or b >= N:
		return -1
	var j := junctions[_id(a, b)]
	if absf(p.x - j.x) <= JUNCTION_HALF + margin and absf(p.z - j.z) <= JUNCTION_HALF + margin:
		return _id(a, b)
	return -1


## True when `p` is on asphalt (any road or junction inside the city).
static func on_road(p: Vector3) -> bool:
	return absf(p.x) <= City.HALF and absf(p.z) <= City.HALF and not City.on_block(p)
