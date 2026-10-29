extends SceneTree
## Street-life places (scripts/street_places.gd) in the real game scene:
##   godot --headless --path . --script tests/street_places_test.gd
## Checks: every model in the manifest loads and is CC0; the flyover leaves the
## road below it clear and high enough for the coach; no solid part of a place
## stands on a road or in the pavement walking band; the place people exist,
## hold still or walk their loops without navigation, and lie or sit at the
## right height; shoppers go in and come out carrying a bag; the medical point
## sign is green, not red.

const City = preload("res://scripts/city.gd")
const StreetPlaces = preload("res://scripts/street_places.gd")
const SkeletonMap = preload("res://scripts/skeleton_map.gd")
const Quality = preload("res://scripts/quality.gd")
## People the places queue (street_places.gd); presets keep a share of them
const PLACE_PEOPLE := 20
## Walkers keep to a ring this far from each block's centre (pavement_graph.gd), +- 1.5 m
const RING := City.BLOCK / 2.0 - City.PAVEMENT_INSET
const BAND := 1.5
const COACH_HEIGHT := 3.6

var _failures := 0


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	_run.call_deferred()


func _fail(message: String) -> void:
	print("FAIL " + message)
	_failures += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var manifest := StreetPlaces.manifest()
	for name: String in manifest:
		var entry: Dictionary = manifest[name]
		if not ResourceLoader.exists(entry.file) or not load(entry.file) is PackedScene:
			_fail("model %s doesn't load" % name)
		if entry.get("license", "") != "CC0":
			_fail("model %s licence %s" % [name, entry.get("license", "?")])
	print("models: %d in the manifest" % manifest.size())

	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	var player: Node3D = main.get("_player")

	# Flyover: clear road underneath, deck above coach height
	var bridge := Vector3(City.road_line(StreetPlaces.FLYOVER_ROAD), 0, City.block_center(0, StreetPlaces.FLYOVER_ROW).z)
	player.global_position = bridge + Vector3(0, 0.2, 20)
	main.call("_update_streaming")
	await _frames(5)
	var space := main.get_world_3d().direct_space_state
	for lane_x in [-3.0, 0.0, 3.0]:
		for dz in [-4.0, 0.0, 4.0]:
			var top := bridge + Vector3(lane_x, 30.0, dz)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top - Vector3(0, 40, 0), 1))
			var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(top - Vector3(0, 30.0 - COACH_HEIGHT, 0), top - Vector3(0, 40, 0), 1))
			if hit.is_empty() or (hit.position as Vector3).y < 6.5:
				_fail("no flyover deck above the road at %s" % (top - Vector3(0, 30, 0)))
			if not under.is_empty() and (under.position as Vector3).y > 0.05:
				_fail("something on the road under the flyover at %s (%.2f m)" % [under.position, under.position.y])
	print("flyover: deck over the road, %.1f m clear below" % COACH_HEIGHT)

	# Solid parts of the places stay off roads and out of the walking band
	var parts := 0
	for body: StaticBody3D in main.find_children("*", "StaticBody3D", true, false):
		if not _is_place(body):
			continue
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", false, false):
			var box := shape.shape as BoxShape3D
			var xform := shape.global_transform
			# The deck and the beams under it are allowed over the road
			if box == null or xform.origin.y - box.size.y / 2.0 > COACH_HEIGHT:
				continue
			parts += 1
			for corner in [Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3.ZERO]:
				var p: Vector3 = xform * (corner * box.size / 2.0)
				if not City.on_block(p):
					_fail("%s/%s stands on the road at %s" % [body.name, shape.name, p.snapped(Vector3.ONE * 0.1)])
				elif _in_band(p):
					_fail("%s/%s is in the pavement walking band at %s" % [body.name, shape.name, p.snapped(Vector3.ONE * 0.1)])
	print("solid place parts checked: %d" % parts)

	# People at the places
	var people := get_nodes_in_group("place_people")
	var expected := ceili(PLACE_PEOPLE * float(Quality.current().get("pedestrians", 30)) / 30.0)
	if people.size() < expected:
		_fail("only %d place people (expected %d)" % [people.size(), expected])
	var lying := 0
	var sitting := 0
	var loops := 0
	for ped in people:
		if ped.navigation != null:
			_fail("%s at a place has pavement navigation" % ped.character_id)
		if not ped.loop_path.is_empty():
			loops += 1
	# Bring each place's people into full detail and let them settle
	for spot in [bridge + Vector3(13, 0, 6), bridge - Vector3(13, 0, -6), City.block_center(2, 1) + Vector3(0, 0, 14), City.block_center(3, 1) + Vector3(-14, 0, 8)]:
		player.global_position = spot + Vector3(0, 0.2, 0)
		main.call("_update_streaming")
		await _frames(40)
		for ped in people:
			if ped.global_position.distance_to(spot) > 25.0 or not ped.loop_path.is_empty():
				continue
			var hips := _hips_height(ped)
			if ped.anchor_state == "lie":
				lying += 1
				if hips > 0.4:
					_fail("%s lying with hips %.2f m up" % [ped.character_id, hips])
			elif ped.anchor_state == "sit":
				sitting += 1
				if hips < 0.35 or hips > 0.8:
					_fail("%s sitting with hips %.2f m up" % [ped.character_id, hips])
	print("place people: %d (%d lying, %d sitting, %d on loops)" % [people.size(), lying, sitting, loops])
	if lying < 2 or sitting < 3:
		_fail("too few people lying (%d) or sitting (%d)" % [lying, sitting])

	# Shoppers: hidden inside, then out of the door with a bag
	player.global_position = City.block_center(2, 1) + Vector3(-9.5, 0.2, 16)
	main.call("_update_streaming")
	var shoppers := people.filter(func(p) -> bool: return p.loop_path.size() == 2 and p.loop_path[0].get("hide", false))
	var went_in := false
	var came_out_with_bag := false
	for frame in 60 * 25:
		await physics_frame
		for s in shoppers:
			if not s.visible:
				went_in = true
			elif went_in and s._bag != null and s._bag.visible:
				came_out_with_bag = true
		if came_out_with_bag:
			break
	print("shoppers: %d, went in %s, came out with a bag %s" % [shoppers.size(), went_in, came_out_with_bag])
	if shoppers.is_empty() or not went_in or not came_out_with_bag:
		_fail("shoppers don't go in and come out with a bag")

	# Signs: made-up names; the medical point uses green
	var labels := main.find_children("*", "Label3D", true, false)
	var texts := labels.map(func(l: Label3D) -> String: return l.text)
	for name in [StreetPlaces.SUPERMARKET_NAME, StreetPlaces.CLINIC_NAME, StreetPlaces.SUYA_NAME]:
		if not texts.has(name):
			_fail("sign %s missing" % name)
	for label: Label3D in labels:
		if label.text == StreetPlaces.CLINIC_NAME and not (label.modulate.g > label.modulate.r * 2.0):
			_fail("medical point sign isn't green")

	print("street places test: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _is_place(body: Node) -> bool:
	var names := StreetPlaces.manifest().keys().map(func(n: String) -> String: return n.to_pascal_case())
	return names.has(String(body.name))


## Inside a block's pavement walking band (the ring walkers follow, +- BAND).
func _in_band(p: Vector3) -> bool:
	var i := roundi(p.x / City.PITCH + (City.GRID - 1) / 2.0)
	var j := roundi(p.z / City.PITCH + (City.GRID - 1) / 2.0)
	var c := City.block_center(i, j)
	var dx := absf(p.x - c.x)
	var dz := absf(p.z - c.z)
	return (absf(dx - RING) < BAND and dz < RING + BAND) or (absf(dz - RING) < BAND and dx < RING + BAND)


func _hips_height(ped: Node3D) -> float:
	var model: Node3D = ped.get("_model")
	var skeleton := SkeletonMap.skeleton_of(model) if model != null else null
	if skeleton == null:
		return -1.0
	var hips := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	return hips.y - ped.global_position.y
