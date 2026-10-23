extends Control
## Lightweight, data-driven driving cluster. RPM follows the vehicle's
## simplified automatic transmission model and current gear ratio.

const STYLES := {
	"corolla": {"name": "TOYOTA COROLLA", "sub": "COMPACT  /  16V", "accent": Color("77d9c5"), "max_speed": 220.0, "rpm_max": 8000.0, "redline": 6500.0, "design": "clean", "size": 23, "font": "Avenir Next", "weight": 500, "italic": false},
	"camry": {"name": "TOYOTA CAMRY", "sub": "V6  /  EXECUTIVE", "accent": Color("78d8ee"), "max_speed": 260.0, "rpm_max": 8000.0, "redline": 6800.0, "design": "digital", "size": 25, "font": "Arial", "weight": 700, "italic": false},
	"benz_g": {"name": "MERCEDES-BENZ  G", "sub": "G-CLASS  /  4MATIC", "accent": Color("d7bb79"), "max_speed": 240.0, "rpm_max": 7000.0, "redline": 6200.0, "design": "luxury", "size": 24, "font": "Georgia", "weight": 700, "italic": false},
	"bmw_e30": {"name": "BMW  /  E30", "sub": "CLASSIC SPORT  /  1987", "accent": Color("ec5549"), "max_speed": 240.0, "rpm_max": 8000.0, "redline": 7000.0, "design": "classic", "size": 27, "font": "Arial", "weight": 700, "italic": true},
	"accord": {"name": "HONDA ACCORD", "sub": "VTEC  /  TOURING", "accent": Color("e98b68"), "max_speed": 240.0, "rpm_max": 8000.0, "redline": 7000.0, "design": "sport", "size": 23, "font": "Arial", "weight": 700, "italic": true},
	"sprinter": {"name": "MERCEDES SPRINTER", "sub": "DIESEL  /  CARGO", "accent": Color("c2d1c9"), "max_speed": 180.0, "rpm_max": 6000.0, "redline": 4700.0, "design": "cargo", "size": 21, "font": "Roboto Condensed", "weight": 600, "italic": false},
	"hiace": {"name": "TOYOTA HIACE", "sub": "COMMUTER  /  DIESEL", "accent": Color("f1c86e"), "max_speed": 180.0, "rpm_max": 6500.0, "redline": 5200.0, "design": "shuttle", "size": 22, "font": "Arial", "weight": 600, "italic": false},
	"vw_t3": {"name": "VW  T3  DANFO", "sub": "LAGOS ROAD SERVICE", "accent": Color("ffd447"), "max_speed": 160.0, "rpm_max": 7000.0, "redline": 5800.0, "design": "danfo", "size": 25, "font": "Arial Black", "weight": 800, "italic": false},
	"town_bus": {"name": "CITY TRANSIT", "sub": "TOWN BUS  /  DIESEL", "accent": Color("efb53b"), "max_speed": 130.0, "rpm_max": 4500.0, "redline": 3500.0, "design": "transit", "size": 23, "font": "Roboto Condensed", "weight": 700, "italic": false},
	"coach": {"name": "INTERCITY COACH", "sub": "EXPRESS  /  DIESEL", "accent": Color("9fc9e7"), "max_speed": 150.0, "rpm_max": 4500.0, "redline": 3400.0, "design": "touring", "size": 22, "font": "Georgia", "weight": 600, "italic": false},
}

static var _name_font_cache := {}
var car: Node = null
var touch_mode := false
var touch_controls = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func set_vehicle(current: Node) -> void:
	car = current
	visible = car != null
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if car == null:
		return
	var viewport: Vector2 = size
	var style: Dictionary = STYLES.get(car.model, STYLES["corolla"])
	var accent: Color = style["accent"]
	var font := ThemeDB.fallback_font
	var speed: float = car.linear_velocity.length() * 3.6
	var rpm: float = car.estimated_rpm
	var radius := minf(88.0, minf(viewport.x * 0.105, viewport.y * 0.125))
	var center_y := viewport.y - radius - 14.0
	var speed_center := Vector2(viewport.x * 0.51, center_y)
	var rpm_center := Vector2(viewport.x * 0.72, center_y)
	if touch_mode:
		radius = minf(radius, viewport.x * 0.105)
		speed_center.x = viewport.x * 0.45
		rpm_center.x = viewport.x * 0.67
	elif viewport.x < 700.0:
		speed_center.x = viewport.x * 0.49
		rpm_center.x = viewport.x * 0.69
	_draw_gauge(speed_center, radius, speed, float(style["max_speed"]), "KM/H", "%.0f" % speed, style, font, false)
	_draw_gauge(rpm_center, radius, rpm, float(style["rpm_max"]), "RPM", "%.1f" % (rpm / 1000.0), style, font, true)

	var name_size: int = int(style["size"])
	var design: String = style["design"]
	var name_font: Font = _vehicle_name_font(style)
	var name_y := viewport.y - maxf(56.0, viewport.y * 0.09)
	if touch_mode and touch_controls != null:
		var safe: Rect2 = touch_controls.safe_rect()
		var unit: float = touch_controls._unit
		var stick_top := safe.end.y - unit * 3.4
		name_y = stick_top - name_size - 18.0
	var title: String = style["name"]
	if design == "danfo":
		title = "✦  " + title + "  ✦"
	if design == "classic":
		title = "BMW   /   E30"
	elif design == "sport":
		title = "HONDA   /   ACCORD"
	elif design == "cargo":
		title = "SPRINTER   /   CARGO"
	elif design == "shuttle":
		title = "HIACE   |   COMMUTER"
	# A restrained plate keeps the name clear against either paint or road.
	draw_rect(Rect2(18.0, name_y - name_size - 10.0, minf(viewport.x * 0.34, 340.0), name_size + 44.0), Color(0.025, 0.035, 0.04, 0.76), true)
	draw_rect(Rect2(18.0, name_y - name_size - 10.0, 4.0, name_size + 44.0), accent)
	draw_string(name_font, Vector2(34.0, name_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color.WHITE)
	var subtitle: String = style["sub"]
	draw_string(font, Vector2(35.0, name_y + 22.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)


func _vehicle_name_font(style: Dictionary) -> Font:
	var key := "%s:%d:%s" % [style["font"], style["weight"], style["italic"]]
	if not _name_font_cache.has(key):
		var font := SystemFont.new()
		font.font_names = PackedStringArray([style["font"], "sans-serif"])
		font.font_weight = style["weight"]
		font.font_italic = style["italic"]
		_name_font_cache[key] = font
	return _name_font_cache[key]


func _draw_gauge(center: Vector2, radius: float, value: float, maximum: float,
		unit: String, readout: String, style: Dictionary, font: Font, tachometer: bool) -> void:
	var accent: Color = style["accent"]
	var design: String = style["design"]
	var start := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	var ratio := clampf(value / maximum, 0.0, 1.0)
	draw_circle(center, radius + 13.0, Color(0.015, 0.025, 0.03, 0.76))
	draw_arc(center, radius + 13.0, 0.0, TAU, 64, Color(accent, 0.36), 1.5, true)
	draw_arc(center, radius, start, start + sweep, 64, Color(0.42, 0.47, 0.48, 0.48), 5.0, true)
	draw_arc(center, radius, start, start + sweep * ratio, 64, accent, 5.0 if design != "luxury" else 3.0, true)
	var redline: float = float(style["redline"])
	if tachometer:
		var redline_start := start + sweep * clampf(redline / maximum, 0.0, 1.0)
		draw_arc(center, radius, redline_start, start + sweep, 28, Color(0.94, 0.27, 0.19, 0.88), 6.0, true)
	if design in ["luxury", "shuttle", "touring"]:
		draw_arc(center, radius - 8.0, start, start + sweep, 64, Color(accent, 0.30), 1.0, true)
	if design == "sport":
		draw_arc(center, radius + 5.0, start + sweep * 0.58, start + sweep * 0.83, 18, Color(0.94, 0.27, 0.19, 0.9), 3.0, true)
	if design == "cargo":
		draw_arc(center, radius - 5.0, start, start + sweep, 48, Color(accent, 0.2), 1.0, true)
	var tick_count := 14 if design == "touring" else (12 if design in ["classic", "shuttle"] else (8 if design in ["sport", "transit"] else 10))
	for i in tick_count + 1:
		var t := float(i) / float(tick_count)
		var angle := start + sweep * t
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius - 1.0)
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - (11.0 if i % 2 == 0 else 6.0))
		var tick_color := Color(0.98, 0.32, 0.22) if tachometer and t >= redline / maximum else Color.WHITE
		if design == "transit" and i % 2 == 0:
			tick_color = accent
		if design == "danfo" and i % 2 == 1:
			tick_color = Color("7be495")
		draw_line(inner, outer, tick_color, 1.6 if i % 2 == 0 else 1.0, true)
		if i % 2 == 0:
			var label_value := int(roundf(maximum * t / (1000.0 if tachometer else 20.0)))
			var label_pos := center + Vector2(cos(angle), sin(angle)) * (radius - 24.0)
			var label_text := str(label_value) if tachometer else str(label_value * 20)
			var label_size := 10 if design == "commercial" else 11
			draw_string(font, label_pos + Vector2(-17.0, 4.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, 34.0, label_size, Color(0.83, 0.87, 0.88))
	var needle_angle := start + sweep * ratio
	var tip := center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 19.0)
	draw_line(center, tip, Color(0.97, 0.97, 0.91), 2.5, true)
	draw_circle(center, 5.0, accent)
	var number_size := 25 if design == "digital" else (22 if design in ["danfo", "transit"] else 18)
	draw_string(font, center + Vector2(-35.0, 27.0), readout, HORIZONTAL_ALIGNMENT_CENTER, 70.0, number_size, Color.WHITE)
	draw_string(font, center + Vector2(-32.0, 43.0), unit, HORIZONTAL_ALIGNMENT_CENTER, 64.0, 10, accent)
