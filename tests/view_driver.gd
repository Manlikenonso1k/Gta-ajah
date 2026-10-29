extends SceneTree
## Renders seated drivers for checking by eye. Run with a window:
##
##   godot --path . --script tests/view_driver.gd [-- <model> ...]
##       The player walks to each parked <model> (default camry), sits down and
##       steers full left, centre and full right. Two contact sheets per model in
##       user://vehicle_views/: seated_<model>.png (rows: full left, centre, full
##       right; columns: front through the windscreen, side through the driver's
##       window, three-quarter front, and the usual driving camera) and
##       seated_<model>_cutaway.png (body hidden except the steering wheel, so
##       hands on the rim and arms against the body show clearly; columns
##       front, side, three-quarter).
##   godot --path . --script tests/view_driver.gd -- traffic <model> ...
##       An AI driver and passengers (as traffic.gd fills them) in a stopped
##       <model>: traffic_<model>.png (row 1 normal, row 2 cutaway; columns
##       front, side, three-quarter, rear three-quarter).
##   godot --path . --script tests/view_driver.gd -- player
##       The player model on its own (see _player_view).

const VehiclePersistence = preload("res://scripts/vehicle_persistence.gd")
const CELL := Vector2i(640, 360)
const OUT := "user://vehicle_views/"
## Camera offsets in the car's frame from the driver's chest: front, side,
## three-quarter front (driver's side), three-quarter rear
const VIEWS := {
	"front": Vector3(0.0, 0.25, 2.3),
	"side": Vector3(2.1, 0.15, 0.1),
	"three_quarter": Vector3(1.55, 0.35, 1.55),
	"rear_three_quarter": Vector3(1.8, 0.6, -2.2),
}

var main: Node3D


func _initialize() -> void:
	create_timer(600.0).timeout.connect(func():
		push_error("view_driver timed out")
		quit(2))
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] == "player":
		await _player_view()
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	VehiclePersistence.SAVE_PATH = "user://view_driver_state.json"
	VehiclePersistence.TEMP_PATH = "user://view_driver_state.json.tmp"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(90)
	if not args.is_empty() and args[0] == "traffic":
		for model in args.slice(1):
			await _traffic_sheet(model)
	else:
		for model in (args if not args.is_empty() else ["camry"]):
			await _seated_sheets(model)
	for path in [VehiclePersistence.SAVE_PATH, VehiclePersistence.TEMP_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit()


func _seated_sheets(model: String) -> void:
	var player = main._player
	var car: VehicleBody3D
	for candidate in get_nodes_in_group("cars"):
		if candidate.model == model and not candidate.is_in_group("traffic"):
			car = candidate
			break
	if car == null:
		push_error("no parked %s" % model)
		return
	# Keep traffic out of the shots
	for t in get_nodes_in_group("traffic"):
		t.queue_free()
	player.global_position = car.to_global(car.driver_door_point()) + car.global_basis.x * 0.8 + Vector3.UP * 0.1
	# A parked car waking up as the player appears beside it can knock him
	# over (seen when teleporting between cars); let him get up first
	await _frames(20)
	for i in 400:
		if player.interaction_state == player.InteractionState.ON_FOOT:
			break
		await physics_frame
	player._try_enter_car()
	var last_state := -1
	for i in 900:
		await physics_frame
		if player.interaction_state != last_state:
			last_state = player.interaction_state
			print("  %s entry: frame %d state %d at %s" % [model, i, last_state, player.global_position.snappedf(0.01)])
		if player.car == car and not car.occupants.is_busy():
			break
	if player.car != car or car.occupants.is_busy():
		push_error("player did not sit down in the %s (state %d, in %s, at %s, door %s, busy %s)" % [model, player.interaction_state,
			player.car.model if player.car != null else "nothing", player.global_position.snappedf(0.01),
			car.to_global(car.driver_door_point()).snappedf(0.01), player._interaction_busy])
		return
	var rig: Node3D = player.camera_rig
	var game_cam: Camera3D = rig.camera
	var sheet := Image.create(CELL.x * 4, CELL.y * 3, false, Image.FORMAT_RGBA8)
	var cut := Image.create(CELL.x * 3, CELL.y * 3, false, Image.FORMAT_RGBA8)
	var row := 0
	for steer in ["move_left", "", "move_right"]:
		for a in ["move_left", "move_right"]:
			Input.action_release(a)
		if not steer.is_empty():
			Input.action_press(steer)
		await _frames(45)
		var col := 0
		for view in ["front", "side", "three_quarter"]:
			_blit(sheet, await _shot(car, VIEWS[view]), col, row)
			col += 1
		# The usual chase camera behind the car
		rig.yaw = car.global_rotation.y + PI
		game_cam.make_current()
		for f in 4:
			await process_frame
		_blit(sheet, root.get_texture().get_image(), 3, row)
		_set_body_visible(car, false)
		col = 0
		for view in ["front", "side", "three_quarter"]:
			_blit(cut, await _shot(car, VIEWS[view]), col, row)
			col += 1
		_set_body_visible(car, true)
		var occ: Node3D = car.occupants
		print("%s %s: wheel %.2f rad, left palm %.3f m / right palm %.3f m off the rim" % [
			model, steer if not steer.is_empty() else "centre", occ.wheel_angle, occ.driver.rim_error("Left"), occ.driver.rim_error("Right")])
		row += 1
	for a in ["move_left", "move_right"]:
		Input.action_release(a)
	game_cam.make_current()
	_save(sheet, "seated_%s.png" % model)
	_save(cut, "seated_%s_cutaway.png" % model)
	# Get out again for the next model
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	for i in 600:
		await physics_frame
		if player.car == null and player.interaction_state == player.InteractionState.ON_FOOT:
			break


func _traffic_sheet(model: String) -> void:
	var traffic: Node = null
	for child in main.get_children():
		if child.has_method("spawn_car"):
			traffic = child
	var spot: Dictionary = traffic._free_spot()
	if spot.is_empty():
		push_error("no free lane spot")
		return
	var car: VehicleBody3D = traffic.spawn_car(spot.lane, spot.distance, model, false)
	# Hold it still and out of traffic's hands so the people can be looked at
	traffic._forget(car.ai_driver)
	car.remove_from_group("traffic")
	car.ai_enabled = false
	await _frames(60)
	var sheet := Image.create(CELL.x * 4, CELL.y * 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		_set_body_visible(car, row == 0)
		var col := 0
		for view in ["front", "side", "three_quarter", "rear_three_quarter"]:
			_blit(sheet, await _shot(car, VIEWS[view], 0.25), col, row)
			col += 1
	_set_body_visible(car, true)
	print("%s: driver %s, %d passengers" % [model, car.occupants.driver.model.get_meta("character_id", "?"), car.occupants.passengers.size()])
	_save(sheet, "traffic_%s.png" % model)


## A frame from `offset` (car frame, from the driver's chest), looking at the
## chest. `back` shifts the look point towards the rear (for passengers).
func _shot(car: Node3D, offset: Vector3, back := 0.0) -> Image:
	var seat: Vector3 = car.occupants.cabin["seat"]
	var chest := car.to_global(seat + Vector3(-0.1 if back > 0.0 else 0.0, 0.35, 0.25 - back * 4.0))
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	root.add_child(cam)
	cam.global_position = chest + car.global_basis * (offset * (1.0 + back * 2.0))
	cam.look_at(chest)
	cam.make_current()
	for f in 4:
		await process_frame
	var img := root.get_texture().get_image()
	cam.queue_free()
	return img


## Shows or hides the car body and road wheels, keeping the steering wheel and
## the people.
func _set_body_visible(car: Node3D, show: bool) -> void:
	for child in car.get_children():
		if child.name == "SteeringWheel" or str(child.name).begins_with("Seat_") or child.name == "Occupants":
			continue
		if child is VisualInstance3D or child is VehicleWheel3D or (child is Node3D and child.get_child_count() > 0 and not child is CollisionObject3D):
			child.visible = show


func _blit(sheet: Image, img: Image, col: int, row: int) -> void:
	img.convert(Image.FORMAT_RGBA8)
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))


func _save(img: Image, file: String) -> void:
	var path := ProjectSettings.globalize_path(OUT + file)
	img.save_png(path)
	print("saved ", path)


## Loads assets/characters/player/player.glb on its own, prints its world-space
## size (height = y extent, feet expected at y = 0), and renders front, side
## and three-quarter views of the raw model (it faces +Z; the player turns it to
## -Z) on a 0.5 m grid. Images: user://vehicle_views/player_<view>.png.
func _player_view() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.85, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.2
	root.add_child(env)
	var model_path := "res://assets/characters/player/player.glb"
	if not ResourceLoader.exists(model_path):
		push_error("player model not found: " + model_path)
		return
	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	root.add_child(model)
	await process_frame
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("player AABB position ", box.position.snappedf(0.001), " size ", box.size.snappedf(0.001))
	print("player height (y) ", snappedf(box.size.y, 0.001), " m  feet y ", snappedf(box.position.y, 0.001), " m")
	var grid := _player_grid()
	root.add_child(grid)
	var center := box.get_center()
	var out := "user://vehicle_views/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var eye_y := box.position.y + box.size.y * 0.5
	var look := Vector3(center.x, eye_y, center.z)
	# The raw model faces +Z: front from +Z, side from +X, three-quarter between
	for view: Array in [["front", Vector3(0, 0, 3.2)], ["side", Vector3(3.2, 0, 0)], ["three_quarter", Vector3(2.26, 0, 2.26)]]:
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 2.4
		root.add_child(cam)
		cam.position = look + view[1]
		cam.look_at(look)
		cam.make_current()
		for f in 6:
			await process_frame
		var path := ProjectSettings.globalize_path(out + "player_%s.png" % view[0])
		root.get_texture().get_image().save_png(path)
		print("saved player view: ", path)
		cam.queue_free()
		await process_frame


func _player_grid() -> Node3D:
	var grid := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.35, 0.35)
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color.RED
	# Horizontal lines every 0.5 m up to 2 m; ground (y = 0) in red.
	for i in range(0, 5):
		var y := i * 0.5
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4, 0.01 if i else 0.02, 0.01)
		line.mesh = box
		line.material_override = red if i == 0 else mat
		line.position = Vector3(0, y, 0)
		grid.add_child(line)
	return grid
