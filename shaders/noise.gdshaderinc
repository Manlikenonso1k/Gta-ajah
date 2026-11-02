// Cheap value noise shared by the city shaders (GLES3 / Compatibility safe).
float city_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float city_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(city_hash(i), city_hash(i + vec2(1.0, 0.0)), f.x),
		mix(city_hash(i + vec2(0.0, 1.0)), city_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Two octaves: broad blotches plus finer grain
float city_fbm(vec2 p) {
	return city_noise(p) * 0.65 + city_noise(p * 2.7 + 13.1) * 0.35;
}
