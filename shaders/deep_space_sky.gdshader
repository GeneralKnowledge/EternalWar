shader_type sky;

// Soft deep-space backdrop for Compatibility/OpenGL3.
// Dense star *points* come from MultiMesh billboards; this fills voids with
// a lifted indigo base, galactic band, and soft nebula lobes — never pure black.

uniform float seed = 42.0;
uniform vec3 nebula_tint = vec3(0.35, 0.22, 0.55);
uniform float nebula_strength = 0.65;
uniform float band_strength = 0.55;

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

	// Lifted void — readable indigo, not crushed black under ACES.
	vec3 col = vec3(0.02, 0.024, 0.045);
	col = mix(col, nebula_tint * 0.22, 0.55);

	// Galactic band
	vec3 band_n = normalize(vec3(0.18, 1.0, 0.1));
	float band = 1.0 - abs(dot(dir, band_n));
	band = pow(clamp(band, 0.0, 1.0), 3.8);
	vec2 band_uv = vec2(atan(dir.z, dir.x), dir.y) * 2.2 + seed * 0.01;
	float band_noise = fbm(band_uv * 1.6);
	col += nebula_tint * band * band_noise * band_strength * 0.85;
	col += vec3(0.18, 0.2, 0.32) * band * 0.28 * band_strength;

	// Asymmetric nebula lobes (structure, not full-sky wash)
	vec2 nuv = dir.xy * 1.5 + dir.z * 0.85 + vec2(seed * 0.02, seed * 0.015);
	float n1 = fbm(nuv * 1.1);
	float n2 = fbm(nuv * 2.8 + 9.0);
	float veil = smoothstep(0.38, 0.82, n1 * 0.6 + n2 * 0.5);
	float lobe = smoothstep(0.15, 0.75, abs(dir.x + 0.25 * dir.y + n2 * 0.35));
	col += nebula_tint * veil * lobe * nebula_strength * 0.55;
	col += nebula_tint.bgr * veil * (1.0 - lobe) * nebula_strength * 0.28;

	// Sparse soft sparkle layer (large cells — survives low-res sky / Compat)
	vec2 suv = dir.xy * 90.0 + dir.z * 40.0 + seed;
	float cell = hash21(floor(suv));
	if (cell > 0.97) {
		vec2 f = fract(suv) - 0.5;
		float spark = exp(-dot(f, f) * 90.0) * (0.35 + cell);
		col += mix(vec3(1.0, 0.9, 0.75), vec3(0.7, 0.85, 1.0), hash21(floor(suv) + 3.1)) * spark;
	}

	COLOR = col;
}
