extends SceneTree
## Renders side and top views of vehicles on a 0.5 m grid (front on the left,
## red lines = centre z = 0 and ground y = 0). Run with a window:
##
##   Measure a new model:  godot --path . --script tests/view_vehicle.gd -- raw <key> <length> <yaw>
##   Check a finished car: godot --path . --script tests/view_vehicle.gd -- car <key> [<key> ...]
##   Measure the cabin:    godot --path . --script tests/view_vehicle.gd -- cabin <key>[:mobile] [x y z] [size]
##     (seat and steering-wheel sections; see _cabin_views)
##
## "car" mode tints the cut-out wheels magenta. Images go to user://vehicle_views/
## (on macOS: ~/Library/Application Support/Godot/app_userdata/GTA Port Harcourt/).

const VehicleModel = preload("res://scripts/vehicle_model.gd")

var _source_dir := ""
var _suffix := ""


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
	if mode == "cabin":
		await _cabin_views(args.slice(1), out)
		quit()
		return
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
## `shape` replaces textures with normal-based shading and drops glass, so dark
## interiors read clearly in the cabin views.
func _car(key: String, shape := false) -> Node3D:
	var data: Dictionary = VehicleModel.build(key, _source_dir)
	var holder := Node3D.new()
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color.MAGENTA
	var shape_material: ShaderMaterial = null
	if shape:
		shape_material = ShaderMaterial.new()
		shape_material.shader = Shader.new()
		shape_material.shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvoid fragment() {\n\tvec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);\n\tALBEDO = vec3(0.25) + 0.55 * abs(n) * vec3(0.9, 1.0, 0.8);\n}\n"
	for part in data["body"]:
		var original: Material = part[0].surface_get_material(0)
		if shape and original is BaseMaterial3D and original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		holder.add_child(_mesh(part, shape_material))
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
	var sw: Dictionary = data.get("steering_wheel", {})
	if not sw.is_empty():
		var cyan := StandardMaterial3D.new()
		cyan.albedo_color = Color.CYAN
		var pivot := Node3D.new()
		pivot.position = sw["center"]
		holder.add_child(pivot)
		for part in sw["parts"]:
			pivot.add_child(_mesh(part, cyan))
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


## Cabin measuring views: `cabin <key>[:mobile] [fx fy fz] [size]`. Focus defaults to
## the steering-wheel centre stored in vehicles.json. Each view is a section:
## the camera's near plane cuts away the door, the seat back or the roof.
## A 0.1 m grid (labels every 0.5 m, car-local metres) is drawn on top.
## Measured data is overlaid: cut steering wheel cyan, measured rim as a yellow
## ring, the seat (hip) point as a green cross, the rim centre as a red cross.
func _cabin_views(args: Array, out: String) -> void:
	var key: String = args[0]
	if key.ends_with(":mobile"):
		key = key.trim_suffix(":mobile")
		_source_dir = VehicleModel.MOBILE_DIR
		_suffix = "_mobile"
	var data: Dictionary = VehicleModel.build(key, _source_dir)
	var cabin: Dictionary = VehicleModel.cabin(key)
	var focus := Vector3(0.38, 1.0, 0.6)
	if cabin.has("wheel_center"):
		focus = cabin["wheel_center"]
	var size := 1.6
	if args.size() >= 4:
		focus = Vector3(float(args[1]), float(args[2]), float(args[3]))
	if args.size() == 2 or args.size() >= 5:
		size = float(args[args.size() - 1])
	var subject := _car(key, true)
	root.add_child(subject)
	if not cabin.is_empty():
		subject.add_child(_cabin_overlay(cabin))
	var views := {
		# name: [camera offset, rotation, slab start and end (distance from the
		# focus towards / away from the camera), view size]
		"side": [Vector3(10, 0, 0), Vector3(0, 90, 0), 0.22, 0.25, size],
		"seat": [Vector3(10, 0, -0.55), Vector3(0, 90, 0), 0.22, 0.25, size * 1.7],
		"rear": [Vector3(0, 0, -10), Vector3(0, 180, 0), 0.25, 0.35, size],
		"top": [Vector3(0, 10, 0), Vector3(-90, 90, 0), 0.32, 0.45, size],
	}
	for view: String in views:
		var v: Array = views[view]
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = v[4]
		root.add_child(cam)
		cam.position = focus + v[0]
		cam.rotation_degrees = v[1]
		cam.near = 10.0 - v[2]
		cam.far = 10.0 + v[3]
		cam.make_current()
		var dir: Vector3 = -v[0].normalized()
		var grid := _cabin_grid(cam.position + dir * (10.0 - v[2] + 0.02), dir, v[4])
		root.add_child(grid)
		for f in 5:
			await process_frame
		var path: String = out + "%s%s_cabin_%s.png" % [key, _suffix, view]
		root.get_texture().get_image().save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
		grid.queue_free()
		cam.queue_free()
		await process_frame
	var sw: Dictionary = data.get("steering_wheel", {})
	print(key, " focus ", focus, " steering parts ", sw.get("parts", []).size())


func _cabin_overlay(cabin: Dictionary) -> Node3D:
	var node := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var seat: Vector3 = cabin["seat"]
	var c: Vector3 = cabin["wheel_center"]
	for p: Array in [[seat, Color.GREEN], [c, Color.RED]]:
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			im.surface_set_color(p[1])
			im.surface_add_vertex(p[0] - axis * 0.06)
			im.surface_add_vertex(p[0] + axis * 0.06)
	var n: Vector3 = VehicleModel.steering_axis(cabin)
	var u := Vector3.RIGHT
	var w := n.cross(u)
	var r: float = cabin["wheel_radius"]
	# Yellow: where the wheel is mounted. Orange: where a right-hand-drive
	# model's wheel is cut from.
	var rings := [[c, Color.YELLOW]]
	if cabin.has("wheel_cut_center"):
		rings.append([cabin["wheel_cut_center"], Color.ORANGE])
	for ring: Array in rings:
		var rc: Vector3 = ring[0]
		for i in 48:
			for k in [i, i + 1]:
				var a: float = TAU * k / 48.0
				im.surface_set_color(ring[1])
				im.surface_add_vertex(rc + (u * cos(a) + w * sin(a)) * r)
		im.surface_set_color(ring[1])
		im.surface_add_vertex(rc)
		im.surface_add_vertex(rc + n * 0.25)
	im.surface_end()
	node.mesh = im
	node.material_override = _overlay_material()
	return node


func _cabin_grid(origin: Vector3, view_dir: Vector3, extent: float) -> Node3D:
	var node := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	# The two axes lying in the view plane
	var axes: Array[Vector3] = []
	for a in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		if absf(a.dot(view_dir)) < 0.5:
			axes.append(a)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var labels: Array[Label3D] = []
	for i in 2:
		var a: Vector3 = axes[i]
		var b: Vector3 = axes[1 - i]
		var start := snappedf(origin.dot(a) - extent, 0.1)
		var steps := int(extent * 2.0 / 0.1) + 1
		for s in steps:
			var value := start + s * 0.1
			var major := absf(value / 0.5 - roundf(value / 0.5)) < 0.01
			var color := Color(0.1, 0.3, 1.0) if major else Color(0.2, 0.2, 0.2, 0.55)
			var base := origin - a * origin.dot(a) + a * value
			im.surface_set_color(color)
			im.surface_add_vertex(base - b * extent)
			im.surface_add_vertex(base + b * extent)
			if major:
				var label := Label3D.new()
				label.text = "%s=%.1f" % ["x" if a == Vector3.RIGHT else ("y" if a == Vector3.UP else "z"), value]
				label.no_depth_test = true
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.modulate = Color(0.1, 0.3, 1.0)
				label.outline_size = 6
				label.pixel_size = extent / 900.0
				label.font_size = 28
				label.position = base - b * extent * 0.4
				labels.append(label)
	im.surface_end()
	node.mesh = im
	node.material_override = _overlay_material()
	for label in labels:
		node.add_child(label)
	return node


func _overlay_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 10
	return mat
