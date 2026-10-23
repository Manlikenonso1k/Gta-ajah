extends SceneTree
## Renders side-view contact sheets so animation can be checked by eye: one
## row per clip or gait, 12 frames per cycle. Needs a window (not --headless).
##
## Source clips on their own mannequin:
##   godot --path . --script tests/view_animation.gd -- ual Idle,Walk,Jog_Fwd
##   (ual2 for the second pack)
## A pedestrian on the shared library, through locomotion.gd (state:speed):
##   godot --path . --script tests/view_animation.gd -- PED_BA_M01 idle:0,walk:1.4,jog:2.6,run:4.5
##   godot --path . --script tests/view_animation.gd -- PED_BA_M01 clip:GetUp,clip:Driving
## Add "front" as a third argument for a front view. The character walks on
## the spot (foot sliding is measured by tests/pedestrian_models_test.gd).
## Images go to user://animation_views/.

const Registry = preload("res://scripts/pedestrian_registry.gd")
const Locomotion = preload("res://scripts/locomotion.gd")
const FRAMES := 12
const CELL := Vector2i(160, 240)

var _camera: Camera3D


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: print("TIMEOUT"); quit(1))
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var source := args[0] if args.size() > 0 else "ual"
	var rows: PackedStringArray = args[1].split(",") if args.size() > 1 else PackedStringArray()
	var view := args[2] if args.size() > 2 else "side"
	root.size = Vector2i(480, 720)
	var stage := _build_stage(view)
	var sheet: Image
	if source == "ual" or source == "ual2":
		sheet = await _clip_sheet(source, rows, stage)
	else:
		sheet = await _pedestrian_sheet(source, rows, stage)
	if sheet == null:
		quit(1)
		return
	var directory := "user://animation_views/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var out := ProjectSettings.globalize_path(directory + "%s_%s.png" % [source, view])
	sheet.save_png(out)
	print("saved ", out)
	quit()


func _grab(sheet: Image, column: int, row: int) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(CELL.x, CELL.y)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(column * CELL.x, row * CELL.y))


func _clip_sheet(source: String, clips: PackedStringArray, stage: Node3D) -> Image:
	var path := "res://assets/animations/quaternius_ual1/UAL1_Standard.glb" if source == "ual" else "res://assets/animations/quaternius_ual2/UAL2_Standard.glb"
	var model: Node3D = (load(path) as PackedScene).instantiate()
	stage.add_child(model)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if clips.is_empty():
		clips = player.get_animation_list()
	var sheet := Image.create(CELL.x * FRAMES, CELL.y * clips.size(), false, Image.FORMAT_RGB8)
	for row in clips.size():
		var clip := clips[row]
		if not player.has_animation(clip):
			print("missing clip ", clip)
			continue
		var anim := player.get_animation(clip)
		player.play(clip)
		player.pause()
		for f in FRAMES:
			player.seek(anim.length * f / FRAMES, true)
			await _grab(sheet, f, row)
		print("%-28s %.2fs" % [clip, anim.length])
	return sheet


func _pedestrian_sheet(id: String, rows: PackedStringArray, stage: Node3D) -> Image:
	var entry: Dictionary = Registry.by_id(id)
	if entry.is_empty():
		push_error("unknown pedestrian " + id)
		return null
	if rows.is_empty():
		rows = PackedStringArray(["idle:0", "walk:1.4", "jog:2.8", "run:4.5"])
	var sheet := Image.create(CELL.x * FRAMES, CELL.y * rows.size(), false, Image.FORMAT_RGB8)
	for row in rows.size():
		var parts := rows[row].split(":")
		var model: Node3D = (load(entry.model_path) as PackedScene).instantiate()
		model.scale = Vector3.ONE * float(entry.scale)
		stage.add_child(model)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var loco = Locomotion.create(model, {"idle": "Idle"}, rng)
		if loco == null:
			push_error("%s has no standard skeleton or the library is missing" % id)
			return null
		var cycle := 2.5
		if parts[0] == "clip":
			cycle = loco.play_action(parts[1])
			loco.advance(0.0)
		else:
			var speed := float(parts[1])
			loco.set_locomotion(speed, parts[0])
			for i in 60:
				loco.advance(1.0 / 30.0)
			if speed > 0.1:
				var gait: String = "walk" if loco._gait <= 1.5 else ("jog" if loco._gait <= 2.5 else "sprint")
				cycle = Locomotion.library().get_animation(loco._clips[gait]).length / loco._time_scale()
			print("%s %s: gait %.2f scale %.2f natural %s" % [id, rows[row], loco._gait, loco._time_scale(), loco.natural])
		for f in FRAMES:
			await _grab(sheet, f, row)
			loco.advance(cycle / FRAMES)
		model.queue_free()
		await process_frame
	return sheet


func _build_stage(view: String) -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.86, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 1.0
	stage.add_child(env)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.2, 0.2)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Ground line and height marks every 0.5 m
	for i in 5:
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6.0, 0.02 if i == 0 else 0.005, 6.0) if view == "front" else Vector3(0.1 if i == 0 else 0.01, 0.02 if i == 0 else 0.005, 6.0)
		mark.mesh = box
		mark.position = Vector3(0, -0.01, -1.5 if view == "front" else 0.0) if i == 0 else Vector3(-1.0, i * 0.5, -1.5 if view == "front" else 0.0)
		mark.material_override = dark
		stage.add_child(mark)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.4
	if view == "front":
		# Characters face +Z here (glTF convention), so the front camera is at +Z
		_camera.position = Vector3(0.0, 0.95, 5.0)
	else:
		# Side view from the character's left (+X), looking toward -X
		_camera.position = Vector3(5.0, 0.95, 0.0)
		_camera.rotation.y = PI / 2.0
	stage.add_child(_camera)
	_camera.make_current()
	return stage
