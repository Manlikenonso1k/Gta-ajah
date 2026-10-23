extends Node
## Road traffic on the road graph, driving on the right.
##
## spawn_car() makes a Car (VehicleBody3D, scripts/car.gd) with ai_enabled and
## a TrafficDriver (scripts/traffic_driver.gd) in car.ai_driver, adds it to
## the world and to the "traffic" group, then emits car_spawned(car).
## Cars within DETAIL_RADIUS of the player drive with vehicle physics; further
## away they are frozen and moved along the same path on cheap ticks.
## 90% of drivers are normal and 10% reckless (exactly one in every ten spawns).
## F6 toggles the debug view (scripts/traffic_debug.gd).

signal car_spawned(car: VehicleBody3D)
## Emitted when a car switches between vehicle physics (near, `physics` true)
## and the frozen lightweight mode (far). Also set as car meta "traffic_detail".
signal car_detail_changed(car: VehicleBody3D, physics: bool)

const Car = preload("res://scripts/car.gd")
const City = preload("res://scripts/city.gd")
const RoadGraph = preload("res://scripts/road_graph.gd")
const TrafficDriver = preload("res://scripts/traffic_driver.gd")
const TrafficDebug = preload("res://scripts/traffic_debug.gd")
const VehicleModel = preload("res://scripts/vehicle_model.gd")
## Models that can make the 12 m city junction turns (buses and the coach can't)
const MODELS := ["corolla", "camry", "bmw_e30", "accord", "hiace", "vw_t3"]
const RECKLESS_MODELS := ["vw_t3", "hiace"]
const DETAIL_RADIUS := 115.0
## Think rates: nearby physics cars, lightweight cars, very distant cars
const NEAR_TICK := 0.1
const FAR_TICK := 0.25
const VERY_FAR_TICK := 1.0
const VERY_FAR_RADIUS := 250.0
## Smallest junction-movement separation (m) that lets two cars share a junction
const JUNCTION_CLEARANCE := 3.4

var drivers: Array = []
var _world: Node3D
var _graph: RefCounted
var _rng := RandomNumberGenerator.new()
var _deck: Array[bool] = []
var _spawned := 0
var _time := 0.0
var _next_think := {}
var _last_think := {}
## junction id -> Array of [driver, mark, time held]
var _holds := {}
var _debug: Node3D


func setup(world: Node3D, count: int) -> void:
	_world = world
	_graph = RoadGraph.shared()
	_rng.seed = 7307
	spawn_cars(count)


## Shuffled decks of ten with exactly one reckless driver each.
static func driver_type_deck(rng: RandomNumberGenerator) -> Array[bool]:
	var deck: Array[bool] = []
	for i in 10:
		deck.append(i == 0)
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := deck[i]
		deck[i] = deck[j]
		deck[j] = swap
	return deck


func next_driver_is_reckless() -> bool:
	if _deck.is_empty():
		_deck = driver_type_deck(_rng)
	return _deck.pop_back()


func spawn_cars(count: int) -> void:
	for i in count:
		var spot := _free_spot()
		if spot.is_empty():
			continue
		var reckless := next_driver_is_reckless()
		var model: String = RECKLESS_MODELS[_spawned % RECKLESS_MODELS.size()] if reckless else MODELS[_spawned % MODELS.size()]
		spawn_car(spot.lane, spot.distance, model, reckless)


## Spawns one AI car on `lane`, `distance` metres from the lane's start junction.
func spawn_car(lane: int, distance: float, model: String, reckless: bool) -> VehicleBody3D:
	var car := Car.new()
	car.model = model
	car.ai_enabled = true
	car.persistent_id = "traffic_%02d" % _spawned
	var driver := TrafficDriver.new(car, self, reckless, 1000 + _spawned)
	driver.setup_cruise(float(VehicleModel.MODELS[model]["handling"]["top_speed"]))
	car.ai_driver = driver
	_spawned += 1
	driver.start(lane, distance)
	var forward: Vector3 = _graph.lanes[lane].dir
	car.transform = Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), _graph.lane_point(lane, distance) + Vector3.UP * 0.65)
	_world.add_child(car)
	car.add_to_group("traffic")
	car.set_meta("traffic_detail", true)
	car.tree_exiting.connect(_forget.bind(driver))
	drivers.append(driver)
	_next_think[driver] = 0.0
	_last_think[driver] = 0.0
	car_spawned.emit(car)
	return car


func _forget(driver: RefCounted) -> void:
	release_all(driver)
	drivers.erase(driver)
	_next_think.erase(driver)
	_last_think.erase(driver)


func _free_spot() -> Dictionary:
	var avoid: Array[Vector3] = []
	for node: Node3D in get_tree().get_nodes_in_group("cars"):
		avoid.append(node.global_position)
	if _world != null and _world.get("_player") != null:
		avoid.append(_world._player.global_position)
	for attempt in 80:
		var lane := _rng.randi_range(0, _graph.lanes.size() - 1)
		var distance := _rng.randf_range(16.0, 34.0)
		var p: Vector3 = _graph.lane_point(lane, distance)
		var clear := true
		for q in avoid:
			if Vector2(p.x - q.x, p.z - q.z).length() < 22.0:
				clear = false
				break
		if clear:
			return {"lane": lane, "distance": distance}
	return {}


## Junction give-way: a car may enter when its movement keeps JUNCTION_CLEARANCE
## from every movement already holding the junction. First come, first served.
func request_junction(driver: RefCounted, mark: Dictionary) -> bool:
	var holds: Array = _holds.get(mark.junction, [])
	for hold: Array in holds:
		if hold[0] == driver:
			continue
		if _movements_conflict(hold[1].dense, mark.dense):
			return false
	holds.append([driver, mark, _time])
	_holds[mark.junction] = holds
	return true


static func _movements_conflict(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	var limit := JUNCTION_CLEARANCE * JUNCTION_CLEARANCE
	for p in a:
		for q in b:
			if Vector2(p.x - q.x, p.z - q.z).length_squared() < limit:
				return true
	return false


func release_all(driver: RefCounted) -> void:
	for junction in _holds.keys():
		var holds: Array = _holds[junction]
		for i in range(holds.size() - 1, -1, -1):
			if holds[i][0] == driver:
				holds[i][1].held = false
				holds.remove_at(i)


func _release_passed() -> void:
	for junction in _holds.keys():
		var holds: Array = _holds[junction]
		for i in range(holds.size() - 1, -1, -1):
			var driver: RefCounted = holds[i][0]
			var mark: Dictionary = holds[i][1]
			var passed: bool = not driver in drivers or driver.s > mark.exit + driver.half_length() + 1.5
			# A holder stuck for 25 s gives the junction up (it is reset or reverses)
			if passed or _time - float(holds[i][2]) > 25.0:
				mark.held = false
				holds.remove_at(i)


func _physics_process(delta: float) -> void:
	_time += delta
	if _world == null or drivers.is_empty():
		return
	var player: Node3D = _world.get("_player")
	if player == null or not is_instance_valid(player):
		return
	var focus: Node3D = player.car if player.car != null else player
	var cars := get_tree().get_nodes_in_group("cars")
	var people: Array = []
	for person: Node3D in get_tree().get_nodes_in_group("pedestrians"):
		if person.is_physics_processing() or RoadGraph.on_road(person.global_position):
			people.append(person)
	if player.car == null:
		people.append(player)
	_release_passed()
	for driver: RefCounted in drivers:
		if _time < _next_think[driver]:
			continue
		var car: VehicleBody3D = driver.car
		var dt: float = _time - _last_think[driver]
		_last_think[driver] = _time
		var distance := car.global_position.distance_to(focus.global_position)
		var distant := distance > DETAIL_RADIUS
		if distant and not car.freeze:
			driver.enter_lightweight()
			car.set_physics_process(false)
			car.freeze = true
			dt = 0.0
			car.set_meta("traffic_detail", false)
			car_detail_changed.emit(car, false)
		elif not distant and car.freeze:
			car.freeze = false
			car.set_physics_process(true)
			driver.exit_lightweight()
			car.set_meta("traffic_detail", true)
			car_detail_changed.emit(car, true)
		driver.think(cars, people, maxf(dt, 0.0))
		if distant:
			driver.advance_lightweight(dt)
			_next_think[driver] = _time + (VERY_FAR_TICK if distance > VERY_FAR_RADIUS else FAR_TICK)
		else:
			_maybe_reset(driver)
			_next_think[driver] = _time + NEAR_TICK


## A car that is flipped, far off its lane or stuck after several reversing
## attempts is put back on the nearest lane, but only while nobody can see it.
func _maybe_reset(driver: RefCounted) -> void:
	var car: VehicleBody3D = driver.car
	var flipped := car.global_basis.y.y < 0.4
	if not flipped and driver.stuck_count < 3 and driver.off_lane_time < 3.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.is_position_in_frustum(car.global_position) and camera.global_position.distance_to(car.global_position) < 150.0:
		return
	reset_to_lane(driver)


func reset_to_lane(driver: RefCounted) -> void:
	var car: VehicleBody3D = driver.car
	var found: Dictionary = _graph.nearest_lane(car.global_position, car.global_basis.z)
	var lane: int = found.lane
	var distance := clampf(found.distance, 14.0, float(_graph.lanes[lane].length) - 18.0)
	driver.start(lane, distance)
	var forward: Vector3 = _graph.lanes[lane].dir
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), _graph.lane_point(lane, distance) + Vector3.UP * 0.65)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	driver.stuck_count = 0
	driver.off_lane_time = 0.0
	driver.speed = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F6:
		set_debug_visible(_debug == null or not _debug.visible)
		get_viewport().set_input_as_handled()


func set_debug_visible(show: bool) -> void:
	if _debug == null:
		if not show:
			return
		_debug = TrafficDebug.new()
		_debug.traffic = self
		add_child(_debug)
	_debug.visible = show
