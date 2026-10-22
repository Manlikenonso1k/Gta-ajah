extends RefCounted
## Graphics and crowd presets. Phones default to Low, desktops to High.
## Override with `godot --path . -- --quality=low` (or medium / high).

const PRESETS := {
	"low": {
		"pedestrians": 12,
		"cars": 6,
		"ragdolls": 8,
		"shadows": false,
		"shadow_distance": 0.0,
		# Thicker haze hides the short draw distance
		"fog_density": 0.006,
		"draw_distance": 250.0,
		# 3D is drawn at this fraction of the screen resolution and scaled up;
		# the HUD and touch controls stay sharp
		"render_scale": 0.7,
	},
	"medium": {
		"pedestrians": 20,
		"cars": 9,
		"ragdolls": 15,
		"shadows": true,
		"shadow_distance": 60.0,
		"fog_density": 0.004,
		"draw_distance": 600.0,
		"render_scale": 0.85,
	},
	"high": {
		"pedestrians": 30,
		"cars": 13,
		"ragdolls": 25,
		"shadows": true,
		"shadow_distance": 120.0,
		"fog_density": 0.0025,
		"draw_distance": 1500.0,
		"render_scale": 1.0,
	},
}


static func current_name() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			var picked := arg.trim_prefix("--quality=")
			if PRESETS.has(picked):
				return picked
	return "low" if OS.has_feature("mobile") else "high"


static func current() -> Dictionary:
	return PRESETS[current_name()]
