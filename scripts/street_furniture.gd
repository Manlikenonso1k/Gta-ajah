extends RefCounted
## Street lights and electric poles along the kerbs of every block, built by
## city.gd. Each road gets lamp posts on one side (the blocks' north and east
## edges) and wooden electric poles with sagging wires on the other (south
## and west edges).
##
## Everything in a block is merged into ONE mesh (a surface per material) and
## the poles share ONE static body, so a block adds one draw call per material
## and streaming (City.set_chunk_active) hides and disables it with the block.

## Lamp posts per edge, measured along the edge from its middle
const LAMP_SPOTS := [-14.0, -2.0, 10.0]
const POLE_SPOTS := [-17.0, -5.667, 5.667, 17.0]
## Distance in from the block edge (the kerb is the outer 0.3 m)
const INSET := 0.5
const LAMP_HEIGHT := 7.0
const POLE_HEIGHT := 8.6
## Wire attachment points on a pole's crossarm, across the edge
const WIRE_OFFSETS := [-0.8, 0.0, 0.8]
const WIRE_SAG := 0.55
const WIRE_SEGMENTS := 6

static var _materials := {}


## `skip_edges` lists edge directions (Vector2i(±1, 0) / Vector2i(0, ±1)) to
## leave empty, e.g. under the flyover deck.
static func build(chunk: Node3D, center: Vector3, half: float, skip_edges: Array = []) -> void:
	var tools := {
		"metal": _tool(), "pole": _tool(), "wire": _tool(), "lamp": _tool(),
	}
	var body := StaticBody3D.new()
	body.name = "StreetFurniture"
	# North (-z) and east (+x) edges: lamps; south (+z) and west (-x): poles
	for edge: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if skip_edges.has(edge):
			continue
		var outward := Vector3(edge.x, 0, edge.y)
		var along := Vector3(-outward.z, 0, outward.x)
		var edge_mid := center + outward * (half - INSET)
		var lamps := edge == Vector2i(0, -1) or edge == Vector2i(1, 0)
		if lamps:
			for spot: float in LAMP_SPOTS:
				_lamp(tools, body, edge_mid + along * spot, outward)
		else:
			var tops: Array = []
			for spot: float in POLE_SPOTS:
				tops.append(_pole(tools, body, edge_mid + along * spot, along))
			for n in tops.size() - 1:
				for wire in WIRE_OFFSETS.size():
					_wire(tools["wire"], tops[n][wire], tops[n + 1][wire])
	var mesh := ArrayMesh.new()
	for key: String in tools:
		var st: SurfaceTool = tools[key]
		if st.get_meta("used", false):
			st.generate_normals()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key))
	var instance := MeshInstance3D.new()
	instance.name = "StreetFurnitureMesh"
	instance.mesh = mesh
	chunk.add_child(instance)
	body.collision_layer = 1
	body.collision_mask = 0
	chunk.add_child(body)


## A lamp post: pole, an arm reaching over the road and the lamp head.
static func _lamp(tools: Dictionary, body: StaticBody3D, base: Vector3, outward: Vector3) -> void:
	var yaw := atan2(outward.x, outward.z)
	var basis := Basis(Vector3.UP, yaw)
	_cylinder(tools["metal"], base + Vector3(0, LAMP_HEIGHT / 2.0, 0), 0.07, 0.11, LAMP_HEIGHT, 8)
	_cylinder(tools["metal"], base + Vector3(0, 0.3, 0), 0.16, 0.16, 0.6, 8)
	_box(tools["metal"], Transform3D(basis, base + Vector3(0, LAMP_HEIGHT - 0.1, 0) + outward * 0.85), Vector3(0.08, 0.08, 1.7))
	_box(tools["metal"], Transform3D(basis, base + Vector3(0, LAMP_HEIGHT - 0.12, 0) + outward * 1.75), Vector3(0.32, 0.14, 0.6))
	_box(tools["lamp"], Transform3D(basis, base + Vector3(0, LAMP_HEIGHT - 0.2, 0) + outward * 1.75), Vector3(0.26, 0.03, 0.5))
	_collider(body, base, 0.12, LAMP_HEIGHT)


## A wooden electric pole with a crossarm and insulators. Returns the wire
## attachment points.
static func _pole(tools: Dictionary, body: StaticBody3D, base: Vector3, along: Vector3) -> Array:
	var across := Vector3(-along.z, 0, along.x)
	_cylinder(tools["pole"], base + Vector3(0, POLE_HEIGHT / 2.0, 0), 0.11, 0.15, POLE_HEIGHT, 7)
	var arm_y := POLE_HEIGHT - 0.45
	var basis := Basis(Vector3.UP, atan2(across.x, across.z))
	_box(tools["pole"], Transform3D(basis, base + Vector3(0, arm_y, 0)), Vector3(0.12, 0.12, 2.0))
	var points := []
	for offset: float in WIRE_OFFSETS:
		var p := base + Vector3(0, arm_y, 0) + across * offset
		_cylinder(tools["metal"], p + Vector3(0, 0.13, 0), 0.035, 0.05, 0.16, 6)
		points.append(p + Vector3(0, 0.2, 0))
	# A transformer drum on every other pole
	if absi(hash(Vector2i(roundi(base.x), roundi(base.z)))) % 2 == 0:
		_cylinder(tools["metal"], base + Vector3(0, POLE_HEIGHT - 1.7, 0) + along * 0.0 + across * -0.32, 0.25, 0.25, 0.75, 8)
	_collider(body, base, 0.15, POLE_HEIGHT)
	return points


## A sagging wire from `a` to `b`, as thin boxes along a parabola.
static func _wire(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var previous := a
	for i in range(1, WIRE_SEGMENTS + 1):
		var t := float(i) / WIRE_SEGMENTS
		var p := a.lerp(b, t) + Vector3.DOWN * WIRE_SAG * 4.0 * t * (1.0 - t)
		var mid := (previous + p) / 2.0
		var dir := p - previous
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
		_box(st, Transform3D(basis, mid), Vector3(0.025, 0.025, dir.length()))
		previous = p


static func _collider(body: StaticBody3D, base: Vector3, radius: float, height: float) -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position = base + Vector3(0, height / 2.0, 0)
	body.add_child(shape)


static func _tool() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _box(st: SurfaceTool, xform: Transform3D, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box, 0, xform)
	st.set_meta("used", true)


static func _cylinder(st: SurfaceTool, pos: Vector3, top: float, bottom: float, height: float, sides: int) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = sides
	cylinder.rings = 1
	st.append_from(cylinder, 0, Transform3D(Basis.IDENTITY, pos))
	st.set_meta("used", true)


static func _material(key: String) -> Material:
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		match key:
			"metal":
				mat.albedo_color = Color(0.42, 0.44, 0.46)
				mat.metallic = 0.5
				mat.roughness = 0.5
			"pole":
				mat.albedo_color = Color(0.36, 0.28, 0.2)
				mat.roughness = 0.95
			"wire":
				mat.albedo_color = Color(0.05, 0.05, 0.05)
				mat.roughness = 0.6
			"lamp":
				mat.albedo_color = Color(1.0, 0.95, 0.8)
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.88, 0.6)
				mat.emission_energy_multiplier = 0.6
		_materials[key] = mat
	return _materials[key]
