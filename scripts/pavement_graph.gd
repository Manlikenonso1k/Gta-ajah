extends RefCounted
## Pavement graph: a walking ring around every block, PAVEMENT_INSET inside the
## kerb, with crossings to the neighbouring blocks. Each block has 8 nodes:
## its 4 corners and the middle of each side (shop fronts). Junction crossings
## join facing corners across a road just outside the junction; mid-block
## crossings join the middles of facing sides across the east-west roads
## (the north-south roads have kerbside parking in the middle of each block).

const City = preload("res://scripts/city.gd")

## Ring order per block: corner (-,-), mid -z, corner (+,-), mid +x,
## corner (+,+), mid +z, corner (-,+), mid -x
const RING := [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0),
	Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)]

static var _shared: RefCounted

var points: Array[Vector3] = []
var astar := AStar3D.new()
## edge key -> true for crossing edges
var _crossings := {}
var _crossing_list: Array = []


static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://scripts/pavement_graph.gd").new()
	return _shared


func _init() -> void:
	var reach := City.BLOCK / 2.0 - City.PAVEMENT_INSET
	for j in City.GRID:
		for i in City.GRID:
			var c := City.block_center(i, j)
			for k in RING.size():
				var id := points.size()
				var offset: Vector2 = RING[k] * reach
				points.append(c + Vector3(offset.x, 0.0, offset.y))
				astar.add_point(id, points[id])
			for k in RING.size():
				astar.connect_points(_node(i, j, k), _node(i, j, (k + 1) % RING.size()))
	for j in City.GRID:
		for i in City.GRID:
			if i + 1 < City.GRID:
				_add_crossing(_node(i, j, 2), _node(i + 1, j, 0))
				_add_crossing(_node(i, j, 4), _node(i + 1, j, 6))
			if j + 1 < City.GRID:
				_add_crossing(_node(i, j, 6), _node(i, j + 1, 0))
				_add_crossing(_node(i, j, 4), _node(i, j + 1, 2))
				_add_crossing(_node(i, j, 5), _node(i, j + 1, 1))


static func _node(i: int, j: int, k: int) -> int:
	return (i + j * City.GRID) * RING.size() + k


func _add_crossing(a: int, b: int) -> void:
	astar.connect_points(a, b)
	_crossings[_key(a, b)] = true
	_crossing_list.append([points[a], points[b]])


static func _key(a: int, b: int) -> int:
	return mini(a, b) * 10000 + maxi(a, b)


func is_crossing(a: int, b: int) -> bool:
	return _crossings.has(_key(a, b))


func is_corner(id: int) -> bool:
	return id % 2 == 0


## Pairs of [kerb point, kerb point] for every crossing.
func crossing_segments() -> Array:
	return _crossing_list


func nearest_node(p: Vector3) -> int:
	return astar.get_closest_point(Vector3(p.x, 0.0, p.z))


func path(from: int, to: int) -> PackedInt64Array:
	return astar.get_id_path(from, to)


## Every walking (non-crossing) edge as [a, b] point pairs, for the debug view.
func walk_segments() -> Array:
	var result := []
	for id in points.size():
		for other: int in astar.get_point_connections(id):
			if other > id and not is_crossing(id, other):
				result.append([points[id], points[other]])
	return result


## True when `p` is on the pavement band of some block (including the strip
## where buildings stand; they block movement themselves).
static func on_pavement(p: Vector3, margin := 0.3) -> bool:
	return City.on_block(p, margin)
