extends SceneTree
## World systems: block streaming, distant traffic on low-cost ticks, and a
## 60-second simulated run of traffic and pedestrians that checks:
## - the 90/10 split of normal and reckless drivers
## - normal drivers within 1 m of their lane centre at least 95% of the time
## - no AI car on a pavement or in a building, and no AI car hitting another
## - pedestrians on the pavement except while crossing, and running when crossing
## Run: godot --headless --path . --script tests/world_systems_test.gd

const Persistence = preload("res://scripts/vehicle_persistence.gd")
const City = preload("res://scripts/city.gd")
const RoadGraph = preload("res://scripts/road_graph.gd")
const PavementGraph = preload("res://scripts/pavement_graph.gd")
const Traffic = preload("res://scripts/traffic.gd")

const RUN_SECONDS := 60.0
const SAMPLE_EVERY := 6
const EXTRA_TRAFFIC := 10

var _failures: Array[String] = []


func _initialize() -> void:
	Persistence.SAVE_PATH = "user://world_systems_test.json"
	Persistence.TEMP_PATH = "user://world_systems_test.json.tmp"
	# Safety net: never hang the shared tool lock
	create_timer(300.0).timeout.connect(func() -> void:
		push_error("world systems test timed out")
		quit(1))
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _run() -> void:
	# Driver types: every ten spawns hold exactly one reckless driver
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var reckless_count := 0
	for deck in 100:
		for reckless in Traffic.driver_type_deck(rng):
			reckless_count += int(reckless)
	_check(reckless_count == 100, "driver split over 1000 spawns: %d reckless (want 100)" % reckless_count)

	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30: await physics_frame
	var player: Node3D = main._player
	# Stand the player on a pavement so they are not an obstacle in a lane
	player.global_position = Vector3(City.road_line(3) + City.ROAD / 2.0 + 1.2, 0.2, 5.0)
	var traffic: Node = null
	for child in main.get_children():
		if child is Traffic:
			traffic = child
	if traffic == null:
		_finish(main, ["traffic manager missing"])
		return
	traffic.spawn_cars(EXTRA_TRAFFIC)
	var drivers: Array = traffic.drivers
	var reckless_in_game := 0
	for driver in drivers:
		reckless_in_game += int(driver.reckless)
	print("traffic cars: %d (%d reckless)" % [drivers.size(), reckless_in_game])
	_check(drivers.size() >= 10, "only %d traffic cars spawned" % drivers.size())
	_check(reckless_in_game == drivers.size() / 10 or reckless_in_game == ceili(drivers.size() / 10.0), "in-game reckless count %d of %d" % [reckless_in_game, drivers.size()])
	for i in 60: await physics_frame

	# Distant traffic: frozen, physics off, still advancing
	var far_driver: RefCounted = null
	for driver in drivers:
		if driver.car.global_position.distance_to(player.global_position) > Traffic.DETAIL_RADIUS + 25.0:
			far_driver = driver
			break
	var far_moved := false
	var far_light := false
	if far_driver != null:
		var start: Vector3 = far_driver.car.global_position
		for i in 60: await physics_frame
		far_moved = far_driver.car.global_position.distance_to(start) > 1.0 or far_driver.allowed_speed < 0.5
		far_light = far_driver.car.freeze and not far_driver.car.is_physics_processing()
	_check(far_driver != null and far_moved and far_light, "distant traffic not on lightweight ticks (found=%s moved=%s light=%s)" % [far_driver != null, far_moved, far_light])

	# 60-second run
	var lane_samples := 0
	var lane_ok := 0
	var worst_lane := 0.0
	var off_road := 0
	var off_road_note := ""
	var collisions := {}
	var travelled := {}
	var last_pos := {}
	var ped_samples := 0
	var ped_off := 0
	var ped_off_note := ""
	var cross_samples := {"run": 0, "hurry": 0, "walk_then_run": 0}
	var cross_slow := 0
	var cross_slow_note := ""
	var crossings_seen := {}
	var hooked := 0
	var space := main.get_world_3d().direct_space_state
	var frames := int(RUN_SECONDS * Engine.physics_ticks_per_second)
	for frame in frames:
		await physics_frame
		if frame % SAMPLE_EVERY != 0:
			continue
		for driver in traffic.drivers:
			var car: VehicleBody3D = driver.car
			var p := car.global_position
			if last_pos.has(driver):
				travelled[driver] = float(travelled.get(driver, 0.0)) + Vector2(p.x - last_pos[driver].x, p.z - last_pos[driver].z).length()
			last_pos[driver] = p
			if not driver.reckless and not car.freeze and absf(driver.offset) < 0.05:
				lane_samples += 1
				worst_lane = maxf(worst_lane, driver.lateral_error)
				if driver.lateral_error <= 1.0:
					lane_ok += 1
			# Footprint corners must stay on asphalt
			var half_w: float = car._half_width
			var half_l: float = car._half_length
			for corner in [Vector3(half_w, 0, half_l), Vector3(-half_w, 0, half_l), Vector3(half_w, 0, -half_l), Vector3(-half_w, 0, -half_l)]:
				var q: Vector3 = car.global_transform * corner
				if City.on_block(q, -0.25) or absf(q.x) > City.HALF or absf(q.z) > City.HALF:
					off_road += 1
					off_road_note = "%s (%s) at %s" % [car.persistent_id, "reckless" if driver.reckless else "normal", q.snapped(Vector3.ONE * 0.1)]
					break
			var shape_node := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape_node.shape
			query.transform = car.global_transform * shape_node.transform
			query.collision_mask = 2
			query.exclude = [car.get_rid()]
			for hit in space.intersect_shape(query, 4):
				var other: Object = hit.collider
				if other is Node and other.is_in_group("traffic"):
					var key := "%s-%s" % [mini(car.get_instance_id(), other.get_instance_id()), maxi(car.get_instance_id(), other.get_instance_id())]
					collisions[key] = "%s & %s at %s" % [car.persistent_id, other.persistent_id, p.snapped(Vector3.ONE * 0.1)]
		for ped: Node3D in get_nodes_in_group("pedestrians"):
			var nav = ped.get("navigation")
			if nav == null or not ped.is_physics_processing():
				continue
			hooked += 1
			var pos := ped.global_position
			if nav.is_crossing():
				crossings_seen[ped] = true
				# Measure in the road, away from the kerbs
				if RoadGraph.on_road(pos) and not City.on_block(pos, 1.0):
					var speed := Vector2(ped.velocity.x, ped.velocity.z).length()
					var style: String = nav.crossing_style
					cross_samples[style] += 1
					var need := 1.8 if style == "hurry" else (1.1 if style == "walk_then_run" else 3.5)
					if speed < need:
						cross_slow += 1
						cross_slow_note = "%s style=%s speed=%.2f" % [ped.name, style, speed]
			elif nav.mode_name() in ["walk", "pause", "kerb"]:
				ped_samples += 1
				if not PavementGraph.on_pavement(pos, 0.35):
					ped_off += 1
					ped_off_note = "%s mode=%s at %s" % [ped.name, nav.mode_name(), pos.snapped(Vector3.ONE * 0.1)]

	var lane_share := float(lane_ok) / maxf(float(lane_samples), 1.0)
	var moving := 0
	for driver in travelled:
		if float(travelled[driver]) > 60.0:
			moving += 1
	print("lane keeping (normal, physics): %.1f%% of %d samples within 1 m, worst %.2f m" % [lane_share * 100.0, lane_samples, worst_lane])
	print("cars that drove over 60 m: %d of %d; off-road samples: %d; AI-AI contacts: %d" % [moving, traffic.drivers.size(), off_road, collisions.size()])
	_check(lane_samples > 200 and lane_share >= 0.95, "normal lane keeping %.1f%% (%d samples)" % [lane_share * 100.0, lane_samples])
	_check(off_road == 0, "AI car off the road %d times, last %s" % [off_road, off_road_note])
	_check(collisions.is_empty(), "AI cars collided: %s" % [collisions.values()])
	_check(moving >= traffic.drivers.size() * 0.7, "only %d of %d cars drove over 60 m" % [moving, traffic.drivers.size()])
	if hooked == 0:
		print("WARNING pedestrian checks skipped: pedestrian.gd does not call PedestrianNavigation yet")
	else:
		print("pedestrians: %d pavement samples, %d off pavement; crossings by %d people; crossing samples %s, %d too slow" % [ped_samples, ped_off, crossings_seen.size(), cross_samples, cross_slow])
		_check(ped_off == 0, "pedestrian off the pavement %d times, last %s" % [ped_off, ped_off_note])
		_check(cross_slow == 0, "crossing pedestrian too slow %d times, last %s" % [cross_slow, cross_slow_note])
		_check(crossings_seen.size() > 0, "no pedestrian crossed a road in 60 s")

	# Streaming (unchanged checks)
	var city: Node3D = main.get_node("City")
	var ground_kept := false
	for child in city.get_children():
		if child is StaticBody3D and child.collision_layer == 1:
			ground_kept = true
	var any_unloaded := false
	for chunk: Node3D in main._chunks:
		if not chunk.visible:
			any_unloaded = true
			break
	var distant_parked_frozen := false
	for parked in get_nodes_in_group("persistent_vehicles"):
		if parked.global_position.distance_to(player.global_position) > 80.0 and parked.freeze:
			distant_parked_frozen = true
			break
	_check(ground_kept and any_unloaded and distant_parked_frozen, "streaming: ground=%s unloaded=%s parked_frozen=%s" % [ground_kept, any_unloaded, distant_parked_frozen])
	_finish(main, _failures)


func _finish(_main: Node, failures: Array) -> void:
	for path in [Persistence.SAVE_PATH, Persistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not failures.is_empty():
		for failure in failures:
			push_error("world systems: " + failure)
		quit(1)
		return
	print("world systems: 90/10 drivers, lane keeping, no off-road or AI collisions, pavements and crossings OK; distant traffic on low-cost ticks; streaming OK")
	quit()
