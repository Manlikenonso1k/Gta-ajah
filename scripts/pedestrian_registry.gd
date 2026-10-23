extends RefCounted
## Central pedestrian catalogue.
##
## Two sources: CHARACTERS below (downloaded models, each with its own scale and
## licence) and generated_roster.json, written by blender/make_pedestrians.py
## for the MPFB-generated characters. IDs are stable: keep an ID when a model's
## file or display name changes.
##
## Imported models must face +Z with their feet at the origin after `scale`;
## pedestrian.gd turns them to the game's -Z and animates them with
## humanoid_walk.gd. See docs/PEDESTRIAN_CATALOG.md.

const BLACK_AFRICAN_WEIGHT := 0.90
const WHITE_WEIGHT := 0.10
const LEGACY_ID := "PED_LEGACY_PROC_001"
const GENERATED_ROSTER := "res://assets/characters/pedestrians/generated_roster.json"

const LEGACY := {
	"id": LEGACY_ID,
	"display_name": "Legacy Procedural Pedestrian",
	"model_path": "procedural://scripts/ragdoll.gd",
	"appearance_category": "unclassified_procedural",
	"outfit_id": "legacy_colour_variant",
	"tags": ["legacy", "fallback"],
	"scale": 1.0,
	"animation": "procedural_walk",
	"collision_radius": 0.3,
	"collision_height": 1.8,
	# Only used if no imported model can be loaded
	"available": false,
	"source": "Project procedural placeholder; not an external character asset.",
	"license": "Project code",
}

## Downloaded models. Renderpeople files are in centimetres (scale 0.01).
const CHARACTERS := [
	{"id": "PED_BA_SF01", "display_name": "Carla, business wear", "model_path": "res://assets/characters/pedestrians/black_african/carla.glb",
		"appearance_category": "black_african", "gender": "female", "outfit_id": "blazer_trousers", "tags": ["office", "business_casual"], "scale": 0.01,
		"source": "Carla Rigged 001 by Renderpeople, Sketchfab", "license": "CC BY 4.0"},
	{"id": "PED_BA_SF02", "display_name": "Man in vest and jeans", "model_path": "res://assets/characters/pedestrians/black_african/african_male.glb",
		"appearance_category": "black_african", "gender": "male", "outfit_id": "vest_jeans", "tags": ["casual"], "scale": 0.573,
		"source": "A rigged, animated black African male character by Maggadog, Sketchfab", "license": "CC BY 4.0"},
	{"id": "PED_WH_SF01", "display_name": "Eric, waistcoat and tie", "model_path": "res://assets/characters/pedestrians/white/eric.glb",
		"appearance_category": "white", "gender": "male", "outfit_id": "waistcoat_tie", "tags": ["office", "business_casual"], "scale": 0.01,
		"source": "Eric Rigged 001 by Renderpeople, Sketchfab", "license": "CC BY 4.0"},
	{"id": "PED_WH_SF02", "display_name": "Claudia, blouse", "model_path": "res://assets/characters/pedestrians/white/claudia.glb",
		"appearance_category": "white", "gender": "female", "outfit_id": "blouse_trousers", "tags": ["office", "business_casual"], "scale": 0.01,
		"source": "Claudia Rigged 002 by Renderpeople, Sketchfab", "license": "CC BY 4.0"},
	{"id": "PED_WH_SF03", "display_name": "Nathan, T-shirt and jeans", "model_path": "res://assets/characters/pedestrians/white/nathan.glb",
		"appearance_category": "white", "gender": "male", "outfit_id": "tshirt_jeans", "tags": ["casual"], "scale": 0.01,
		"source": "Nathan Animated 003 by Renderpeople, Sketchfab", "license": "CC BY 4.0"},
	{"id": "PED_WH_SF04", "display_name": "Sophia, top and jeans", "model_path": "res://assets/characters/pedestrians/white/sophia.glb",
		"appearance_category": "white", "gender": "female", "outfit_id": "top_jeans", "tags": ["casual"], "scale": 0.01,
		"source": "Sophia Animated 003 by Renderpeople, Sketchfab", "license": "CC BY 4.0"},
	{"id": "PED_WH_SF05", "display_name": "Manuel, grey T-shirt", "model_path": "res://assets/characters/pedestrians/white/manuel.glb",
		"appearance_category": "white", "gender": "male", "outfit_id": "tshirt_jeans", "tags": ["casual"], "scale": 0.01,
		"source": "Manuel Animated 001 by Renderpeople, Sketchfab", "license": "CC BY 4.0"},
]

static var _all: Array = []
## How many times each ID has been handed out, so repeats come last
static var _uses := {}


## Every available character, downloaded and generated.
static func all() -> Array:
	if _all.is_empty():
		for entry: Dictionary in CHARACTERS:
			_all.append(_with_defaults(entry))
		var text := FileAccess.get_file_as_string(GENERATED_ROSTER)
		var generated = JSON.parse_string(text) if not text.is_empty() else null
		if generated is Array:
			for entry: Dictionary in generated:
				_all.append(_with_defaults(entry))
		else:
			push_warning("Pedestrian roster missing or invalid: " + GENERATED_ROSTER)
	return _all


static func _with_defaults(entry: Dictionary) -> Dictionary:
	var full := {"scale": 1.0, "animation": "procedural_skeleton_walk", "collision_radius": 0.3,
		"collision_height": 1.8, "available": true, "tags": []}
	full.merge(entry, true)
	return full


## Picks a character: Black African with probability BLACK_AFRICAN_WEIGHT,
## otherwise white. Within the group the least-used models come first, so
## every model appears once before any repeats.
static func choose(rng: RandomNumberGenerator) -> Dictionary:
	var available := all().filter(func(entry: Dictionary) -> bool: return entry.available)
	if available.is_empty():
		return LEGACY.duplicate(true)
	var wanted := "black_african" if rng.randf() < BLACK_AFRICAN_WEIGHT else "white"
	var candidates: Array = available.filter(func(entry: Dictionary) -> bool: return entry.appearance_category == wanted)
	if candidates.is_empty():
		candidates = available
	var fewest: int = candidates.map(func(entry: Dictionary) -> int: return _uses.get(entry.id, 0)).min()
	candidates = candidates.filter(func(entry: Dictionary) -> bool: return _uses.get(entry.id, 0) == fewest)
	var picked: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	_uses[picked.id] = fewest + 1
	return picked.duplicate(true)


static func by_id(character_id: String) -> Dictionary:
	for entry: Dictionary in all():
		if entry.id == character_id:
			return entry.duplicate(true)
	return LEGACY.duplicate(true) if character_id == LEGACY_ID else {}
