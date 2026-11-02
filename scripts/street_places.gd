extends RefCounted
## Street life places (Task 5 Phase 2, docs/PLAN_street_life.md): the flyover
## with people living under it, the market (suya kiosk, stalls, supermarket)
## next to the start block and the medical point across the road from it.
##
##   StreetPlaces.build(main, city, chunks, rng, people_share)
##
## Models come from assets/models/buildings/ (blender/make_buildings.py) with
## the collision boxes listed in its manifest.json. The lots they stand on are
## kept empty by City.RESERVED_LOTS. People reuse pedestrian.gd with an
## anchor_state, so they look, animate and ragdoll like everyone else but
## don't navigate: they hold a pose or walk a short loop. `people_share`
## (0..1) keeps the most important people first for lower quality presets.

const City = preload("res://scripts/city.gd")
const Pedestrian = preload("res://scripts/pedestrian.gd")
const Registry = preload("res://scripts/pedestrian_registry.gd")
const Ragdoll = preload("res://scripts/ragdoll.gd")
const MANIFEST := "res://assets/models/buildings/manifest.json"
## Made-up names; no real brands
const SUPERMARKET_NAME := "GARDEN CITY MART"
const CLINIC_NAME := "HOPE MEDICAL POINT"
const SUYA_NAME := "MALLAM SUYA SPOT"
## The flyover crosses road 1 above the middle of block row 3
const FLYOVER_ROAD := 1
const FLYOVER_ROW := 3

static var _manifest: Dictionary


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		_manifest = parsed if parsed is Dictionary else {}
	return _manifest


## Builds every place. `chunks` maps Vector2i(i, j) to the block's chunk node;
## props go in the chunks so streaming hides them with the block.
static func build(main: Node3D, city: Node3D, chunks: Dictionary, rng: RandomNumberGenerator, people_share := 1.0) -> Array:
	var people := []   # [priority, Pedestrian]; lower priority numbers are kept first
	_under_bridge(city, chunks, people)
	_market(chunks[Vector2i(2, 1)], people)
	_clinic(chunks[Vector2i(3, 1)], people)
	people.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var keep := int(ceil(people.size() * clampf(people_share, 0.0, 1.0)))
	var added := []
	for n in keep:
		var spec: Dictionary = people[n][1]
		var ped = _person(spec, rng)
		main.add_child(ped)
		ped.add_to_group("pedestrians")
		ped.add_to_group("place_people")
		added.append(ped)
	return added


## Where online players appear: on the pavement in front of the medical
## point, between its stalls, facing the road. `slot` spreads players 1.2 m
## apart so they don't spawn inside each other.
static func clinic_spawn(slot := 0) -> Transform3D:
	var yaw := _facing(Vector3(-1, 0, 0))
	var clinic := City.block_center(3, 1) + Vector3(-City.LOT_OFFSET, 0, City.LOT_OFFSET - 2.0)
	var across := float(posmod(slot, 4)) * 1.2 - 1.8
	var spot := _at(clinic, Vector3(across, 0.2, 8.6), yaw)
	# The player walks towards -Z, the models' fronts are +Z
	return Transform3D(Basis(Vector3.UP, yaw + PI), spot.origin)


## A model from the manifest with its collision, placed by `xform`.
static func prop(parent: Node3D, name: String, xform: Transform3D) -> Node3D:
	var entry: Dictionary = manifest().get(name, {})
	var scene: PackedScene = load(entry.get("file", "")) if not entry.is_empty() else null
	if scene == null:
		push_warning("street places: missing model " + name)
		return null
	var node: Node3D
	var boxes: Array = entry.get("collision", [])
	if boxes.is_empty():
		node = Node3D.new()
	else:
		var body := StaticBody3D.new()
		for box: Dictionary in boxes:
			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(box.size[0], box.size[1], box.size[2])
			shape.shape = box_shape
			shape.position = Vector3(box.center[0], box.center[1], box.center[2])
			body.add_child(shape)
		node = body
	node.name = name.to_pascal_case()
	node.transform = xform
	node.add_child(scene.instantiate())
	parent.add_child(node)
	return node


static func _at(origin: Vector3, local: Vector3, yaw: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw)
	return Transform3D(basis, origin + basis * local)


## Turn that makes a model's front (+Z) face `direction` (x/z).
static func _facing(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


## Queues a person: `spec` = {pos, yaw, state, clips (overrides), loop,
## sex ("male"/"female"/""), bag}. Created later in priority order.
static func _queue(people: Array, priority: int, spec: Dictionary) -> void:
	people.append([priority, spec])


static func _person(spec: Dictionary, rng: RandomNumberGenerator) -> CharacterBody3D:
	var entry: Dictionary = {}
	var wanted: String = spec.get("sex", "")
	for attempt in 12:
		entry = Registry.choose(rng)
		if wanted == "" or entry.get("gender", "") == wanted:
			break
	var ped = Pedestrian.from_entry(entry, rng)
	ped.anchor_state = spec.get("state", "idle")
	ped.clip_overrides = spec.get("clips", {})
	ped.loop_path = spec.get("loop", [])
	ped.position = spec.pos
	ped.rotation.y = spec.get("yaw", 0.0)
	if spec.get("bag", false):
		ped.ready.connect(func() -> void: ped.set_carrying(true), CONNECT_ONE_SHOT)
	return ped


## Grey smoke rising from `pos` (CPUParticles3D works on the Compatibility
## renderer). `fire` adds small flames.
static func smoke(parent: Node3D, pos: Vector3, fire := false) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "Smoke"
	particles.position = pos
	particles.amount = 28
	particles.lifetime = 3.5
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.initial_velocity_min = 0.35
	particles.initial_velocity_max = 0.7
	particles.gravity = Vector3(0.15, 0.25, 0.0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.6))
	particles.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.3, 0.3, 0.3, 0.75))
	fade.set_color(1, Color(0.55, 0.55, 0.55, 0.0))
	particles.color_ramp = fade
	particles.mesh = _puff(Color.WHITE, 0.8)
	parent.add_child(particles)
	if fire:
		var flames := CPUParticles3D.new()
		flames.name = "Flames"
		flames.position = pos - Vector3(0, 0.1, 0)
		flames.amount = 10
		flames.lifetime = 0.5
		flames.direction = Vector3.UP
		flames.spread = 20.0
		flames.initial_velocity_min = 0.4
		flames.initial_velocity_max = 0.8
		flames.gravity = Vector3.ZERO
		var heat := Gradient.new()
		heat.set_color(0, Color(1.0, 0.75, 0.2, 0.9))
		heat.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
		flames.color_ramp = heat
		flames.mesh = _puff(Color.WHITE, 0.18)
		parent.add_child(flames)


static func _puff(color: Color, size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	quad.material = material
	return quad


static func sign_text(parent: Node3D, text: String, xform: Transform3D, color := Color(0.1, 0.1, 0.12), size := 64) -> void:
	var label := Label3D.new()
	label.name = "Sign"
	label.text = text
	label.font_size = size
	label.pixel_size = 0.01
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.transform = xform
	parent.add_child(label)


## The flyover across road 1 at row 3, and the people living beneath it on
## both sides: sleeping on mats and cardboard, sitting against the pillars,
## a fire, belongings, and a couple of people pacing about.
static func _under_bridge(city: Node3D, chunks: Dictionary, people: Array) -> void:
	var middle := Vector3(City.road_line(FLYOVER_ROAD), 0.0, City.block_center(0, FLYOVER_ROW).z)
	prop(city, "flyover", Transform3D(Basis.IDENTITY, middle))
	# East side (block 1): between the pillar row (x + 10) and the end wall (x + 16.25)
	var east: Node3D = chunks[Vector2i(FLYOVER_ROAD, FLYOVER_ROW)]
	var e := middle + Vector3(13.0, 0.0, 0.0)
	for item in [["mat", Vector3(0.0, 0, -3.2), 0.0], ["mat", Vector3(0.0, 0, -1.0), 0.0], ["cardboard", Vector3(0.2, 0, 1.6), 0.0],
			["sack", Vector3(2.2, 0, -3.8), 0.3], ["sack", Vector3(2.4, 0, 3.6), -0.4], ["bucket", Vector3(2.3, 0, -2.4), 0.0],
			["bucket", Vector3(2.5, 0, 2.6), 0.0], ["fire_pit", Vector3(1.6, 0, 0.3), 0.0]]:
		prop(east, item[0], _at(e, item[1], item[2]))
	smoke(east, e + Vector3(1.6, 0.25, 0.3), true)
	# Lying along their mats (hips at the middle)
	_queue(people, 1, {"pos": e + Vector3(0.0, 0, -3.2), "yaw": PI / 2, "state": "lie"})
	_queue(people, 4, {"pos": e + Vector3(0.0, 0, -1.0), "yaw": PI / 2, "state": "lie"})
	_queue(people, 7, {"pos": e + Vector3(0.2, 0, 1.6), "yaw": PI / 2, "state": "lie"})
	# Sitting on upturned crates with their backs to the pillar columns (pillar at e.x - 3)
	for z in [-3.0, 3.0]:
		_seated(east, people, 2 if z < 0 else 8, e + Vector3(-2.3, 0, z), _facing(Vector3.RIGHT))
	# Pacing along the open strip under the deck's edge, swaying while stopped
	_queue(people, 10, {"pos": e + Vector3(-1.2, 0, 4.4), "state": "idle", "clips": {"idle": "mx/Idle_Drunk"},
		"loop": [{"p": e + Vector3(-1.2, 0, 4.4), "wait": 3.0}, {"p": e + Vector3(1.8, 0, 4.4), "wait": 4.0}]})
	# West side (block 0): between the end wall (x - 16.25) and the pillar row (x - 10)
	var west: Node3D = chunks[Vector2i(FLYOVER_ROAD - 1, FLYOVER_ROW)]
	var w := middle - Vector3(13.0, 0.0, 0.0)
	for item in [["mat", Vector3(0.0, 0, -2.0), 0.0], ["cardboard", Vector3(0.0, 0, 1.8), 0.0], ["sack", Vector3(-2.3, 0, -3.5), 0.2],
			["bucket", Vector3(-2.2, 0, 3.4), 0.0], ["sack", Vector3(-2.4, 0, 0.0), 1.2]]:
		prop(west, item[0], _at(w, item[1], item[2]))
	_queue(people, 3, {"pos": w + Vector3(0.0, 0, -2.0), "yaw": -PI / 2, "state": "lie"})
	_seated(west, people, 9, w + Vector3(2.3, 0, 3.0), _facing(Vector3.LEFT))
	_queue(people, 11, {"pos": w + Vector3(-1.5, 0, 0.0), "state": "idle",
		"loop": [{"p": w + Vector3(-1.5, 0, -4.2), "wait": 5.0}, {"p": w + Vector3(-1.5, 0, 4.2), "wait": 2.0}]})


## Someone sitting on an upturned crate at `seat`, facing `yaw`: hips over
## the seat, feet ahead of it (the set has no clip for sitting on the ground).
static func _seated(parent: Node3D, people: Array, priority: int, seat: Vector3, yaw: float) -> void:
	prop(parent, "seat_crate", Transform3D(Basis(Vector3.UP, yaw), seat))
	_queue(people, priority, {"pos": seat + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.18), "yaw": yaw, "state": "sit",
		"clips": {"sit": "mx/Sit_Talk"}})


## Market lots of block (2, 1), facing the start block: the supermarket on
## the west lot, and on the east lot the suya kiosk with its customers,
## packed stalls under umbrellas, a kiosk booth and crates.
static func _market(chunk: Node3D, people: Array) -> void:
	var center := City.block_center(2, 1)
	var front := Vector3(0, 0, 1)   # towards the road the start block is across
	var yaw := _facing(front)
	var shop := center + Vector3(-City.LOT_OFFSET, 0, City.LOT_OFFSET)
	prop(chunk, "supermarket", _at(shop, Vector3.ZERO, yaw))
	sign_text(chunk, SUPERMARKET_NAME, _at(shop, Vector3(0, 4.4, 6.22), yaw), Color(0.75, 0.08, 0.06), 96)
	# Shoppers: out of the door with a bag, along the forecourt, back in later
	var door := shop + Vector3(0, 0, 6.3)
	for n in 2:
		var away := shop + Vector3(-4.5 + n * 9.0, 0, 7.6)
		_queue(people, 5 + n * 7, {"pos": door, "state": "idle", "loop": [
			{"p": door, "wait": 5.0 + n * 6.0, "hide": true, "bag": true},
			{"p": away, "wait": 4.0, "bag": false},
		]})

	var lot := center + Vector3(City.LOT_OFFSET, 0, City.LOT_OFFSET)
	var kiosk := lot + Vector3(-3.5, 0, 4.5)
	prop(chunk, "suya_kiosk", _at(kiosk, Vector3.ZERO, yaw))
	sign_text(chunk, SUYA_NAME, _at(kiosk, Vector3(0, 2.62, 1.21), yaw), Color(0.95, 0.85, 0.2), 40)
	smoke(chunk, kiosk + Vector3(0, 1.25, 0.75))
	# The seller turns the meat behind the grill; customers wait or eat standing
	_queue(people, 0, {"pos": kiosk + Vector3(0, 0, 0.25), "yaw": yaw, "state": "idle", "sex": "male", "clips": {"idle": "Idle_Talking"}})
	_queue(people, 6, {"pos": kiosk + Vector3(-0.7, 0, 2.0), "yaw": yaw + PI, "state": "idle"})
	_queue(people, 13, {"pos": kiosk + Vector3(0.6, 0, 2.3), "yaw": yaw + PI - 0.4, "state": "idle", "clips": {"idle": "Idle_Talking"}})
	_queue(people, 16, {"pos": kiosk + Vector3(1.5, 0, 1.6), "yaw": yaw + PI - 0.9, "state": "idle", "clips": {"idle": "mx/Idle_Phone"}})
	prop(chunk, "kiosk_booth", _at(lot, Vector3(-7.0, 0, 5.2), yaw))
	var stalls := [[0.2, 4.8], [3.0, 5.0], [5.8, 4.7], [-6.5, 1.5], [-3.5, 1.8], [-0.3, 1.4], [2.8, 1.7], [5.9, 1.4]]
	for n in stalls.size():
		var model := "market_stall_red" if n % 2 == 0 else "market_stall_blue"
		prop(chunk, model, _at(lot, Vector3(stalls[n][0], 0, stalls[n][1]), yaw + (n % 3 - 1) * 0.08))
	# Kept inside the lot so the pavement stays walkable
	for spot in [[6.2, -1.5, 0.2], [-7.4, -1.8, -0.3], [1.5, -2.3, 0.0], [6.0, 5.9, 0.6]]:
		prop(chunk, "crate_stack", _at(lot, Vector3(spot[0], 0, spot[1]), spot[2]))
	_queue(people, 14, {"pos": lot + Vector3(3.0, 0, 6.4), "yaw": yaw + PI, "state": "idle"})


## The medical point on block (3, 1), facing the market across road 3, with
## people waiting on a bench outside and stalls crowding its frontage.
static func _clinic(chunk: Node3D, people: Array) -> void:
	var center := City.block_center(3, 1)
	var front := Vector3(-1, 0, 0)
	var yaw := _facing(front)
	var lot := center + Vector3(-City.LOT_OFFSET, 0, City.LOT_OFFSET)
	var clinic := lot + Vector3(0, 0, -2.0)
	prop(chunk, "clinic", _at(clinic, Vector3.ZERO, yaw))
	sign_text(chunk, CLINIC_NAME, _at(clinic, Vector3(0.8, 3.4, 4.68), yaw), Color(0.05, 0.4, 0.15), 56)
	var bench := clinic + Basis(Vector3.UP, yaw) * Vector3(-2.6, 0, 5.5)
	prop(chunk, "bench", Transform3D(Basis(Vector3.UP, yaw), bench))
	# Sitters: hips over the seat, feet ahead of the bench
	for n in 3:
		var along := Basis(Vector3.UP, yaw) * Vector3(-0.75 + n * 0.75, 0, 0.18)
		_queue(people, [2, 8, 15][n], {"pos": bench + along, "yaw": yaw, "state": "sit"})
	_queue(people, 12, {"pos": clinic + Basis(Vector3.UP, yaw) * Vector3(2.4, 0, 5.6), "yaw": yaw + 0.5, "state": "idle"})
	for spot in [[-4.5, 6.2, 0.1], [4.6, 6.2, -0.1]]:
		var model := "market_stall_blue" if spot[0] < 0 else "market_stall_red"
		var place := _at(clinic, Vector3(spot[0], 0, spot[1]), yaw)
		prop(chunk, model, Transform3D(Basis(Vector3.UP, yaw + spot[2]), place.origin))
	prop(chunk, "kiosk_booth", _at(lot, Vector3(5.5, 0, 6.4), yaw))
	prop(chunk, "crate_stack", _at(lot, Vector3(-6.5, 0, 6.2), yaw))
