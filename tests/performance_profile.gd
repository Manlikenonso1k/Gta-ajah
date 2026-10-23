extends SceneTree
## Headless CPU-side benchmark; not a substitute for fullscreen GPU profiling.

const Persistence = preload("res://scripts/vehicle_persistence.gd")

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Persistence.SAVE_PATH = "user://performance_profile_state.json"
	Persistence.TEMP_PATH = "user://performance_profile_state.json.tmp"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 120: await process_frame
	var elapsed_usec := 0
	var max_frame_usec := 0
	var frames := 240
	for i in frames:
		var started := Time.get_ticks_usec()
		await process_frame
		var frame_usec := Time.get_ticks_usec() - started
		elapsed_usec += frame_usec
		max_frame_usec = maxi(max_frame_usec, frame_usec)
	var average_ms := float(elapsed_usec) / float(frames) / 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("profile frames=%d avg_frame_ms=%.3f max_frame_ms=%.3f physics_ms=%.3f fps=%.1f nodes=%d cars=%d pedestrians=%d" % [
		frames, average_ms, float(max_frame_usec) / 1000.0, physics_ms, 1000.0 / maxf(average_ms, 0.01),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), get_nodes_in_group("cars").size(), get_nodes_in_group("pedestrians").size()
	])
	for path in [Persistence.SAVE_PATH, Persistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
