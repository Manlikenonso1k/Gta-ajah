// Block tops (scripts/city.gd): concrete paving slabs with dirty joints, and
// a kerb painted in black and yellow stripes along the block edge, as on
// Port Harcourt roads. The block's box is centred at MODEL_MATRIX's origin.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/noise.gdshaderinc"

uniform float block_half = 20.0;
uniform float slab = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 local = world_pos.xz - origin.xz;
	vec2 cell = floor(world_pos.xz / slab);
	vec2 f = fract(world_pos.xz / slab);
	float joint = 1.0 - step(0.04, f.x) * step(0.04, f.y);
	float tone = city_hash(cell);
	vec3 col = vec3(0.6, 0.58, 0.55) * (0.88 + 0.14 * tone);
	col *= 0.85 + 0.2 * city_fbm(world_pos.xz * 0.25);
	col = mix(col, vec3(0.32, 0.3, 0.28), joint * 0.7);
	// Red dust drifts in from the edges
	float edge = block_half - max(abs(local.x), abs(local.y));
	col = mix(col, vec3(0.55, 0.36, 0.25), smoothstep(2.2, 0.4, edge) * 0.35 * city_noise(world_pos.xz * 0.6));
	// Painted kerb: the outer 0.3 m, striped every metre
	float kerb = step(edge, 0.3);
	float along = abs(local.x) > abs(local.y) ? world_pos.z : world_pos.x;
	vec3 kerb_col = mix(vec3(0.08, 0.08, 0.08), vec3(0.92, 0.78, 0.12), step(0.5, fract(along * 0.5)));
	kerb_col *= 0.8 + 0.25 * city_noise(world_pos.xz * 3.0);
	col = mix(col, kerb_col, kerb);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
