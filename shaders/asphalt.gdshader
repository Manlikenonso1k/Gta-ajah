// Worn tropical asphalt: uneven patches, repairs, grain and darker tyre
// tracks along the lanes (the city's roads run along x and z).
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/noise.gdshaderinc"

uniform float road_pitch = 52.0;
uniform float lane_offset = 1.8;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float broad = city_fbm(p * 0.07);
	float grain = city_noise(p * 9.0);
	vec3 col = mix(vec3(0.21, 0.21, 0.22), vec3(0.27, 0.265, 0.255), broad);
	col *= 0.95 + 0.07 * grain;
	// Patched repairs: a few darker rectangles, soft-edged
	vec2 patch_cell = floor(p / vec2(6.0, 4.0));
	vec2 in_cell = fract(p / vec2(6.0, 4.0));
	float patch = step(0.93, city_hash(patch_cell * 1.7)) * smoothstep(0.08, 0.16, min(in_cell.x, in_cell.y)) * smoothstep(0.08, 0.16, min(1.0 - in_cell.x, 1.0 - in_cell.y));
	col = mix(col, vec3(0.16, 0.16, 0.17), patch * 0.7);
	// Tyre tracks: the middle of each lane, measured from the nearest road line
	vec2 to_line = abs(mod(p + road_pitch * 0.5 + 26.0, road_pitch) - road_pitch * 0.5);
	float track_x = smoothstep(0.9, 0.2, abs(to_line.x - lane_offset));
	float track_z = smoothstep(0.9, 0.2, abs(to_line.y - lane_offset));
	col *= 1.0 - 0.12 * max(track_x, track_z);
	ALBEDO = col;
	ROUGHNESS = 0.82 - 0.1 * max(track_x, track_z);
	SPECULAR = 0.35;
}
