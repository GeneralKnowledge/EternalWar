shader_type sky;

// Composition-driven deep space: indigo floor, irregular galactic band,
// 3 nebula masses, void cones, sparse sky sparks. MultiMesh supplies dense stars.

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
	float lane = smoothstep(0.35, 0.7, abs(n_mid - 0.5) * 2.0);
	density *= mix(1.0, 1.0 - dark * 0.85, lane);
	return density * 0.7 + wisps * 0.35 + core_glow * 0.9;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = bg_color * 1.25 + primary_color * 0.06;

	float void_w = 0.0;
	void_w = max(void_w, smoothstep(void0_radius, void0_radius * 0.25, 1.0 - max(dot(dir, normalize(void0_dir)), 0.0)));
	void_w = max(void_w, smoothstep(void1_radius, void1_radius * 0.25, 1.0 - max(dot(dir, normalize(void1_dir)), 0.0)));
	void_w = clamp(void_w, 0.0, 1.0);

	// Irregular galactic band — clumps + dark gaps along longitude
	vec3 gn = normalize(galaxy_normal);
	float plane = 1.0 - abs(dot(dir, gn));
	float band_profile = pow(clamp(plane, 0.0, 1.0), max(band_width * 0.85, 2.2));
	vec3 tangent = normalize(cross(gn, abs(gn.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 bitangent = cross(gn, tangent);
	float lon = atan(dot(dir, bitangent), dot(dir, tangent));
	vec2 band_uv = vec2(lon * 1.8, plane * 3.0) + seed * 0.013;
	float n_lo = fbm(band_uv * 1.1);
	float n_mid = fbm(band_uv * 2.8 + 4.0);
	float n_hi = fbm(band_uv * 7.0 + 9.0);
	float clump = smoothstep(0.35, 0.85, n_lo * 0.65 + n_mid * 0.45);
	float gap = smoothstep(0.25, 0.7, abs(n_mid - 0.48) * 2.1);
	float band = band_profile * mix(0.35, 1.15, clump) * mix(1.0, 0.35, gap * 0.85);
	band *= 0.75 + n_hi * 0.35;
	col += band_color * band * 0.95 * band_strength;
	col += primary_color * band * 0.55 * band_strength;
	col += secondary_color * band_profile * n_lo * 0.18 * band_strength;

	// Faint far hint only — real colour/volume comes from raymarched masses.
	float m0 = mass_field(dir, mass0_dir, mass0_params);
	float m1 = mass_field(dir, mass1_dir, mass1_params);
	float m2 = mass_field(dir, mass2_dir, mass2_params);
	col += mix(primary_color, secondary_color, 0.15) * m0 * 0.28;
	col += mix(primary_color, secondary_color, 0.55) * m1 * 0.2;
	col += mix(secondary_color, band_color, 0.4) * m2 * 0.16;

	vec2 suv = dir.xy * 95.0 + dir.z * 40.0 + seed;
	float cell = hash21(floor(suv));
	if (cell > 0.978 && void_w < 0.55) {
		vec2 f = fract(suv) - 0.5;
		float spark = exp(-dot(f, f) * 120.0) * (0.35 + cell * 0.4);
		col += mix(vec3(1.0, 0.9, 0.75), vec3(0.7, 0.85, 1.0), hash21(floor(suv) + 2.2)) * spark * 0.9;
	}

	col = mix(col, bg_color * 0.5, void_w * 0.58);
	col *= 1.0 - void_w * 0.32;

	COLOR = col;
}
