extends SceneTree
## QA windowed FPS sample (GPU + CPU). Not headless: needs a window.
## Usage: godot --path . --script tests/qa_fps.gd -- --quality=high [--shot=/abs/path.png]
## Renders the game at 1280x720 with vsync off, warms up, then measures 300 frames.

const Persistence = preload("res://scripts/vehicle_persistence.gd")
const WARMUP := 180
const FRAMES := 300


func _initialize() -> void:
	# Safety: never hang the shared machine.
	var timer := create_timer(180.0)
	timer.timeout.connect(func() -> void:
		push_error("qa_fps: safety timeout")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	Persistence.SAVE_PATH = "user://qa_fps_state.json"
	Persistence.TEMP_PATH = "user://qa_fps_state.json.tmp"
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in WARMUP:
		await process_frame
	var times: Array[float] = []
	var total := 0
	for i in FRAMES:
		var started := Time.get_ticks_usec()
		await process_frame
		var dt := Time.get_ticks_usec() - started
		total += dt
		times.append(dt / 1000.0)
	times.sort()
	var avg := float(total) / FRAMES / 1000.0
	var p95 := times[int(FRAMES * 0.95)]
	var p99 := times[int(FRAMES * 0.99)]
	print("qa_fps size=%s avg_ms=%.2f fps=%.1f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f draw_calls=%d prims=%d nodes=%d cars=%d peds=%d" % [
		str(DisplayServer.window_get_size()), avg, 1000.0 / maxf(avg, 0.01), p95, p99, times[FRAMES - 1],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		get_nodes_in_group("cars").size(), get_nodes_in_group("pedestrians").size()])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			var img := root.get_texture().get_image()
			img.save_png(arg.trim_prefix("--shot="))
	for path in [Persistence.SAVE_PATH, Persistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()
