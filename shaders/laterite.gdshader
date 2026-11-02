// Red laterite earth around the city, with darker damp patches and a little
// scrub grass.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://shaders/noise.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float broad = city_fbm(p * 0.03);
	vec3 col = mix(vec3(0.6, 0.33, 0.2), vec3(0.45, 0.24, 0.15), broad);
	col *= 0.9 + 0.15 * city_noise(p * 1.3);
	float grass = smoothstep(0.62, 0.8, city_fbm(p * 0.09 + 31.0));
	col = mix(col, vec3(0.3, 0.38, 0.16), grass * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.2;
}
