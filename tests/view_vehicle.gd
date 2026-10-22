extends SceneTree
## Renders side and top views of vehicles on a 0.5 m grid (front on the left,
## red lines = centre z = 0 and ground y = 0). Run with a window:
##
##   Measure a new model:  godot --path . --script tests/view_vehicle.gd -- raw <key> <length> <yaw>
##   Check a finished car: godot --path . --script tests/view_vehicle.gd -- car <key> [<key> ...]
##
## "car" mode tints the cut-out wheels magenta. Images go to user://vehicle_views/
## (on macOS: ~/Library/Application Support/Godot/app_userdata/GTA Port Harcourt/).

const VehicleModel = preload("res://scripts/vehicle_model.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://vehicle_views/"
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.85, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	root.add_child(env)

	var args := OS.get_cmdline_user_args()
	var mode: String = args[0]
	var jobs := []
	if mode == "raw":
		jobs.append([args[1], float(args[2]), float(args[3])])
	else:
		for key in args.slice(1):
			jobs.append([key, VehicleModel.MODELS[key]["length"], 0.0])

	for job in jobs:
		var subject := _raw(job[0], job[1], job[2]) if mode == "raw" else _car(job[0])
		root.add_child(subject)
		var size := maxf(job[1], 4.0) * 0.62
		var grid := _grid()
		root.add_child(grid)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = size
		root.add_child(cam)
		cam.position = Vector3(10, size * 0.28, 0)
		cam.rotation_degrees = Vector3(0, 90, 0)
		cam.make_current()
		for f in 6:
			await process_frame
		root.get_texture().get_image().save_png(out + "%s_%s_side.png" % [job[0], mode])
		cam.position = Vector3(0, 10, 0)
		cam.rotation_degrees = Vector3(-90, 90, 0)
		for f in 4:
			await process_frame
		root.get_texture().get_image().save_png(out + "%s_%s_top.png" % [job[0], mode])
		print("saved ", ProjectSettings.globalize_path(out), job[0], "_", mode, "_side/top.png")
		subject.queue_free()
		grid.queue_free()
		cam.queue_free()
		await process_frame
	quit()


## The model scaled to `length`, turned by `yaw`, centred, lowest point on y = 0.
func _raw(key: String, length: float, yaw: float) -> Node3D:
	var model: Node3D = load(VehicleModel.DIR + key + ".glb").instantiate()
	var box := AABB()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for i in meshes.size():
		var b: AABB = VehicleModel._chain(meshes[i], model) * meshes[i].get_aabb()
		box = b if i == 0 else box.merge(b)
	var rot := Basis(Vector3.UP, deg_to_rad(yaw))
	var rbox: AABB = Transform3D(rot) * box
	var s := length / rbox.size.z
	var c := rbox.get_center()
	var holder := Node3D.new()
	holder.add_child(model)
	holder.transform = Transform3D(rot.scaled(Vector3.ONE * s), Vector3(-c.x * s, -rbox.position.y * s, -c.z * s))
	print(key, " scale=", snappedf(s, 0.0001), " size=", (rbox.size * s).snappedf(0.01))
	return holder


## The finished car without physics, with the wheel meshes tinted.
func _car(key: String) -> Node3D:
	var data: Dictionary = VehicleModel.build(key)
	var holder := Node3D.new()
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color.MAGENTA
	for part in data["body"]:
		holder.add_child(_mesh(part, null))
	var counts := []
	for w in data["wheels"]:
		var hub := Node3D.new()
		hub.position = w["center"]
		holder.add_child(hub)
		var tris := 0
		for part in w["parts"]:
			hub.add_child(_mesh(part, tint))
			tris += part[0].surface_get_array_index_len(0) / 3
		counts.append(tris)
	print(key, " wheel tris: ", counts, "  hubs: ", data["wheels"].map(func(w): return w["center"].snappedf(0.01)))
	return holder


func _mesh(part: Array, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = part[0]
	m.transform = part[1]
	m.material_override = material
	return m


func _grid() -> Node3D:
	var grid := Node3D.new()
	for z in range(-16, 17):
		_line(grid, Vector3(-3, 1.5, z * 0.5), Vector3(0.01, 3, 0.02 if z % 2 else 0.05), Color.RED if z == 0 else Color(0.3, 0.3, 0.3))
	for y in range(0, 9):
		_line(grid, Vector3(-3, y * 0.5, 0), Vector3(0.01, 0.02 if y % 2 else 0.05, 16), Color.RED if y == 0 else Color(0.3, 0.3, 0.3))
	return grid


func _line(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
