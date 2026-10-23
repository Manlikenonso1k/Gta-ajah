extends Node
## Small loop-based road traffic. Traffic uses existing VehicleBody models.

const Car = preload("res://scripts/car.gd")
const City = preload("res://scripts/city.gd")
const VehicleModel = preload("res://scripts/vehicle_model.gd")
const MODELS := ["corolla", "vw_t3", "hiace", "town_bus", "bmw_e30"]
const DETAIL_RADIUS := 115.0
var _world: Node3D
var _tick := 0.0


func setup(world: Node3D, count: int) -> void:
	_world = world
	for i in count:
		var low := i % 3
		var high := mini(low + 3, City.GRID)
		var route := _rectangle_route(low, high, i % 2 == 1)
		if route.size() < 4:
			continue
		var car := Car.new()
		car.model = MODELS[i % MODELS.size()]
		car.ai_enabled = true
		car.ai_route = route
		car.ai_route_index = 1
		car.ai_target_speed = float(VehicleModel.MODELS[car.model]["handling"]["top_speed"]) * (0.34 + 0.04 * float(i % 3))
		car.persistent_id = "traffic_%02d" % i
		var forward: Vector3 = (route[1] - route[0]).normalized()
		car.transform = Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), route[0] + Vector3.UP * 0.65)
		world.add_child(car)
		car.add_to_group("traffic")


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25 or _world == null or not is_instance_valid(_world._player):
		return
	var step := _tick
	_tick = 0.0
	var focus: Node3D = _world._player.car if _world._player.car != null else _world._player
	for car in get_tree().get_nodes_in_group("traffic"):
		var distant: bool = car.global_position.distance_to(focus.global_position) > DETAIL_RADIUS
		if distant:
			if car.is_physics_processing():
				car.set_physics_process(false)
			car.freeze = true
			_advance_distant(car, step)
		else:
			if car.freeze:
				car.freeze = false
			if not car.is_physics_processing():
				car.set_physics_process(true)


func _rectangle_route(low: int, high: int, reverse: bool) -> Array[Vector3]:
	var left := City.road_line(low)
	var right := City.road_line(high)
	var near := City.road_line(low)
	var far := City.road_line(high)
	var corners := [Vector3(left, 0, near), Vector3(right, 0, near), Vector3(right, 0, far), Vector3(left, 0, far)]
	if reverse:
		corners.reverse()
	var route: Array[Vector3] = []
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		var forward := (b - a).normalized()
		var right_lane := Vector3(forward.z, 0.0, -forward.x)
		route.append(a + right_lane * 3.0)
	return route


func _advance_distant(car: VehicleBody3D, delta: float) -> void:
	if car.ai_route.is_empty():
		return
	var target: Vector3 = car.ai_route[car.ai_route_index % car.ai_route.size()]
	var offset := target - car.global_position
	offset.y = 0.0
	if offset.length() < 5.0:
		car.ai_route_index = (car.ai_route_index + 1) % car.ai_route.size()
		target = car.ai_route[car.ai_route_index]
		offset = target - car.global_position
		offset.y = 0.0
	var direction := offset.normalized()
	var current := car.linear_velocity
	var desired: Vector3 = direction * car.ai_target_speed
	current = current.move_toward(desired, 4.0 * delta)
	car.linear_velocity = current
	car.global_position += current * delta
	if direction.length_squared() > 0.0:
		car.global_basis = Basis(Vector3.UP, atan2(direction.x, direction.z))
