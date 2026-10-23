extends SceneTree
## Audits extracted tire meshes for every model in both the desktop and mobile
## asset sets. Run: godot --headless --path . --script tests/vehicle_tires_test.gd

const VehicleModel = preload("res://scripts/vehicle_model.gd")
const ASSET_DIRS := [VehicleModel.DIR, VehicleModel.MOBILE_DIR]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []
	for asset_dir in ASSET_DIRS:
		for key in VehicleModel.MODELS:
			VehicleModel._cache.clear()
			var data: Dictionary = VehicleModel.build(key, asset_dir)
			if data.is_empty():
				failures.append("%s/%s: model failed to load" % [asset_dir, key])
				continue
			var cfg: Dictionary = VehicleModel.MODELS[key]
			var expected_radius: float = cfg["wheels"][3]
			var actual_wheels: Array = data["wheels"]
			if actual_wheels.size() != 4:
				failures.append("%s/%s: expected 4 wheel mounts, got %d" % [asset_dir, key, actual_wheels.size()])
				continue
			for i in actual_wheels.size():
				var wheel: Dictionary = actual_wheels[i]
				var tris := 0
				var min_radius := INF
				var max_radius := 0.0
				var tire_vertices := 0
				var local_vertices := 0
				var min_axle := INF
				var max_axle := -INF
				for part in wheel["parts"]:
					var mesh: Mesh = part[0]
					var transform: Transform3D = part[1]
					var arrays: Array = mesh.surface_get_arrays(0)
					tris += mesh.surface_get_array_index_len(0) / 3
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
					if indices.is_empty():
						indices = PackedInt32Array(range(vertices.size()))
					for index in indices:
						var vertex: Vector3 = vertices[index]
						var point: Vector3 = transform * vertex
						var radial := Vector2(point.y, point.z).length()
						tire_vertices += 1
						min_radius = minf(min_radius, radial)
						max_radius = maxf(max_radius, radial)
						min_axle = minf(min_axle, point.x)
						max_axle = maxf(max_axle, point.x)
				var label := "%s/%s wheel %d" % [asset_dir.get_file(), key, i]
				if tris < 20:
					failures.append("%s: suspiciously little tire geometry (%d triangles)" % [label, tris])
				if absf(wheel["radius"] - expected_radius) > 0.001:
					failures.append("%s: runtime radius %.3f != configured %.3f" % [label, wheel["radius"], expected_radius])
				if tire_vertices < 60 or max_radius < expected_radius * 0.75 or min_radius > expected_radius * 0.65:
					failures.append("%s: extracted tire ring looks incomplete (radii %.3f..%.3f, expected %.3f)" % [label, min_radius, max_radius, expected_radius])
				if max_radius > expected_radius * 1.35:
					failures.append("%s: non-tire geometry remains attached (radial extent %.3f, tire radius %.3f)" % [label, max_radius, expected_radius])
				if min_axle == INF or max_axle - min_axle < expected_radius * 0.15:
					failures.append("%s: tire has no useful axle width" % label)
				print("%s %s wheel %d: %d tris, referenced vertices %d, radial %.3f..%.3f m, width %.3f m" % [
					asset_dir.get_file(), key, i, tris, tire_vertices, min_radius, max_radius, max_axle - min_axle
				])
			var wheels: Array = data["wheels"]
			var expected_axles: Array = cfg["wheels"]
			for i in 4:
				var expected_z: float = expected_axles[0] if i < 2 else expected_axles[1]
				if absf(wheels[i]["center"].z - expected_z) > 0.01:
					failures.append("%s/%s wheel %d: axle misplaced at z=%.3f (expected %.3f)" % [asset_dir.get_file(), key, i, wheels[i]["center"].z, expected_z])
				var expected_side := 1.0 if i % 2 == 0 else -1.0
				if wheels[i]["center"].x * expected_side <= 0.0:
					failures.append("%s/%s wheel %d: side placement has the wrong sign" % [asset_dir.get_file(), key, i])
				if absf(wheels[i]["center"].y - expected_radius) > 0.01:
					failures.append("%s/%s wheel %d: hub height does not match configured radius" % [asset_dir.get_file(), key, i])
				if bool(wheels[i]["front"]) != (i < 2):
					failures.append("%s/%s wheel %d: steering axle classification is wrong" % [asset_dir.get_file(), key, i])
	if failures.is_empty():
		print("Vehicle tire audit passed for all 10 models in both asset sets.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
