extends SceneTree
## Checks that blocks stream while the permanent ground collider stays present,
## and that distant traffic uses its lightweight route simulation.

const Persistence = preload("res://scripts/vehicle_persistence.gd")
const Car = preload("res://scripts/car.gd")

func _initialize() -> void:
	Persistence.SAVE_PATH = "user://world_systems_test.json"
	Persistence.TEMP_PATH = "user://world_systems_test.json.tmp"
	_run.call_deferred()

func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60: await physics_frame
	var traffic := get_nodes_in_group("traffic")
	if traffic.is_empty():
		push_error("Traffic did not spawn")
		quit(1)
		return
	var car: Car = traffic[0]
	car.global_position = Vector3(210.0, 1.0, 210.0)
	var test_route: Array[Vector3] = [Vector3(300, 0, 210), Vector3(300, 0, 300), Vector3(210, 0, 300), Vector3(210, 0, 210)]
	car.ai_route = test_route
	car.ai_route_index = 0
	car.linear_velocity = Vector3.ZERO
	car.set_physics_process(true)
	await process_frame
	var start := car.global_position
	for i in 45: await physics_frame
	var moved := car.global_position.distance_to(start) > 0.1
	var lightweight: bool = not car.is_physics_processing() and car.freeze
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
		if parked.global_position.distance_to(main._player.global_position) > 80.0 and parked.freeze:
			distant_parked_frozen = true
			break
	for path in [Persistence.SAVE_PATH, Persistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not moved or not lightweight or not ground_kept or not any_unloaded or not distant_parked_frozen:
		push_error("Streaming/traffic check failed moved=%s lightweight=%s ground=%s unloaded=%s parked_frozen=%s" % [moved, lightweight, ground_kept, any_unloaded, distant_parked_frozen])
		quit(1)
		return
	print("world systems: distant traffic advances on low-cost ticks; far blocks and parked cars deactivate; ground collision remains")
	quit()
