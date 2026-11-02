extends RefCounted
## Procedural placeholder city: a grid of blocks, roads, buildings and palm
## trees. Swap pieces for Blender models in assets/models/ as they're made.

const Ragdoll = preload("res://scripts/ragdoll.gd")
const BUILDING_SHADER = preload("res://shaders/building.gdshader")
const ASPHALT_SHADER = preload("res://shaders/asphalt.gdshader")
const PAVEMENT_SHADER = preload("res://shaders/pavement.gdshader")
const LATERITE_SHADER = preload("res://shaders/laterite.gdshader")

const BLOCK := 40.0
const ROAD := 12.0
const GRID := 5
const PITCH := BLOCK + ROAD
const HALF := GRID / 2.0 * PITCH + ROAD / 2.0
## Traffic drives on the right. Each 12 m road holds two 3.6 m lanes (centres
## LANE_OFFSET from the road centre line) plus a 2.4 m kerbside parking strip
## on the east side of the inner north-south roads.
const LANE_OFFSET := 1.8
const LANE_WIDTH := 3.6
const PARK_OFFSET := ROAD / 2.0 - 1.2
## The pavement is the 3 m band between the block edge and the buildings
## (buildings reach at most 17.05 m from a block centre). Pedestrians walk on
## the line PAVEMENT_INSET inside the block edge.
const PAVEMENT_WIDTH := 2.9
const PAVEMENT_INSET := 1.5

## Building lots kept empty for scripts/street_places.gd, by block (i, j):
## lot offsets (lx, lz), each -1 or 1. The flyover spans road 1 at row 3;
## the market and supermarket face the start block; the clinic faces them
## across road 3.
const RESERVED_LOTS := {
	Vector2i(0, 3): [Vector2i(1, -1), Vector2i(1, 1)],
	Vector2i(1, 3): [Vector2i(-1, -1), Vector2i(-1, 1)],
	Vector2i(2, 1): [Vector2i(-1, 1), Vector2i(1, 1)],
	Vector2i(3, 1): [Vector2i(-1, 1)],
}
## Lot centres sit this far from their block's centre on each axis
const LOT_OFFSET := 9.5

const BUILDING_COLORS := [
	Color(0.92, 0.88, 0.78), Color(0.78, 0.45, 0.32), Color(0.65, 0.75, 0.82),
	Color(0.85, 0.72, 0.45), Color(0.9, 0.9, 0.88), Color(0.6, 0.68, 0.55),
]


## Centre line of road `k` (0..GRID), along either axis.
static func road_line(k: int) -> float:
	return (k - GRID / 2.0) * PITCH


static func block_center(i: int, j: int) -> Vector3:
	return Vector3((i - (GRID - 1) / 2.0) * PITCH, 0, (j - (GRID - 1) / 2.0) * PITCH)


## Builds the city under `parent` and returns spawn points:
## {"sidewalk": [Vector3], "parking": [Transform3D]}
static func build(parent: Node3D, rng: RandomNumberGenerator) -> Dictionary:
	var city := Node3D.new()
	city.name = "City"
	parent.add_child(city)

	# Ground: red laterite earth outside, asphalt within the city
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(1000, 2, 1000)
	ground_shape.shape = ground_box
	ground_shape.position.y = -1
	ground.add_child(ground_shape)
	city.add_child(ground)
	_plane(city, Vector2(1000, 1000), 0.0, Color(0.55, 0.32, 0.2), _shader_material(LATERITE_SHADER))
	_plane(city, Vector2(HALF * 2, HALF * 2), 0.01, Color(0.18, 0.18, 0.19), _shader_material(ASPHALT_SHADER, {"road_pitch": PITCH, "lane_offset": LANE_OFFSET}))

	for k in GRID + 1:
		_box(city, Vector3(0.2, 0.02, HALF * 2), Vector3(road_line(k), 0.02, 0), Color(0.9, 0.75, 0.2), false)
		_box(city, Vector3(HALF * 2, 0.02, 0.2), Vector3(0, 0.02, road_line(k)), Color(0.9, 0.75, 0.2), false)

	var spawns := {"sidewalk": [], "parking": [], "chunks": []}
	for i in GRID:
		for j in GRID:
			var c := block_center(i, j)
			var chunk := Node3D.new()
			chunk.name = "Block_%d_%d" % [i, j]
			chunk.set_meta("stream_center", c)
			city.add_child(chunk)
			spawns["chunks"].append(chunk)
			_box(chunk, Vector3(BLOCK, 0.1, BLOCK), c + Vector3(0, 0.05, 0), Color(0.62, 0.6, 0.56), false, _shader_material(PAVEMENT_SHADER, {"block_half": BLOCK / 2.0}))
			for lx in [-1, 1]:
				for lz in [-1, 1]:
					var lot := c + Vector3(lx * LOT_OFFSET, 0, lz * LOT_OFFSET)
					var reserved: bool = RESERVED_LOTS.get(Vector2i(i, j), []).has(Vector2i(lx, lz))
					if rng.randf() < 0.8:
						if reserved:
							# Draw what _building would, so the rest of the city is unchanged
							for n in 3:
								rng.randf()
							rng.randi()
						else:
							_building(chunk, lot, rng)
					elif reserved:
						rng.randf()
					else:
						_palm(chunk, lot, rng)
			for n in 6:
				var along := rng.randf_range(-BLOCK / 2 + 2, BLOCK / 2 - 2)
				var edge := (BLOCK / 2 - 1.2) * (1 if rng.randf() < 0.5 else -1)
				var p := Vector3(along, 0, edge) if n % 2 == 0 else Vector3(edge, 0, along)
				if n < 2:
					_palm(chunk, c + p * 1.02, rng)
				else:
					spawns["sidewalk"].append(c + p + Vector3(0, 0.2, 0))

	# Parked cars along the kerb, alternating road direction. Each road has one
	# slot per block, so a 12 m bus fits; the middle block is kept clear for
	# the player's car.
	for k in range(1, GRID):
		var slots := [0, 1, 3, 4]
		for i in range(slots.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap = slots[i]
			slots[i] = slots[j]
			slots[j] = swap
		for n in 3:
			var z := block_center(0, slots[n]).z + rng.randf_range(-8, 8)
			# Against the east kerb, facing -Z like the southbound traffic beside it
			var pos := Vector3(road_line(k) + PARK_OFFSET, 0.6, z)
			spawns["parking"].append(Transform3D(Basis(Vector3.UP, PI), pos))
	_zebra_crossings(city)
	return spawns


## True when `p` is on a city block (pavement or building lot), with `margin`
## metres added around each block. Roads are everything else.
static func on_block(p: Vector3, margin := 0.0) -> bool:
	var limit := BLOCK / 2.0 + margin
	for axis_value: float in [p.x, p.z]:
		var cell := roundf(axis_value / PITCH + (GRID - 1) / 2.0)
		if cell < 0 or cell > GRID - 1:
			return false
		if absf(axis_value - (cell - (GRID - 1) / 2.0) * PITCH) > limit:
			return false
	return true


## Zebra stripes for every pavement crossing (one MultiMesh, one draw call).
static func _zebra_crossings(city: Node3D) -> void:
	var PavementGraph: GDScript = load("res://scripts/pavement_graph.gd")
	var crossings: Array = PavementGraph.shared().crossing_segments()
	var stripe := BoxMesh.new()
	stripe.size = Vector3(2.4, 0.02, 0.5)
	var transforms: Array[Transform3D] = []
	for segment: Array in crossings:
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var direction := (b - a).normalized()
		var stripe_basis := Basis(Vector3.UP, atan2(direction.x, direction.z))
		var length := a.distance_to(b)
		var d := 0.6
		while d < length - 0.4:
			var p := a + direction * d
			if not on_block(p, 0.1):
				transforms.append(Transform3D(stripe_basis, Vector3(p.x, 0.025, p.z)))
			d += 1.0
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = stripe
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "ZebraCrossings"
	instance.multimesh = multimesh
	instance.material_override = Ragdoll.material(Color(0.92, 0.92, 0.88))
	city.add_child(instance)


static func set_chunk_active(chunk: Node3D, active: bool) -> void:
	if chunk.visible == active:
		return
	chunk.visible = active
	var pending: Array[Node] = [chunk]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D:
			if not node.has_meta("stream_collision_layer"):
				node.set_meta("stream_collision_layer", node.collision_layer)
			node.collision_layer = int(node.get_meta("stream_collision_layer")) if active else 0
		for child in node.get_children():
			pending.append(child)


static var _shader_materials := {}


## One shared material per shader and parameter set (shaders/*.gdshader).
static func _shader_material(shader: Shader, params := {}) -> ShaderMaterial:
	var key := [shader.resource_path, params]
	if not _shader_materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = shader
		for name: String in params:
			mat.set_shader_parameter(name, params[name])
		_shader_materials[key] = mat
	return _shader_materials[key]


static func _plane(parent: Node3D, size: Vector2, y: float, color: Color, material: Material = null) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = material if material != null else Ragdoll.material(color)
	mesh.position.y = y
	parent.add_child(mesh)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, collide := true, material: Material = null) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material if material != null else Ragdoll.material(color)
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		body.add_child(mesh)
		parent.add_child(body)
	else:
		mesh.position = pos
		parent.add_child(mesh)


static func _building(parent: Node3D, lot: Vector3, rng: RandomNumberGenerator) -> void:
	var size := Vector3(rng.randf_range(10, 15), rng.randf_range(6, 28), rng.randf_range(10, 15))
	var color: Color = BUILDING_COLORS[rng.randi() % BUILDING_COLORS.size()]
	# Windows, shops, signs and weathering come from shaders/building.gdshader
	_box(parent, size, lot + Vector3(0, size.y / 2, 0), color, true, _shader_material(BUILDING_SHADER, {"wall_color": color}))
	_roof_details(parent, lot, size)


## Black plastic water tanks and a stair housing on the roof, as on most
## Port Harcourt buildings. Placed from a hash of the lot so the city's random
## numbers (and so every other placement) stay the same.
static func _roof_details(parent: Node3D, lot: Vector3, size: Vector3) -> void:
	var h := absi(hash(Vector2i(roundi(lot.x), roundi(lot.z))))
	var top := lot.y + size.y
	var tanks := 1 + h % 3
	for n in tanks:
		var tank := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.75
		cylinder.bottom_radius = 0.8
		cylinder.height = 1.6
		cylinder.radial_segments = 12
		cylinder.rings = 1
		tank.mesh = cylinder
		tank.material_override = Ragdoll.material(Color(0.07, 0.07, 0.08))
		var side := -1.0 if (h >> (n + 2)) % 2 == 0 else 1.0
		tank.position = lot + Vector3(size.x * 0.3 * side, size.y + 0.8, size.z * (0.32 - n * 0.22))
		parent.add_child(tank)
	if size.y > 9.0:
		_box(parent, Vector3(3.0, 2.4, 3.2), Vector3(lot.x - size.x * 0.15, top + 1.2, lot.z + size.z * 0.1 * (1 if h % 2 == 0 else -1)), Color(0.72, 0.7, 0.66), false)


static func _palm(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(5, 8)
	var tree := StaticBody3D.new()
	tree.position = pos
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.2
	cylinder.height = height
	shape.shape = cylinder
	shape.position.y = height / 2
	tree.add_child(shape)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = height
	trunk.mesh = trunk_mesh
	trunk.material_override = Ragdoll.material(Color(0.45, 0.35, 0.25))
	trunk.position.y = height / 2
	tree.add_child(trunk)

	for n in 7:
		var frond := MeshInstance3D.new()
		var leaf := BoxMesh.new()
		leaf.size = Vector3(0.5, 0.05, 2.6)
		frond.mesh = leaf
		frond.material_override = Ragdoll.material(Color(0.2, 0.45, 0.15))
		frond.rotation = Vector3(-0.35, n * TAU / 7, 0)
		frond.position = Vector3(0, height, 0) + Vector3(0, 0, 1.2).rotated(Vector3.UP, n * TAU / 7)
		tree.add_child(frond)
	parent.add_child(tree)
