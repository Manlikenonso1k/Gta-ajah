extends SceneTree
## Passenger mass, normal contact, and smooth contact-loss regression check.

const Persistence = preload("res://scripts/vehicle_persistence.gd")

func _initialize() -> void:
	Persistence.SAVE_PATH = "user://vehicle_contact_test.json"
	Persistence.TEMP_PATH = "user://vehicle_contact_test.json.tmp"
	_run.call_deferred()

func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 90: await physics_frame
	var car: Node3D
	for candidate in get_nodes_in_group("cars"):
		if candidate.persistent_id == "corolla_000":
			car = candidate
			break
	if car == null:
		push_error("Starter vehicle missing")
		quit(1)
		return
	car.global_transform = car.original_spawn_transform
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.driver = main
	car.set_physics_process(true)
	for i in 60: await physics_frame
	var contacts_at_rest: int = car._wheels.filter(func(w): return w.is_in_contact()).size()
	var base_mass: float = car._base_mass
	car.set_driver_weight_loaded(true)
	for i in 30: await physics_frame
	var loaded_mass: float = car.mass
	car.set_driver_weight_loaded(false)
	for i in 35: await physics_frame
	var unloaded_mass: float = car.mass
	car.global_position += Vector3.UP * 5.0
	for i in 35: await physics_frame
	var airborne_ratio: float = car._traction_blend
	for i in 120: await physics_frame
	var restored_contacts: int = car._wheels.filter(func(w): return w.is_in_contact()).size()
	for path in [Persistence.SAVE_PATH, Persistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if contacts_at_rest < 3 or loaded_mass < base_mass + 60.0 or unloaded_mass > base_mass + 1.0 or airborne_ratio >= 0.95 or restored_contacts < 3:
		push_error("Vehicle response failed contacts=%d loaded=%.1f unloaded=%.1f blend=%.2f restored=%d" % [contacts_at_rest, loaded_mass, unloaded_mass, airborne_ratio, restored_contacts])
		quit(1)
		return
	print("vehicle contact: %d wheels grounded; passenger mass %.0f kg added/restored smoothly; grip %.2f airborne and contact recovered" % [contacts_at_rest, loaded_mass - base_mass, airborne_ratio])
	quit()
