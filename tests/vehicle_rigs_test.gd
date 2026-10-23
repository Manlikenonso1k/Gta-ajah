extends SceneTree
## Checks the Sprinter rig and per-model handling/transmission metadata.

const VehicleModel = preload("res://scripts/vehicle_model.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var van_gears := VehicleModel.MODELS["sprinter"]["handling"]["gears"]
	var bus_gears := VehicleModel.MODELS["coach"]["handling"]["gears"]
	if van_gears.size() < 4 or bus_gears.size() < 4:
		push_error("Heavy vehicle transmission stages are missing")
		quit(1)
		return
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 90: await physics_frame
	var car: Node3D
	for candidate in get_nodes_in_group("cars"):
		if candidate.model == "sprinter":
			car = candidate
			break
	if car._door_animation == null:
		push_error("Sprinter door animation was not loaded")
		quit(1)
		return
	var clip: Animation = car._door_animation.get_animation(car._door_clip)
	var enabled := []
	for i in clip.get_track_count():
		if clip.track_is_enabled(i):
			enabled.append(str(clip.track_get_path(i)))
	if enabled.size() != 1 or "Porte_avnt_1" not in enabled[0]:
		push_error("Sprinter should animate only its +X driver's door: %s" % [enabled])
		quit(1)
		return
	car.driver = main
	car.linear_velocity = car.global_basis.z * 25.0
	Input.action_press("move_forward")
	await physics_frame
	Input.action_release("move_forward")
	var shifted_up: bool = car.current_gear > 1
	car.linear_velocity = Vector3.ZERO
	for i in 30: await physics_frame
	var shifted_down: bool = car.current_gear == 1
	if not shifted_up or not shifted_down:
		push_error("Sprinter transmission did not shift with speed (up=%s down=%s)" % [shifted_up, shifted_down])
		quit(1)
		return
	print("vehicle rig check passed: independent driver's door and automatic van up/down shifts")
	quit()
