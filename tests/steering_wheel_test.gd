extends SceneTree
## Checks the seat and steering-wheel data and the cut-out steering wheels of
## all 10 vehicle models, in both the desktop and mobile asset sets.
## Run: godot --headless --path . --script tests/steering_wheel_test.gd

const VehicleModel = preload("res://scripts/vehicle_model.gd")
const SteeringWheel = preload("res://scripts/steering_wheel.gd")
const ASSET_DIRS := [VehicleModel.DIR, VehicleModel.MOBILE_DIR]

var _failures: Array[String] = []


func _initialize() -> void:
	# Safety net: never hang the shared tool lock
	create_timer(120.0).timeout.connect(func():
		push_error("steering_wheel_test timed out")
		quit(2))
	_run.call_deferred()


func _fail(message: String) -> void:
	_failures.append(message)


func _run() -> void:
	for asset_dir: String in ASSET_DIRS:
		for key: String in VehicleModel.MODELS:
			VehicleModel._cache.clear()
			_check_model(key, asset_dir)
	if _failures.is_empty():
		print("Steering wheel check passed for all 10 models in both asset sets.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check_model(key: String, asset_dir: String) -> void:
	var label := "%s/%s" % [asset_dir.trim_suffix("/").get_file(), key]
	var cab: Dictionary = VehicleModel.cabin(key)
	for field in ["seat", "wheel_center", "wheel_radius", "wheel_tilt", "wheel_turn_deg", "wheel_source"]:
		if not cab.has(field):
			_fail("%s: vehicles.json cabin is missing %s" % [label, field])
			return
	var data: Dictionary = VehicleModel.build(key, asset_dir)
	var sw: Dictionary = data.get("steering_wheel", {})
	if sw.is_empty() or sw["parts"].is_empty():
		_fail("%s: no steering-wheel mesh" % label)
		return
	var seat: Vector3 = data["driver_seat"]
	var center: Vector3 = sw["center"]
	var axis: Vector3 = sw["axis"]
	var radius: float = sw["radius"]
	var box: AABB = data["body_aabb"].grow(0.05)
	if not box.has_point(seat) or not box.has_point(center):
		_fail("%s: seat %s or wheel %s lies outside the body %s" % [label, seat, center, box])
	# Driver geometry: wheel ahead of and above the hips, in line with the seat,
	# on the driver's (+X) side.
	if center.z - seat.z < 0.25 or center.z - seat.z > 0.75:
		_fail("%s: wheel is %.2f m ahead of the seat (expected 0.25..0.75)" % [label, center.z - seat.z])
	if center.y - seat.y < 0.15 or center.y - seat.y > 0.5:
		_fail("%s: wheel is %.2f m above the seat (expected 0.15..0.5)" % [label, center.y - seat.y])
	if absf(center.x - seat.x) > 0.1 or center.x < 0.2:
		_fail("%s: wheel x %.2f / seat x %.2f not on the driver's side in line" % [label, center.x, seat.x])
	if radius < 0.14 or radius > 0.3:
		_fail("%s: implausible wheel radius %.2f" % [label, radius])
	if absf(axis.length() - 1.0) > 0.001 or axis.z > 0.0:
		_fail("%s: steering axis %s should be unit length and point back at the driver" % [label, axis])

	# Cut-out geometry: forms a rim of about the measured radius around the
	# pivot, within the cut disc.
	var cut_center: Vector3 = cab.get("wheel_cut_center", center)
	var max_radial := 0.0
	var rim_vertices := 0
	var tris := 0
	for part in sw["parts"]:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		var used := _used_vertices(mesh)
		tris += used.size() / 3
		for v: Vector3 in used:
			var p := xf * v
			var along := p.dot(axis)
			var radial := (p - axis * along).length()
			max_radial = maxf(max_radial, radial)
			if radial > radius * 0.8 and radial < radius * 1.2:
				rim_vertices += 1
			if absf(along) > float(cab.get("wheel_depth", 0.07)) + 0.06 or radial > radius * 1.3:
				_fail("%s: steering-wheel vertex %s is far outside the wheel disc" % [label, p])
				return
	if tris < 24 or rim_vertices < 12:
		_fail("%s: steering wheel too small (%d triangles, %d rim vertices)" % [label, tris, rim_vertices])
	if max_radial < radius * 0.8:
		_fail("%s: steering-wheel geometry reaches only %.3f m of the %.3f m rim" % [label, max_radial, radius])

	# No rim left behind in the body: count body vertices on the rim ring.
	var leftover := 0
	if str(cab["wheel_source"]) == "cut":
		for part in data["body"]:
			var mesh: Mesh = part[0]
			var xf: Transform3D = part[1]
			for v: Vector3 in _used_vertices(mesh):
				var d: Vector3 = xf * v - cut_center
				var along := d.dot(axis)
				var radial := (d - axis * along).length()
				if absf(along) < 0.02 and radial > radius * 0.9 and radial < radius * 1.05:
					leftover += 1
		if leftover > maxi(8, rim_vertices / 10):
			_fail("%s: %d rim vertices were left in the body (cut has %d)" % [label, leftover, rim_vertices])

	# Rotation: full lock turns the rim by wheel_turn_deg about the axis.
	var holder := Node3D.new()
	root.add_child(holder)
	var pivot := SteeringWheel.attach(holder, data)
	var rim_point := center + axis.cross(Vector3.RIGHT).normalized() * radius
	var local := rim_point - center
	SteeringWheel.update(pivot, 0.5, 0.5)
	var turned: Vector3 = pivot.basis * local
	var expected := deg_to_rad(float(cab["wheel_turn_deg"]))
	var got := local.signed_angle_to(turned, axis)
	var wrapped := wrapf(expected, -PI, PI)
	if absf(wrapf(got - wrapped, -PI, PI)) > 0.01 or absf(turned.length() - local.length()) > 0.001:
		_fail("%s: full lock turned the rim %.1f deg, expected %.1f" % [label, rad_to_deg(got), rad_to_deg(wrapped)])
	SteeringWheel.update(pivot, 0.0, 0.5)
	if not pivot.basis.is_equal_approx(Basis.IDENTITY):
		_fail("%s: centred steering should leave the wheel unrotated" % label)
	holder.free()
	print("%s: %s wheel, %d tris, %d rim verts, leftover %d, reach %.3f/%.3f m, seat %s, wheel %s" % [
		label, cab["wheel_source"], tris, rim_vertices, leftover, max_radial, radius, seat, center])


## Vertices referenced by the mesh's triangles, one per corner. Cut meshes
## share their source's whole vertex array and differ only in their indices.
func _used_vertices(mesh: Mesh) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if arrays[Mesh.ARRAY_INDEX] == null:
		return verts
	var out := PackedVector3Array()
	for i: int in arrays[Mesh.ARRAY_INDEX]:
		out.append(verts[i])
	return out
