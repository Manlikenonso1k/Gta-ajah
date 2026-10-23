extends RefCounted
## Versioned runtime vehicle save data. The project and imported assets stay read-only.

static var SAVE_PATH := "user://vehicle_state.json"
static var TEMP_PATH := "user://vehicle_state.json.tmp"
const VERSION := 1


static func load_states() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("version", -1)) != VERSION:
		push_warning("Vehicle save was unreadable or used an unsupported version; default spawns will be used")
		return {}
	var vehicles: Variant = parsed.get("vehicles", {})
	return vehicles if vehicles is Dictionary else {}


static func save_states(vehicles: Dictionary) -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write vehicle save file")
		return false
	file.store_string(JSON.stringify({"version": VERSION, "vehicles": vehicles}))
	file.flush()
	file.close()
	var source := ProjectSettings.globalize_path(TEMP_PATH)
	var destination := ProjectSettings.globalize_path(SAVE_PATH)
	var error := DirAccess.rename_absolute(source, destination)
	if error != OK:
		DirAccess.remove_absolute(destination)
		error = DirAccess.rename_absolute(source, destination)
	if error != OK:
		push_warning("Could not replace vehicle save file: %s" % error_string(error))
		return false
	return true


static func transform_from_state(state: Variant, fallback: Transform3D) -> Transform3D:
	if not state is Dictionary:
		return fallback
	var position: Variant = state.get("position", [])
	var rotation: Variant = state.get("rotation", [])
	if not position is Array or position.size() != 3 or not rotation is Array or rotation.size() != 3:
		return fallback
	var p := Vector3(float(position[0]), float(position[1]), float(position[2]))
	var r := Vector3(float(rotation[0]), float(rotation[1]), float(rotation[2]))
	if not p.is_finite() or not r.is_finite() or p.y < -0.5 or p.y > 20.0 or absf(p.x) > 240.0 or absf(p.z) > 240.0:
		return fallback
	return Transform3D(Basis.from_euler(r), p)


static func state_from_transform(xform: Transform3D) -> Dictionary:
	var position := xform.origin
	var rotation := xform.basis.get_euler()
	return {"position": [position.x, position.y, position.z], "rotation": [rotation.x, rotation.y, rotation.z]}
