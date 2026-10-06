shader_type sky;

// Deep indigo void + coloured nebula structure. Nebula tint accents, never muddies the floor.

uniform float seed = 42.0;
uniform vec3 nebula_tint = vec3(0.4, 0.35, 0.85);
uniform float nebula_strength = 0.85;
uniform float band_strength = 0.8;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed * 0.01);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * noise2(p);
		p = m * p * 2.07;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// Cool indigo floor — readable, not olive, not #000.
	vec3 col = vec3(0.035, 0.04, 0.085);
	// Light nebula influence on the floor only
	col = mix(col, nebula_tint * 0.28, 0.35);

	vec3 band_n = normalize(vec3(0.18, 1.0, 0.1));
	float band = 1.0 - abs(dot(dir, band_n));
	band = pow(clamp(band, 0.0, 1.0), 3.4);
	vec2 band_uv = vec2(atan(dir.z, dir.x), dir.y) * 2.0 + seed * 0.01;
	float band_noise = fbm(band_uv * 1.5);
	col += nebula_tint * band * (0.35 + band_noise * 0.65) * band_strength;
	col += vec3(0.12, 0.16, 0.32) * band * 0.4 * band_strength;

	vec2 nuv = dir.xy * 1.4 + dir.z * 0.8 + vec2(seed * 0.02, seed * 0.015);
	float n1 = fbm(nuv * 1.05);
	float n2 = fbm(nuv * 2.6 + 9.0);
	float veil = smoothstep(0.36, 0.82, n1 * 0.58 + n2 * 0.5);
	float lobe = smoothstep(0.15, 0.75, abs(dir.x + 0.25 * dir.y + n2 * 0.35));
	col += nebula_tint * veil * lobe * nebula_strength * 0.55;
	col += mix(nebula_tint.bgr, vec3(0.35, 0.45, 0.9), 0.4) * veil * (1.0 - lobe) * nebula_strength * 0.32;

	vec2 suv = dir.xy * 85.0 + dir.z * 36.0 + seed;
	float cell = hash21(floor(suv));
	if (cell > 0.968) {
		vec2 f = fract(suv) - 0.5;
		float spark = exp(-dot(f, f) * 85.0) * (0.45 + cell);
		col += mix(vec3(1.0, 0.92, 0.78), vec3(0.7, 0.85, 1.0), hash21(floor(suv) + 3.1)) * spark * 1.15;
	}

	COLOR = col;
}
