extends RefCounted
## Procedural placeholder city: a grid of blocks, roads, buildings and palm
## trees. Swap pieces for Blender models in assets/models/ as they're made.

const Ragdoll = preload("res://scripts/ragdoll.gd")

const BLOCK := 40.0
const ROAD := 12.0
const GRID := 5
const PITCH := BLOCK + ROAD
const HALF := GRID / 2.0 * PITCH + ROAD / 2.0

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
	_plane(city, Vector2(1000, 1000), 0.0, Color(0.55, 0.32, 0.2))
	_plane(city, Vector2(HALF * 2, HALF * 2), 0.01, Color(0.18, 0.18, 0.19))

	for k in GRID + 1:
		_box(city, Vector3(0.2, 0.02, HALF * 2), Vector3(road_line(k), 0.02, 0), Color(0.9, 0.75, 0.2), false)
		_box(city, Vector3(HALF * 2, 0.02, 0.2), Vector3(0, 0.02, road_line(k)), Color(0.9, 0.75, 0.2), false)

	var spawns := {"sidewalk": [], "parking": []}
	for i in GRID:
		for j in GRID:
			var c := block_center(i, j)
			_box(city, Vector3(BLOCK, 0.1, BLOCK), c + Vector3(0, 0.05, 0), Color(0.62, 0.6, 0.56), false)
			for lx in [-1, 1]:
				for lz in [-1, 1]:
					var lot := c + Vector3(lx * 9.5, 0, lz * 9.5)
					if rng.randf() < 0.8:
						_building(city, lot, rng)
					else:
						_palm(city, lot, rng)
			for n in 6:
				var along := rng.randf_range(-BLOCK / 2 + 2, BLOCK / 2 - 2)
				var edge := (BLOCK / 2 - 1.2) * (1 if rng.randf() < 0.5 else -1)
				var p := Vector3(along, 0, edge) if n % 2 == 0 else Vector3(edge, 0, along)
				if n < 2:
					_palm(city, c + p * 1.02, rng)
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
			var pos := Vector3(road_line(k) + ROAD / 2 - 1.6, 0.6, z)
			spawns["parking"].append(Transform3D(Basis(Vector3.UP, PI if n == 0 else 0.0), pos))
	return spawns


static func _plane(parent: Node3D, size: Vector2, y: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.material_override = Ragdoll.material(color)
	mesh.position.y = y
	parent.add_child(mesh)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, collide := true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = Ragdoll.material(color)
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
	_box(parent, size, lot + Vector3(0, size.y / 2, 0), color)
	# Dark window bands, one per floor
	var floor_y := 2.0
	while floor_y < size.y - 1.0:
		_box(parent, Vector3(size.x + 0.1, 1.1, size.z + 0.1), lot + Vector3(0, floor_y, 0), Color(0.12, 0.16, 0.2), false)
		floor_y += 3.2


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
