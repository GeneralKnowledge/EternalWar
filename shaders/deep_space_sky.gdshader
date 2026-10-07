shader_type sky;

// Direction-space nebula inspired by Limit Theory gen/nebula.glsl principles:
// Kaliset-style IFS density + absorption along the view ray + far sparks.
// NOT a world-space volume. Composition uniforms bias colour / voids / band.

uniform float seed = 42.0;
uniform vec3 bg_color = vec3(0.02, 0.025, 0.05);
uniform vec3 band_color = vec3(0.45, 0.4, 0.7);
uniform vec3 primary_color = vec3(0.4, 0.3, 0.7);
uniform vec3 secondary_color = vec3(0.3, 0.35, 0.55);
uniform vec3 galaxy_normal = vec3(0.15, 1.0, 0.1);
uniform float band_width = 3.6;
uniform float band_strength = 0.55;
uniform vec3 star_dir = vec3(0.2, 0.55, 0.15);
uniform float roughness = 0.72;

uniform vec3 mass0_dir = vec3(0.4, 0.1, 0.35);
uniform vec3 mass0_params = vec3(1.0, 0.6, 0.4);
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

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = hash21(i.xy + i.z * 17.0);
	float n2 = hash21(i.yz + i.x * 13.0 + 3.1);
	return mix(n, n2, f.z);
}

// Reduced-cost Kaliset-inspired field (LT magic()).
float magic(vec3 p) {
	vec4 z = vec4(vec3(0.53) + p, 0.0);
	float a = 0.0;
	float l = 0.0;
	float tw = 0.0;
	float w = 1.0;
	vec4 c = vec4(0.5, 0.55, 0.45, 0.6);
	for (int i = 0; i < 14; i++) {
		float m = dot(z, z);
		z = abs(z) / max(m, 1e-4) - c;
		z += 0.02 * log(1e-4 + noise3(vec3(float(i) + seed * 0.01)));
		z += 0.25 * sin(z);
		float lm = l - m;
		a += w * exp(-2.0 * lm * lm);
		tw += w;
		if (i > 3) {
			w *= roughness;
		}
		l = m;
		c = c.yzwx;
	}
	float t = a / max(tw, 1e-4);
	// Soften high-frequency concentric banding behind volumes
	float rings = min(cos(12.0 * t), sin(18.0 * t));
	return 0.5 + 0.5 * mix(t, rings, 0.35);
}

float mass_bias(vec3 dir) {
	float b = 0.0;
	b += pow(max(0.0, dot(dir, normalize(mass0_dir))), 6.0) * mass0_params.x;
	b += pow(max(0.0, dot(dir, normalize(mass1_dir))), 7.0) * mass1_params.x * 0.75;
	b += pow(max(0.0, dot(dir, normalize(mass2_dir))), 8.0) * mass2_params.x * 0.55;
	return clamp(b, 0.0, 2.0);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Dark floor — aim for LT dark_frac ~28–40% without killing lobe cores.
	vec3 col = bg_color * 0.55;

	// Soft voids — intentional negative space
	float void_w = 0.0;
	void_w = max(void_w, smoothstep(void0_radius * 1.05, void0_radius * 0.15, 1.0 - max(dot(dir, normalize(void0_dir)), 0.0)));
	void_w = max(void_w, smoothstep(void1_radius * 1.05, void1_radius * 0.15, 1.0 - max(dot(dir, normalize(void1_dir)), 0.0)));
	void_w = clamp(void_w, 0.0, 1.0);

	// Galactic band — structure, not fog wash
	vec3 gn = normalize(galaxy_normal);
	float plane = 1.0 - abs(dot(dir, gn));
	float band = pow(clamp(plane, 0.0, 1.0), max(band_width * 0.95, 2.5));
	col += band_color * band * 0.14 * band_strength * (1.0 - void_w * 0.55);

	// LT-style absorption along direction (short loop for realtime)
	float bias = mass_bias(dir);
	// Soft gate: keep lobe cores bright; off-lobe directions stay darker (not black).
	float lobe = smoothstep(0.015, 0.4, bias);
	float gas_gate = mix(0.32, 1.0, lobe) * (1.0 - void_w * 0.8);
	vec3 c = vec3(0.028 + 0.022 * noise3(dir * 4.0 + seed));
	c += primary_color * 0.024 * gas_gate;

	// Central / local star contribution in sky (LT generate())
	float dstar = max(0.0, 1.0 - dot(dir, normalize(star_dir)));
	float dd = 5.5 * exp(-sqrt(3800.0 * dstar)) + 2.2 * exp(-sqrt(sqrt(1000.0 * dstar)));
	c += dd * mix(primary_color, vec3(1.0, 0.95, 0.85), 0.35);

	vec3 pdir = dir * (0.042 + bias * 0.012);
	const int SAMPLES = 16;
	float w = 1.0 / float(SAMPLES);
	vec3 emit_acc = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		vec3 p = pdir * (float(i) + 0.5) * w * 12.0;
		float t = magic(p);
		t = exp(-t * t);
		// Prefer bright filaments; leave mid densities quieter (internal dark structure)
		float filament = pow(clamp(t, 0.0, 1.0), 1.35);
		vec3 wave = mix(secondary_color, primary_color, clamp(t, 0.0, 1.0));
		wave = sqrt(max(wave, vec3(0.0)));
		vec3 vs = exp(-1.15 * wave * t);
		vs -= 0.88 * exp(-pow(8.0 * abs(t - 0.9), 0.75));
		vec3 emit = 0.85 * primary_color * exp(-pow(9.0 * abs(t - 0.88), 0.55));
		emit += 0.28 * secondary_color * filament;
		c *= exp(-3.5 * w * max(vs, vec3(0.0)));
		emit_acc += gas_gate * emit * w * (0.5 + bias * 0.45) * (0.4 + filament * 0.6);
	}
	c += emit_acc;

	// Mass bias lifts luminous regions without filling voids
	c += mix(primary_color, secondary_color, 0.32) * bias * 0.28 * gas_gate;
	c += band_color * band * 0.1 * band_strength * gas_gate;

	col += c * (0.88 + band * 0.18);
	col = mix(col, bg_color * 0.28, void_w * 0.7);
	col *= 1.0 - void_w * 0.35;
	// Mild off-lobe darken — target ~0.28–0.4 dark_frac on nebula frames
	col *= mix(0.72, 1.0, clamp(gas_gate + dd * 0.06 + band * 0.22, 0.0, 1.0));

	// Sparse sparks (supporting cast; MultiMesh owns dense field)
	vec2 suv = dir.xy * 110.0 + dir.z * 45.0 + seed;
	float cell = hash21(floor(suv));
	if (cell > 0.986 && void_w < 0.42) {
		vec2 f = fract(suv) - 0.5;
		float spark = exp(-dot(f, f) * 150.0) * (0.22 + cell * 0.32);
		col += vec3(0.85, 0.9, 1.0) * spark * 0.48;
	}

	COLOR = max(col, vec3(0.0));
}
