extends RefCounted
## Turns a downloaded vehicle .glb into a car-ready body plus four wheels.
##
## Each model is normalised to real size, facing +Z with the tyres on y = 0.
## Wheel triangles are cut out of whatever mesh they're in (many models merge
## wheels into the body), so the wheels can spin and steer.
##
## To add a model, put the .glb in assets/models/cars/real/ and render it with
## tests/view_vehicle.gd. Then read these off the side view (front on the left):
##   length:  real-world length in metres (sets the scale)
##   yaw:     degrees to turn the model so it lies along Z with its front on the left
##   wheels:  [front axle z, rear axle z, wheel centre y, tyre radius], in metres
##            as measured in that view (centre line z = 0, lowest point y = 0)
##   width:   tyre width as a fraction of the radius (default 0.75; buses with
##            twin rear tyres need more)
##   mass:    kg; engine and brakes scale with it

const MODELS := {
	"corolla": {"length": 4.62, "yaw": 0, "wheels": [1.337, -1.369, 0.815, 0.318], "mass": 1300, "handling": {"accel": 4.1, "top_speed": 43.0, "brake": 27.0, "max_steer": 0.52, "steer_response": 2.2, "suspension": 42.0, "compression": 1.5, "relaxation": 2.0, "grip": 3.2, "gears": [1.0, 0.92, 0.84, 0.76, 0.68, 0.6], "ratios": [1.0, 0.82, 0.69, 0.59, 0.51, 0.44], "shift_rpm": 4400.0, "redline": 6500.0}},
	"camry": {"length": 4.81, "yaw": 0, "wheels": [1.445, -1.305, 0.325, 0.325], "mass": 1450, "handling": {"accel": 4.0, "top_speed": 44.0, "brake": 27.0, "max_steer": 0.5, "steer_response": 2.0, "suspension": 40.0, "compression": 1.5, "relaxation": 2.0, "grip": 3.2, "gears": [1.0, 0.92, 0.84, 0.76, 0.68, 0.6], "ratios": [1.0, 0.82, 0.69, 0.59, 0.51, 0.44], "shift_rpm": 4400.0, "redline": 6800.0}},
	"benz_g": {"length": 4.66, "yaw": 0, "wheels": [1.56, -1.271, 0.392, 0.392], "mass": 2400, "handling": {"accel": 3.3, "top_speed": 39.0, "brake": 30.0, "max_steer": 0.43, "steer_response": 1.55, "suspension": 48.0, "compression": 1.7, "relaxation": 2.2, "grip": 3.4, "gears": [1.0, 0.87, 0.76, 0.67, 0.59, 0.52, 0.46], "ratios": [1.0, 0.81, 0.68, 0.58, 0.5, 0.44, 0.39], "shift_rpm": 4300.0, "redline": 6200.0}},
	"bmw_e30": {"length": 4.32, "yaw": 90, "wheels": [1.399, -1.167, 0.292, 0.292], "mass": 1200, "handling": {"accel": 5.4, "top_speed": 48.0, "brake": 30.0, "max_steer": 0.58, "steer_response": 2.8, "suspension": 55.0, "compression": 1.7, "relaxation": 2.3, "grip": 3.6, "roll_influence": 0.05, "gears": [1.0, 0.87, 0.76, 0.66, 0.57], "ratios": [1.0, 0.78, 0.66, 0.57, 0.5], "shift_rpm": 5000.0, "redline": 7000.0}},
	"accord": {"length": 4.67, "yaw": 180, "wheels": [1.364, -1.319, 0.315, 0.315], "wheel_offsets": [Vector3(0, 0.011, 0.124), Vector3(0, 0.011, -0.159), Vector3.ZERO, Vector3.ZERO], "mass": 1400, "handling": {"accel": 4.2, "top_speed": 44.0, "brake": 28.0, "max_steer": 0.49, "steer_response": 2.0, "suspension": 42.0, "compression": 1.5, "relaxation": 2.0, "grip": 3.25, "gears": [1.0, 0.91, 0.82, 0.73, 0.64, 0.56], "ratios": [1.0, 0.81, 0.68, 0.58, 0.5, 0.43], "shift_rpm": 4700.0, "redline": 7000.0}},
	"sprinter": {"length": 6.94, "yaw": 0, "wheels": [2.486, -1.214, 0.492, 0.349], "mass": 2600, "handling": {"accel": 2.6, "top_speed": 34.0, "brake": 22.0, "max_steer": 0.38, "steer_response": 1.25, "suspension": 34.0, "compression": 1.3, "relaxation": 1.9, "grip": 2.8, "roll_influence": 0.04, "gears": [1.0, 0.88, 0.76, 0.66, 0.57], "ratios": [1.0, 0.82, 0.68, 0.57, 0.48], "shift_rpm": 3900.0, "redline": 4700.0}},
	"hiace": {"length": 4.70, "yaw": 180, "wheels": [1.153, -1.166, 0.285, 0.285], "mass": 1900, "handling": {"accel": 3.1, "top_speed": 37.0, "brake": 24.0, "max_steer": 0.43, "steer_response": 1.6, "suspension": 38.0, "compression": 1.4, "relaxation": 1.9, "grip": 3.0, "roll_influence": 0.06, "gears": [1.0, 0.88, 0.76, 0.66, 0.57], "ratios": [1.0, 0.82, 0.68, 0.57, 0.48], "shift_rpm": 4200.0, "redline": 5200.0}},
	"vw_t3": {"length": 4.57, "yaw": 90, "wheels": [1.02, -1.511, 0.321, 0.321], "mass": 1500, "handling": {"accel": 3.6, "top_speed": 36.0, "brake": 23.0, "max_steer": 0.46, "steer_response": 1.8, "suspension": 40.0, "compression": 1.4, "relaxation": 1.9, "grip": 3.0, "gears": [1.0, 0.86, 0.73, 0.61], "ratios": [1.0, 0.8, 0.65, 0.52], "shift_rpm": 4400.0, "redline": 5800.0}},
	"town_bus": {"length": 11.0, "yaw": 270, "wheels": [2.924, -2.152, 0.5, 0.5], "mass": 11000, "width": 1.3, "handling": {"accel": 1.6, "top_speed": 29.0, "brake": 18.0, "max_steer": 0.3, "steer_response": 0.8, "suspension": 29.0, "compression": 1.2, "relaxation": 1.8, "grip": 2.5, "roll_influence": 0.02, "gears": [1.0, 0.88, 0.76, 0.66, 0.57], "ratios": [1.0, 0.82, 0.68, 0.57, 0.48], "shift_rpm": 3300.0, "redline": 3500.0}},
	"coach": {"length": 12.0, "yaw": 0, "wheels": [3.835, -2.645, 0.537, 0.537], "mass": 13000, "width": 1.0, "handling": {"accel": 1.35, "top_speed": 31.0, "brake": 17.0, "max_steer": 0.27, "steer_response": 0.7, "suspension": 27.0, "compression": 1.15, "relaxation": 1.75, "grip": 2.4, "roll_influence": 0.02, "gears": [1.0, 0.88, 0.76, 0.66, 0.57], "ratios": [1.0, 0.82, 0.68, 0.57, 0.48], "shift_rpm": 3200.0, "redline": 3400.0}},
}
const DIR := "res://assets/models/cars/real/"
## Per-model measurements shared with blender/make_mobile_cars.py. The "cabin"
## block (seat and steering wheel) is read from here; see cabin().
const CONFIG_PATH := "res://assets/models/cars/vehicles.json"
const MOBILE_DIR := "res://assets/models/cars/mobile/"

static var _cache := {}
static var _config := {}


## Returns {"body": [[Mesh, Transform3D]], "wheels": [{"center", "radius",
## "front", "parts": [[Mesh, Transform3D]]}], "body_aabb": AABB, "mass": float}.
## Wheel part transforms are relative to the wheel centre.
static func build(key: String, source_dir: String = "") -> Dictionary:
	var cfg: Dictionary = MODELS[key]
	var model_dir := source_dir
	if model_dir.is_empty():
		model_dir = MOBILE_DIR if OS.has_feature("mobile") else DIR
	var model_path := model_dir + key + ".glb"
	# Development builds can still run before the optional Blender asset pass.
	if not ResourceLoader.exists(model_path):
		model_path = DIR + key + ".glb"
	if _cache.has(model_path):
		return _cache[model_path]
	var packed: PackedScene = load(model_path)
	if packed == null:
		push_error("Could not load vehicle model: " + model_path)
		return {}
	var model: Node3D = packed.instantiate()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)

	# Same normalisation as tests/view_vehicle.gd, then drop the tyres onto y = 0
	var box := AABB()
	for i in meshes.size():
		var b: AABB = _chain(meshes[i], model) * meshes[i].get_aabb()
		box = b if i == 0 else box.merge(b)
	var rot := Basis(Vector3.UP, deg_to_rad(cfg["yaw"]))
	var rbox: AABB = Transform3D(rot) * box
	var s: float = cfg["length"] / rbox.size.z
	var c := rbox.get_center()
	var w: Array = cfg["wheels"]
	var radius: float = w[3]
	var to_car := Transform3D(rot.scaled(Vector3.ONE * s),
		Vector3(-c.x * s, -rbox.position.y * s - (w[2] - radius), -c.z * s))

	var centers: Array[Vector3] = []
	for z in [w[0], w[1]]:
		for side in [1.0, -1.0]:
			centers.append(Vector3(side, radius, z))
	# A slightly generous radius captures low-poly tyre triangles whose corners
	# lie just outside the measured circle, especially the rear dual tyres.
	var reach := radius * 1.18
	var tyre_width: float = cfg.get("width", 0.75) * radius

	# Pass 1: outer face of each tyre = furthest |x| inside its cylinder
	var surfaces := []
	# Body bounds come from vertices outside every wheel cylinder.
	var outer: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var body_min := Vector3.INF
	var body_max := -Vector3.INF
	for m: MeshInstance3D in meshes:
		# Sprinter doors have a real imported animation and are kept in the
		# hierarchy for the vehicle rig instead of being baked into the body.
		if key == "sprinter" and _has_named_ancestor(m, model, "porte"):
			continue
		var xf := to_car * _chain(m, model)
		for si in m.mesh.get_surface_count():
			if m.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := m.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pts := PackedVector3Array()
			pts.resize(verts.size())
			var tags := PackedInt32Array()
			tags.resize(verts.size())
			for vi in verts.size():
				var p := xf * verts[vi]
				pts[vi] = p
				var wi := _wheel_at(p, centers, reach)
				tags[vi] = wi
				if wi >= 0:
					outer[wi] = maxf(outer[wi], absf(p.x))
				else:
					body_min = body_min.min(p)
					body_max = body_max.max(p)
			surfaces.append([m, si, arrays, pts, xf, tags])

	var hubs: Array[Vector3] = []
	for i in 4:
		hubs.append(Vector3(centers[i].x * (outer[i] - tyre_width / 2), radius, centers[i].z))

	# Steering wheel: a thin disc around the measured rim (see cabin()), or every
	# triangle of a named mesh when the model has one.
	var cab := cabin(key)
	# Some models paint their windows opaque, which hides the people inside:
	# vehicles.json "glass" names those materials and the alpha to give them
	var glass: Dictionary = _config.get(key, {}).get("glass", {})
	var glass_cache := {}
	var sw_center: Vector3 = cab.get("wheel_center", Vector3.ZERO)
	# Right-hand-drive models: cut the wheel where it is modelled and mount it
	# at wheel_center on the game's driver (+X) side.
	var sw_cut_center: Vector3 = cab.get("wheel_cut_center", sw_center)
	var sw_axis := steering_axis(cab) if not cab.is_empty() else Vector3.BACK
	var sw_reach: float = float(cab.get("wheel_radius", 0.0)) * 1.12 + 0.03
	var sw_depth: float = float(cab.get("wheel_depth", 0.07))
	var sw_node: String = str(cab.get("wheel_node", ""))
	var sw_cut: bool = str(cab.get("wheel_source", "")) == "cut"
	var sw_parts := []

	# Pass 2: classify by triangle centre. Requiring all three vertices to fit
	# the cylinder clipped broad, low-poly tread faces and left rear tyres partial.
	var body := []
	var wheel_parts := [[], [], [], []]
	for entry in surfaces:
		var m: MeshInstance3D = entry[0]
		var arrays: Array = entry[2]
		var pts: PackedVector3Array = entry[3]
		var xf: Transform3D = entry[4]
		var tags: PackedInt32Array = entry[5]
		for vi in tags.size():
			if tags[vi] >= 0 and absf(pts[vi].x) < outer[tags[vi]] - tyre_width:
				tags[vi] = -1
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(pts.size()))
		var groups := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
		var whole_mesh_is_steering := sw_cut and not sw_node.is_empty() and _has_named_ancestor(m, model, sw_node.to_lower())
		for t in range(0, indices.size() - 2, 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c3 := indices[t + 2]
			if sw_cut and (whole_mesh_is_steering or (sw_node.is_empty()
					and _in_disc(pts[a], sw_cut_center, sw_axis, sw_reach, sw_depth)
					and _in_disc(pts[b], sw_cut_center, sw_axis, sw_reach, sw_depth)
					and _in_disc(pts[c3], sw_cut_center, sw_axis, sw_reach, sw_depth))):
				var steering_group: PackedInt32Array = groups[5]
				steering_group.append_array(PackedInt32Array([a, b, c3]))
				groups[5] = steering_group
				continue
			var centroid := (pts[a] + pts[b] + pts[c3]) / 3.0
			var g := _wheel_at(centroid, centers, reach)
			# The centroid alone can assign large fender/body triangles to a
			# wheel, making those panels rotate with it. Keep the wheel cut local
			# to the tyre envelope while allowing low-poly tread corners to extend
			# beyond the measured radius.
			if g >= 0:
				var radial_limit: float = centers[g].y * 1.3
				for vertex_index in [a, b, c3]:
					var vertex := pts[vertex_index]
					if Vector2(vertex.y - centers[g].y, vertex.z - centers[g].z).length() > radial_limit:
						g = -1
						break
			if g >= 0 and absf(centroid.x) < outer[g] - tyre_width * 0.45:
				g = -1
			if g < 0:
				g = 4
			var group: PackedInt32Array = groups[g]
			group.push_back(a)
			group.push_back(b)
			group.push_back(c3)
			groups[g] = group
		var material := _material(m, entry[1])
		if material != null and glass.has(material.resource_name):
			if not glass_cache.has(material):
				glass_cache[material] = _see_through(material, float(glass[material.resource_name]))
			material = glass_cache[material]
		for g in 6:
			if groups[g].is_empty():
				continue
			# One VW T3 body-painted triangle falls inside the front wheel envelope
			# in both asset variants. It was rotating with the tyre as a yellow
			# paint shard; drop only that stray face from the extracted wheel.
			if key == "vw_t3" and g < 4 and material != null and material.resource_name == "Material_body":
				continue
			var mesh := _sub_mesh(arrays, groups[g], material)
			if g == 5:
				sw_parts.append([mesh, Transform3D(Basis.IDENTITY, -sw_cut_center) * xf])
			elif g == 4:
				body.append([mesh, xf])
			else:
				var wheel_transform := Transform3D(Basis.IDENTITY, -hubs[g]) * xf
				wheel_transform.origin -= cfg.get("wheel_offsets", [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])[g]
				wheel_parts[g].append([mesh, wheel_transform])
	model.free()
	var all_body := AABB(body_min, body_max - body_min)

	var wheels := []
	for i in 4:
		wheels.append({"center": hubs[i], "radius": radius, "front": i < 2, "parts": wheel_parts[i]})
	var result := {"body": body, "wheels": wheels, "body_aabb": all_body, "mass": float(cfg["mass"]), "handling": cfg.get("handling", {}),
		"source_path": model_path, "source_transform": to_car}
	if not cab.is_empty():
		if str(cab.get("wheel_source", "")) == "added":
			sw_parts = [[_low_poly_steering_wheel(cab), Transform3D.IDENTITY]]
		result["driver_seat"] = cab["seat"]
		result["steering_wheel"] = {"center": sw_center, "axis": sw_axis, "radius": float(cab["wheel_radius"]),
			"max_turn": deg_to_rad(float(cab.get("wheel_turn_deg", 240.0))), "parts": sw_parts}
	_cache[model_path] = result
	return result


## Seat and steering-wheel measurements for `key` from vehicles.json "cabin",
## with arrays turned into Vector3. Empty if the model has none. Car-local
## metres, the same space as build(): +Z forward, +X the driver's (door) side,
## y = 0 where the tyres touch the road.
static func cabin(key: String) -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config = parsed if parsed is Dictionary else {"_invalid": true}
	var entry: Dictionary = _config.get(key, {})
	var raw: Dictionary = entry.get("cabin", {})
	var out := raw.duplicate()
	for field in ["seat", "wheel_center", "wheel_cut_center"]:
		if raw.has(field):
			var v: Array = raw[field]
			out[field] = Vector3(v[0], v[1], v[2])
	return out


## Unit rotation axis of the steering wheel, pointing from the rim towards the
## driver. wheel_tilt is the rim plane's angle from vertical: 0 = upright rim
## (horizontal column), 90 = flat rim (vertical column).
static func steering_axis(cab: Dictionary) -> Vector3:
	var tilt := deg_to_rad(float(cab.get("wheel_tilt", 25.0)))
	return Vector3(0.0, sin(tilt), -cos(tilt))


static func _in_disc(p: Vector3, center: Vector3, axis: Vector3, reach: float, depth: float) -> bool:
	var d := p - center
	var along := d.dot(axis)
	return absf(along) <= depth and (d - axis * along).length() <= reach


## Fallback rim + three spokes, centred on the origin, facing `axis`.
static func _low_poly_steering_wheel(cab: Dictionary) -> ArrayMesh:
	var axis := steering_axis(cab)
	var u := Vector3.RIGHT
	var w := axis.cross(u)
	var r: float = cab["wheel_radius"]
	var tube := maxf(0.014, r * 0.08)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := 24
	var sides := 6
	for i in ring:
		for j in sides:
			var quad := []
			for k in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var a: float = TAU * k[0] / ring
				var b: float = TAU * k[1] / sides
				var radial := u * cos(a) + w * sin(a)
				quad.append(radial * (r + tube * cos(b)) + axis * tube * sin(b))
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(quad[idx])
	for angle: float in [PI * 0.5, PI * 1.17, PI * 1.83]:
		var dir := u * cos(angle) + w * sin(angle)
		var side := dir.cross(axis).normalized() * tube * 0.8
		var p0 := axis * 0.02
		var p1 := dir * r
		for tri in [[p0 - side, p1 - side, p1 + side], [p0 - side, p1 + side, p0 + side]]:
			for v in tri:
				st.add_vertex(v)
			for v in [tri[0], tri[2], tri[1]]:
				st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.065)
	mat.roughness = 0.7
	mesh.surface_set_material(0, mat)
	return mesh


## Index of the wheel whose cylinder (axle along X) contains `p`, or -1.
## `centers` hold the side (+1/-1) in x, since the track isn't known yet.
static func _wheel_at(p: Vector3, centers: Array[Vector3], reach: float) -> int:
	if p.y > centers[0].y + reach:
		return -1
	for i in centers.size():
		var cw := centers[i]
		if signf(p.x) == cw.x and Vector2(p.y - cw.y, p.z - cw.z).length() <= reach:
			return i
	return -1


static func _chain(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != root:
		t = n.transform * t
		n = n.get_parent()
	return t


static func _has_named_ancestor(n: Node, root: Node, token: String) -> bool:
	while n != root:
		if token in str(n.name).to_lower():
			return true
		n = n.get_parent()
	return false


## A copy of an opaque window material that lets the cabin show through.
static func _see_through(material: Material, alpha: float) -> Material:
	if not material is BaseMaterial3D:
		return material
	var glass := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = alpha
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glass


static func _material(m: MeshInstance3D, surface: int) -> Material:
	if m.material_override:
		return m.material_override
	var override := m.get_surface_override_material(surface)
	return override if override else m.mesh.surface_get_material(surface)


static func _sub_mesh(arrays: Array, indices: PackedInt32Array, material: Material) -> ArrayMesh:
	var copy := arrays.duplicate()
	copy[Mesh.ARRAY_INDEX] = indices
	# Custom channels and skinning need extra format flags and aren't used here
	for channel in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3,
			Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		copy[channel] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy)
	mesh.surface_set_material(0, material)
	return mesh
