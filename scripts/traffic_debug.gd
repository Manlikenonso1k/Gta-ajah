extends Node3D
## F6 debug view: lane centre lines (grey), pavement walking lines (cyan),
## crossings (yellow, with kerb points), each AI car's planned path (green for
## normal drivers, red for reckless ones) and held junctions (magenta).
## Drawn as unshaded lines on top of everything; the dynamic part refreshes 5×/s.

const City = preload("res://scripts/city.gd")
const RoadGraph = preload("res://scripts/road_graph.gd")
const PavementGraph = preload("res://scripts/pavement_graph.gd")

const LANE_COLOR := Color(0.75, 0.75, 0.8)
const PAVEMENT_COLOR := Color(0.2, 0.85, 1.0)
const CROSSING_COLOR := Color(1.0, 0.85, 0.1)
const NORMAL_COLOR := Color(0.2, 1.0, 0.3)
const RECKLESS_COLOR := Color(1.0, 0.15, 0.15)
const HOLD_COLOR := Color(1.0, 0.2, 1.0)
const Y := 0.15

var traffic: Node
var _dynamic := ImmediateMesh.new()
var _timer := 0.0


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.render_priority = 10
	var static_mesh := ImmediateMesh.new()
	static_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var graph: RefCounted = RoadGraph.shared()
	for lane: Dictionary in graph.lanes:
		var a: Vector3 = lane.origin + lane.dir * RoadGraph.JUNCTION_HALF
		var b: Vector3 = lane.origin + lane.dir * (float(lane.length) - RoadGraph.JUNCTION_HALF)
		_line(static_mesh, a, b, LANE_COLOR)
		# Arrow head shows the driving direction
		var tip := a.lerp(b, 0.5)
		_line(static_mesh, tip, tip - lane.dir * 1.5 + lane.right * 0.8, LANE_COLOR)
		_line(static_mesh, tip, tip - lane.dir * 1.5 - lane.right * 0.8, LANE_COLOR)
	for lane_id in graph.lanes.size():
		for next: int in graph.next_lanes(lane_id):
			var turn: PackedVector3Array = graph.turn_points(lane_id, next)
			for i in turn.size() - 1:
				_line(static_mesh, turn[i], turn[i + 1], LANE_COLOR.darkened(0.45))
	var pavement: RefCounted = PavementGraph.shared()
	for segment: Array in pavement.walk_segments():
		_line(static_mesh, segment[0], segment[1], PAVEMENT_COLOR)
	for segment: Array in pavement.crossing_segments():
		_line(static_mesh, segment[0], segment[1], CROSSING_COLOR)
		for end: Vector3 in segment:
			_cross(static_mesh, end, 0.8, CROSSING_COLOR)
	static_mesh.surface_end()
	var static_instance := MeshInstance3D.new()
	static_instance.mesh = static_mesh
	static_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(static_instance)
	var dynamic_instance := MeshInstance3D.new()
	dynamic_instance.mesh = _dynamic
	dynamic_instance.material_override = material
	dynamic_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dynamic_instance)
	refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.2:
		_timer = 0.0
		refresh()


func refresh() -> void:
	_dynamic.clear_surfaces()
	if traffic == null or traffic.drivers.is_empty():
		return
	_dynamic.surface_begin(Mesh.PRIMITIVE_LINES)
	for driver: RefCounted in traffic.drivers:
		var color := RECKLESS_COLOR if driver.reckless else NORMAL_COLOR
		var path: PackedVector3Array = driver.planned_path(45.0)
		var car_position: Vector3 = driver.car.global_position
		_line(_dynamic, car_position, path[0], color)
		for i in path.size() - 1:
			_line(_dynamic, path[i], path[i + 1], color)
		# A box around each car in its driver colour
		_square(_dynamic, car_position, 2.6, color)
		for mark: Dictionary in driver.marks:
			if mark.held:
				_square(_dynamic, traffic._graph.junctions[mark.junction], RoadGraph.JUNCTION_HALF - 0.3, HOLD_COLOR)
	_dynamic.surface_end()


static func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(a.x, Y, a.z))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3(b.x, Y, b.z))


static func _cross(mesh: ImmediateMesh, p: Vector3, size: float, color: Color) -> void:
	_line(mesh, p + Vector3(-size, 0, -size), p + Vector3(size, 0, size), color)
	_line(mesh, p + Vector3(-size, 0, size), p + Vector3(size, 0, -size), color)


static func _square(mesh: ImmediateMesh, p: Vector3, half: float, color: Color) -> void:
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	for i in 4:
		_line(mesh, p + corners[i], p + corners[(i + 1) % 4], color)
