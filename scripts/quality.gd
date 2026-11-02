extends RefCounted
## Graphics and crowd presets. Phones default to Low, desktops to High; the
## start menu's GRAPHICS choice is saved in user://graphics.json and wins over
## that. Override both with `godot --path . -- --quality=low` (or medium / high).

const PRESETS := {
	"low": {
		"pedestrians": 12,
		"cars": 6,
		"traffic": 1,
		"ragdolls": 8,
		# One shadow map near the player: cheap, and shadows are most of what
		# makes the city look solid
		"shadows": true,
		"shadow_distance": 35.0,
		"shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL,
		"draw_distance": 250.0,
		# 3D is drawn at this fraction of the screen resolution and scaled up;
		# the HUD and touch controls stay sharp. 2x MSAA is nearly free on
		# phone GPUs and removes the jagged edges.
		"render_scale": 0.75,
		"msaa": Viewport.MSAA_2X,
		"glow": false,
	},
	"medium": {
		"pedestrians": 20,
		"cars": 9,
		"traffic": 2,
		"ragdolls": 15,
		"shadows": true,
		"shadow_distance": 60.0,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"draw_distance": 600.0,
		"render_scale": 0.85,
		"msaa": Viewport.MSAA_2X,
	},
	"high": {
		"pedestrians": 30,
		"cars": 13,
		"traffic": 4,
		"ragdolls": 25,
		"shadows": true,
		"shadow_distance": 120.0,
		"draw_distance": 1500.0,
		"render_scale": 1.0,
		"msaa": Viewport.MSAA_4X,
	},
	"performance": {
		"pedestrians": 16,
		"cars": 9,
		"traffic": 2,
		"ragdolls": 12,
		"shadows": true,
		"shadow_distance": 65.0,
		"draw_distance": 650.0,
		"render_scale": 0.8,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"msaa": Viewport.MSAA_2X,
	},
}


const PREF_PATH := "user://graphics.json"
## The choices offered in the start menu
const MENU_CHOICES := ["low", "medium", "high"]


static func current_name() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			var picked := arg.trim_prefix("--quality=")
			if PRESETS.has(picked):
				return picked
	var saved := saved_name()
	if saved != "":
		return saved
	return default_name()


static func default_name() -> String:
	return "low" if OS.has_feature("mobile") else "high"


## The preset picked in the start menu, or "" when none was saved.
static func saved_name() -> String:
	if not FileAccess.file_exists(PREF_PATH):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREF_PATH))
	var picked := str(parsed.get("quality", "")) if parsed is Dictionary else ""
	return picked if PRESETS.has(picked) else ""


static func save_name(preset: String) -> void:
	var file := FileAccess.open(PREF_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"quality": preset}))


static func current() -> Dictionary:
	return PRESETS[current_name()]
