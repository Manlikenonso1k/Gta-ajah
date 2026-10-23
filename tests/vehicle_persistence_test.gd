extends SceneTree
## Versioned save/load and invalid-state fallback check.

const Persistence = preload("res://scripts/vehicle_persistence.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var old_path := Persistence.SAVE_PATH
	var old_temp := Persistence.TEMP_PATH
	Persistence.SAVE_PATH = "user://persistence_test.json"
	Persistence.TEMP_PATH = "user://persistence_test.json.tmp"
	var expected := Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.0)), Vector3(12.0, 0.6, -8.0))
	var states := {"vw_t3_006": Persistence.state_from_transform(expected)}
	var saved := Persistence.save_states(states)
	var loaded := Persistence.load_states()
	var restored := Persistence.transform_from_state(loaded.get("vw_t3_006"), Transform3D.IDENTITY)
	var fallback := Transform3D.IDENTITY
	var invalid := Persistence.transform_from_state({"position": [0, -1000, 0], "rotation": [0, 0, 0]}, fallback)
	var round_trip_ok := saved and loaded.has("vw_t3_006") and restored.origin.distance_to(expected.origin) < 0.001 and absf(restored.basis.get_euler().y - 0.7) < 0.001 and invalid == fallback
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var first_world: Node3D = main_scene.instantiate()
	root.add_child(first_world)
	for i in 60: await physics_frame
	var parked: Node3D
	for candidate in first_world.get_children():
		if candidate.is_in_group("persistent_vehicles") and candidate.persistent_id == "corolla_000":
			parked = candidate
			break
	if parked == null:
		push_error("Could not find stable vehicle ID in integration test")
		quit(1)
		return
	parked.global_transform = Transform3D(Basis(Vector3.UP, 0.25), Vector3(23.0, 0.6, 26.0))
	parked.linear_velocity = Vector3.ZERO
	parked.angular_velocity = Vector3.ZERO
	first_world.save_vehicle_states()
	first_world.queue_free()
	await process_frame
	await process_frame
	var restarted_world: Node3D = main_scene.instantiate()
	root.add_child(restarted_world)
	for i in 60: await physics_frame
	var restored_car: Node3D
	for candidate in restarted_world.get_children():
		if candidate.is_in_group("persistent_vehicles") and candidate.persistent_id == "corolla_000":
			restored_car = candidate
			break
	var restart_ok := restored_car != null and Vector2(restored_car.global_position.x, restored_car.global_position.z).distance_to(Vector2(23, 26)) < 0.5 and absf(restored_car.global_rotation.y - 0.25) < 0.08
	for path in [Persistence.SAVE_PATH, Persistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Persistence.SAVE_PATH = old_path
	Persistence.TEMP_PATH = old_temp
	if not round_trip_ok or not restart_ok:
		push_error("Vehicle persistence round-trip, restart restoration, or invalid-state fallback failed")
		quit(1)
		return
	print("vehicle persistence: versioned save/load, restart restoration, and invalid transform fallback passed")
	quit()
