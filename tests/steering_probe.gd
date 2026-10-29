extends SceneTree
## Throwaway probe (vehicles, Phase 2): body materials of every model, to find
## windows that are opaque.

const VehicleModel = preload("res://scripts/vehicle_model.gd")


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2))
	_run.call_deferred()


func _run() -> void:
	for key: String in VehicleModel.MODELS:
		var data: Dictionary = VehicleModel.build(key)
		var seen := {}
		for part in data["body"]:
			var mesh: Mesh = part[0]
			var mat := mesh.surface_get_material(0)
			if mat == null or seen.has(mat):
				continue
			seen[mat] = true
			var line := "%s | %s" % [key, mat.resource_name]
			if mat is BaseMaterial3D:
				var m := mat as BaseMaterial3D
				line += " | albedo %s | tex %s | transparency %d | tris %d" % [m.albedo_color, m.albedo_texture != null, m.transparency, mesh.surface_get_array_index_len(0) / 3]
			print(line)
	quit()
