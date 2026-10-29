extends SceneTree
## Averaged CPU profile, for before/after comparisons of drivers and passengers.
## Run: godot --headless --path . --script tests/steering_profile.gd -- --quality=high
##
## Unlike performance_profile.gd (one physics-time reading), this averages the
## physics and process time monitors over FRAMES frames after a warm-up, and
## counts the people seated in cars (nodes named Seat_*), so it runs unchanged
## on builds with and without them. load_ms is the time to build the world.

const Persistence = preload("res://scripts/vehicle_persistence.gd")
const WARMUP := 180
const FRAMES := 600


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func():
		push_error("steering_profile timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	Persistence.SAVE_PATH = "user://steering_profile_state.json"
	Persistence.TEMP_PATH = "user://steering_profile_state.json.tmp"
	var load_started := Time.get_ticks_usec()
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var load_ms := (Time.get_ticks_usec() - load_started) / 1000.0
	for i in WARMUP:
		await process_frame
	var physics := 0.0
	var process := 0.0
	var worst_physics := 0.0
	var ragdolls_max := 0
	var frame := 0
	var worst := 0
	for i in FRAMES:
		var started := Time.get_ticks_usec()
		await process_frame
		var dt := Time.get_ticks_usec() - started
		frame += dt
		worst = maxi(worst, dt)
		var physics_now := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += physics_now
		worst_physics = maxf(worst_physics, physics_now)
		ragdolls_max = maxi(ragdolls_max, get_nodes_in_group("ragdolls").size())
		process += Performance.get_monitor(Performance.TIME_PROCESS)
	var seated := 0
	var shown := 0
	for car: Node in get_nodes_in_group("cars"):
		for seat: Node3D in car.find_children("Seat_*", "Node3D", false, false):
			seated += 1
			if seat.is_visible_in_tree():
				shown += 1
	print("steering_profile load_ms=%.0f frames=%d avg_frame_ms=%.3f max_frame_ms=%.3f avg_physics_ms=%.3f avg_process_ms=%.3f nodes=%d cars=%d traffic=%d pedestrians=%d seated=%d seated_visible=%d max_physics_ms=%.2f ragdolls_max=%d" % [
		load_ms, FRAMES, frame / 1000.0 / FRAMES, worst / 1000.0, physics * 1000.0 / FRAMES, process * 1000.0 / FRAMES,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), get_nodes_in_group("cars").size(),
		get_nodes_in_group("traffic").size(), get_nodes_in_group("pedestrians").size(), seated, shown, worst_physics * 1000.0, ragdolls_max])
	for path in [Persistence.SAVE_PATH, Persistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
