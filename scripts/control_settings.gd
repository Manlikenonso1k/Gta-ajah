extends RefCounted
## Player control settings, saved in user://controls.json:
##   layout       on-screen button positions and sizes, edited in the game
##                (scripts/controls_editor.gd): name -> {x, y, s}, with x and
##                y as fractions of the screen and s a size multiplier
##   opacity      on-screen controls, 0.2..1
##   steering     "stick" (joystick) or "tilt" (turn the phone like a wheel,
##                with GAS and BRAKE pedals)
##   tilt_sensitivity, invert_tilt
##   gyro_camera  aim the camera by turning the phone (not while tilt-steering)
##   gyro_sensitivity, invert_gyro_x, invert_gyro_y
##   look_sensitivity  touch drag and mouse look
##
##   ControlSettings.get_value("steering")      ControlSettings.set_value("opacity", 0.6)

## A static var so tests can point it at their own file
static var PATH := "user://controls.json"
const DEFAULTS := {
	"layout": {},
	"opacity": 0.55,
	"steering": "stick",
	"tilt_sensitivity": 1.0,
	"invert_tilt": false,
	"gyro_camera": false,
	"gyro_sensitivity": 1.0,
	"invert_gyro_x": false,
	"invert_gyro_y": false,
	"look_sensitivity": 1.0,
}

static var _data := {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = DEFAULTS.duplicate(true)
		if FileAccess.file_exists(PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if parsed is Dictionary:
				for key: String in DEFAULTS:
					if parsed.has(key) and typeof(parsed[key]) == typeof(DEFAULTS[key]):
						_data[key] = parsed[key]
					elif parsed.has(key) and DEFAULTS[key] is float and (parsed[key] is int or parsed[key] is float):
						_data[key] = float(parsed[key])
	return _data


static func get_value(key: String) -> Variant:
	return data().get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	data()[key] = value
	save()


static func save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data()))


## Back to the defaults, keeping nothing. Used by tests and "Reset all".
static func reset() -> void:
	_data = DEFAULTS.duplicate(true)
	_loaded = true
	save()
