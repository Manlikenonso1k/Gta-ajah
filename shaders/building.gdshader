// Facades for the generated city buildings (scripts/city.gd): a grid of
// floors and window bays drawn from world position, so one material covers
// any box size. Upper floors get louvre ("nako") windows, some with curtains
// or burglar-proof bars; the ground floor gets shop shutters under painted
// sign boards. Walls weather with rain streaks and red laterite dust near the
// ground; roofs are stained concrete.
// The building's box is centred at MODEL_MATRIX's origin, so its roof is at
// twice that height and its origin also seeds the per-building variety.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/noise.gdshaderinc"

uniform vec3 wall_color : source_color = vec3(0.9, 0.88, 0.8);
uniform float floor_height = 3.2;
uniform float bay_width = 2.9;

varying vec3 world_pos;
varying vec3 world_normal;

const vec3 SIGN_COLORS[5] = vec3[5](vec3(0.78, 0.12, 0.1), vec3(0.1, 0.32, 0.7), vec3(0.95, 0.75, 0.1), vec3(0.08, 0.5, 0.25), vec3(0.92, 0.92, 0.9));
const vec3 CURTAINS[4] = vec3[4](vec3(0.7, 0.2, 0.18), vec3(0.8, 0.66, 0.36), vec3(0.3, 0.45, 0.7), vec3(0.55, 0.38, 0.5));

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float box_mask(vec2 p, vec2 lo, vec2 hi) {
	vec2 inside = step(lo, p) * step(p, hi);
	return inside.x * inside.y;
}

void fragment() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float roof_y = origin.y * 2.0;
	float seed = city_hash(origin.xz * 0.173);
	vec3 n = world_normal;
	vec3 albedo;
	float rough = 0.92;
	float spec = 0.3;

	if (n.y > 0.5) {
		// Flat concrete roof with water stains
		float stain = city_fbm(world_pos.xz * 0.35);
		albedo = mix(vec3(0.5, 0.49, 0.46), vec3(0.36, 0.35, 0.33), smoothstep(0.45, 0.8, stain));
	} else {
		// Along the wall: x for walls facing z, z for walls facing x
		float u = abs(n.x) > 0.5 ? world_pos.z : world_pos.x;
		float v = world_pos.y;
		float fy = floor(v / floor_height);
		float fv = fract(v / floor_height);
		float bx = floor(u / bay_width);
		float fu = fract(u / bay_width);
		float cell = city_hash(vec2(bx, fy) + seed * 91.0);

		// Plaster with patchy repaints
		float patch = city_fbm(vec2(u, v) * 0.18 + seed * 7.0);
		albedo = wall_color * (0.86 + 0.16 * patch);
		// A painted band at every floor slab
		float slab = 1.0 - step(0.07, fv);
		albedo = mix(albedo, wall_color * 0.72, slab);

		if (fy < 0.5) {
			// Ground floor: rolled-down shutters or open dark shops, and a sign board
			float shop = box_mask(vec2(fu, fv), vec2(0.06, 0.0), vec2(0.94, 0.7));
			float open_shop = step(0.62, cell);
			float ribs = 0.5 + 0.5 * sin(v * 70.0);
			vec3 shutter = mix(vec3(0.42, 0.45, 0.47), vec3(0.55, 0.58, 0.6), ribs);
			shutter *= 0.75 + 0.35 * city_noise(vec2(u * 3.0, v * 0.6));
			// Open shop: dark inside, with rows of goods on shelves
			float shelf = step(0.5, fract(fv * 5.0)) * step(0.15, fv);
			vec3 goods = SIGN_COLORS[int(floor(city_hash(vec2(floor(u * 3.0), floor(fv * 5.0))) * 4.99))];
			vec3 interior = mix(vec3(0.06, 0.055, 0.05), goods * 0.35, shelf * step(0.4, city_hash(vec2(floor(u * 3.0), fy + floor(fv * 5.0)))));
			albedo = mix(albedo, mix(shutter, interior, open_shop), shop);
			float board = box_mask(vec2(fu, fv), vec2(0.0, 0.74), vec2(1.0, 0.93));
			int sign_index = int(floor(city_hash(vec2(floor(bx / 2.0), seed * 13.0)) * 5.0));
			vec3 sign_color = SIGN_COLORS[sign_index];
			// Word-shaped blocks so a board reads as lettering from a distance
			float letter_u = u * 3.2;
			float word = step(0.3, city_hash(vec2(floor(letter_u / 4.0), seed * 3.0 + bx)));
			float glyph = step(0.18, fract(letter_u)) * step(0.25, city_hash(vec2(floor(letter_u), seed)));
			float letters = word * glyph * box_mask(vec2(fu, fv), vec2(0.1, 0.795), vec2(0.9, 0.875));
			albedo = mix(albedo, mix(sign_color, vec3(1.0) - sign_color * 0.8, letters), board * step(0.25, seed + cell * 0.5));
			rough = mix(rough, 0.55, shop * (1.0 - open_shop));
		} else if (v < roof_y - 0.9) {
			// Upper floors: louvre windows in frames, with a sill below
			float frame = box_mask(vec2(fu, fv), vec2(0.2, 0.3), vec2(0.8, 0.84));
			float glass = box_mask(vec2(fu, fv), vec2(0.24, 0.34), vec2(0.76, 0.8));
			float sill = box_mask(vec2(fu, fv), vec2(0.17, 0.25), vec2(0.83, 0.3));
			albedo = mix(albedo, vec3(0.88, 0.87, 0.84), sill);
			albedo = mix(albedo, vec3(0.32, 0.3, 0.28), frame * (1.0 - glass));
			// Glass reflects the sky, darker inside; louvre blades catch light
			float blades = smoothstep(0.35, 0.6, fract(fv * 14.0));
			vec3 glass_color = mix(vec3(0.1, 0.14, 0.18), vec3(0.45, 0.58, 0.68), blades * 0.6);
			float curtain = step(0.55, cell) * step(fu, 0.5 + 0.26 * (city_hash(vec2(cell, fy)) - 0.3));
			glass_color = mix(glass_color, CURTAINS[int(floor(cell * 3.99))] * 0.8, curtain);
			// Burglar-proof bars on some buildings
			float bars = step(0.6, seed) * step(0.88, fract(fu * 9.0));
			glass_color = mix(glass_color, vec3(0.15, 0.15, 0.16), bars);
			albedo = mix(albedo, glass_color, glass);
			rough = mix(rough, 0.18, glass * (1.0 - curtain));
			spec = mix(spec, 0.6, glass);
		}
		// A darker parapet at the top
		albedo *= 1.0 - 0.18 * step(roof_y - 0.5, v);
		// Rain streaks running down from the windows and the roof
		float streak = city_noise(vec2(u * 2.2, v * 0.05 + seed * 5.0));
		albedo *= 1.0 - 0.22 * smoothstep(0.55, 0.95, streak) * (0.4 + 0.6 * fract(v / floor_height));
		// Red laterite dust splashed up from the ground
		float dust = smoothstep(0.9, 0.0, v) * (0.6 + 0.4 * city_noise(vec2(u * 1.5, 1.0)));
		albedo = mix(albedo, vec3(0.5, 0.33, 0.24), dust * 0.35);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
