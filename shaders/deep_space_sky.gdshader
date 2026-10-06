shader_type sky;

// Composition-driven deep space: indigo floor, galactic band, 3 nebula masses,
// void cones, and sparse sky sparks. MultiMesh supplies dense star points.

uniform float seed = 42.0;
uniform vec3 bg_color = vec3(0.03, 0.035, 0.08);
uniform vec3 band_color = vec3(0.45, 0.4, 0.7);
uniform vec3 primary_color = vec3(0.4, 0.3, 0.7);
uniform vec3 secondary_color = vec3(0.3, 0.35, 0.55);
uniform vec3 galaxy_normal = vec3(0.15, 1.0, 0.1);
uniform float band_width = 3.6;
uniform float band_strength = 0.75;

uniform vec3 mass0_dir = vec3(0.4, 0.1, 0.35);
uniform vec3 mass0_params = vec3(1.0, 0.6, 0.4); // scale, core, dark
uniform vec3 mass1_dir = vec3(-0.3, 0.05, 0.6);
uniform vec3 mass1_params = vec3(0.8, 0.5, 0.45);
uniform vec3 mass2_dir = vec3(0.1, -0.2, -0.7);
uniform vec3 mass2_params = vec3(0.7, 0.4, 0.5);

uniform vec3 void0_dir = vec3(-0.6, 0.4, -0.3);
uniform float void0_radius = 0.5;
uniform vec3 void1_dir = vec3(0.5, -0.5, 0.4);
uniform float void1_radius = 0.45;

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
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = m * p * 2.05;
		a *= 0.5;
	}
	return v;
}

float mass_field(vec3 dir, vec3 mdir, vec3 params) {
	float scale = params.x;
	float core = params.y;
	float dark = params.z;
	float ang = max(0.0, dot(dir, normalize(mdir)));
	float lobe = pow(ang, mix(4.0, 12.0, 1.0 - scale * 0.45));
	vec2 uv = dir.xy * (1.6 / max(scale, 0.35)) + dir.z * 0.7 + mdir.xy * 2.0;
	float n_lo = fbm(uv * 0.9);
	float n_mid = fbm(uv * 2.7 + 5.0);
	float n_hi = fbm(uv * 6.5 + 11.0);
	float density = lobe * (0.35 + n_lo * 0.55 + n_mid * 0.35);
	float wisps = smoothstep(0.4, 0.85, n_mid * 0.6 + n_hi * 0.5) * lobe;
	float core_glow = pow(ang, 18.0) * core * (0.5 + n_lo);
	// Dark lanes / absorption gaps (LT-style negative structure inside glow)
	float lane = smoothstep(0.35, 0.7, abs(n_mid - 0.5) * 2.0);
	density *= mix(1.0, 1.0 - dark * 0.85, lane);
	return density * 0.7 + wisps * 0.35 + core_glow * 0.9;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Lifted floor — LT stills are dark but not crushed #000 everywhere.
	vec3 col = bg_color * 1.35 + primary_color * 0.08;

	// Void cones — soft negative space, not total blackout
	float void_w = 0.0;
	void_w = max(void_w, smoothstep(void0_radius, void0_radius * 0.25, 1.0 - max(dot(dir, normalize(void0_dir)), 0.0)));
	void_w = max(void_w, smoothstep(void1_radius, void1_radius * 0.25, 1.0 - max(dot(dir, normalize(void1_dir)), 0.0)));
	void_w = clamp(void_w, 0.0, 1.0);

	// Galactic band — wide luminous axis
	vec3 gn = normalize(galaxy_normal);
	float band = 1.0 - abs(dot(dir, gn));
	band = pow(clamp(band, 0.0, 1.0), max(band_width * 0.85, 2.2));
	vec2 band_uv = vec2(atan(dir.z, dir.x), dir.y) * 2.0 + seed * 0.01;
	float band_noise = fbm(band_uv * 1.4);
	col += band_color * band * (0.55 + band_noise * 0.9) * band_strength;
	col += primary_color * band * 0.45 * band_strength;

	// Nebula masses (low + mid frequency) — luminous volumes like LT env maps
	float m0 = mass_field(dir, mass0_dir, mass0_params);
	float m1 = mass_field(dir, mass1_dir, mass1_params);
	float m2 = mass_field(dir, mass2_dir, mass2_params);
	col += mix(primary_color, secondary_color, 0.15) * m0 * 1.45;
	col += mix(primary_color, secondary_color, 0.55) * m1 * 1.15;
	col += mix(secondary_color, band_color, 0.4) * m2 * 0.95;

	// Sparse high-frequency sparks in non-void regions
	vec2 suv = dir.xy * 95.0 + dir.z * 40.0 + seed;
	float cell = hash21(floor(suv));
	if (cell > 0.972 && void_w < 0.65) {
		vec2 f = fract(suv) - 0.5;
		float spark = exp(-dot(f, f) * 100.0) * (0.4 + cell);
		col += mix(vec3(1.0, 0.9, 0.75), vec3(0.7, 0.85, 1.0), hash21(floor(suv) + 2.2)) * spark * 1.25;
	}

	// Soft voids — dark resting areas without killing the composition
	col = mix(col, bg_color * 0.55, void_w * 0.55);
	col *= 1.0 - void_w * 0.28;

	COLOR = col;
}
