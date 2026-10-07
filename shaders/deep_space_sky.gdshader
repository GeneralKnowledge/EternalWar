shader_type sky;

// Limit Theory–aligned direction-space nebula (gen/nebula.glsl principles).
// Primary look = Kaliset IFS density + absorption along EYEDIR.
// NOT world-space fog volumes. Composition biases lobes / voids / palette.

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

// Approx LT ColorLUT knots (5 samples each channel), filled from GDScript.
uniform vec3 lut_r = vec3(0.2, 0.55, 0.9);
uniform vec3 lut_g = vec3(0.25, 0.5, 0.75);
uniform vec3 lut_b = vec3(0.35, 0.55, 0.85);
uniform vec2 lut_rg_mid = vec2(0.45, 0.4); // R/G knot at t≈0.5
uniform vec2 lut_b_edge = vec2(0.3, 0.7);  // B knots at t≈0.25 / 0.75

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

const float kScale = 0.040;
const int kSamples = 48; // LT bake uses 128; 48 is realtime sky budget
const int kIterations = 28; // LT uses 30
const float kBrightConstant = 0.075;
const float kBrightCell = 0.100;

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

// LT magic() — Kaliset 4D with noise injection (gen/nebula.glsl)
float magic(vec3 p) {
	vec4 z = vec4(vec3(0.53) + p, 0.0);
	float a = 0.0;
	float l = 0.0;
	float tw = 0.0;
	float w = 1.0;
	vec4 c = vec4(0.5, 0.55, 0.45, 0.6);
	for (int i = 0; i < 30; i++) {
		if (i >= kIterations) {
			break;
		}
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
	// LT: high-frequency filament rings from the IFS field
	return 0.5 + 0.5 * min(cos(30.0 * t), sin(40.0 * t));
}

float bg_density(vec3 p) {
	return kBrightConstant + kBrightCell * noise3(p * 4.0 + vec3(seed));
}

// Piecewise LUT approx — LT samples texture1D(lut*, t)
float lut1(float t, float a, float b, float c, float d, float e) {
	t = clamp(t, 0.0, 1.0);
	if (t < 0.25) {
		return mix(a, b, t / 0.25);
	}
	if (t < 0.5) {
		return mix(b, c, (t - 0.25) / 0.25);
	}
	if (t < 0.75) {
		return mix(c, d, (t - 0.5) / 0.25);
	}
	return mix(d, e, (t - 0.75) / 0.25);
}

vec3 lut_wave(float t) {
	float r = lut1(t, lut_r.x * 0.35, lut_r.x, lut_rg_mid.x, lut_r.y, lut_r.z);
	float g = lut1(t, lut_g.x * 0.35, lut_g.x, lut_rg_mid.y, lut_g.y, lut_g.z);
	float b = lut1(t, lut_b.x * 0.4, lut_b_edge.x, lut_b.x, lut_b_edge.y, lut_b.z);
	vec3 wave = vec3(r, g, b);
	// Nudge toward mood palette so forced moods read clearly
	wave = mix(wave, mix(secondary_color, primary_color, t), 0.35);
	return sqrt(max(wave, vec3(0.0)));
}

float mass_bias(vec3 dir) {
	float b = 0.0;
	b += pow(max(0.0, dot(dir, normalize(mass0_dir))), 6.0) * mass0_params.x;
	b += pow(max(0.0, dot(dir, normalize(mass1_dir))), 7.0) * mass1_params.x * 0.75;
	b += pow(max(0.0, dot(dir, normalize(mass2_dir))), 8.0) * mass2_params.x * 0.55;
	return clamp(b, 0.0, 2.0);
}

// LT Nebula1.lua path: bake generate(dir) into the radiance cubemap, sample as skybox.
vec3 generate(vec3 dir) {
	// Soft voids — intentional negative space (composition)
	float void_w = 0.0;
	void_w = max(void_w, smoothstep(void0_radius * 1.05, void0_radius * 0.15, 1.0 - max(dot(dir, normalize(void0_dir)), 0.0)));
	void_w = max(void_w, smoothstep(void1_radius * 1.05, void1_radius * 0.15, 1.0 - max(dot(dir, normalize(void1_dir)), 0.0)));
	void_w = clamp(void_w, 0.0, 1.0);

	float bias = mass_bias(dir);
	float lobe = smoothstep(0.02, 0.45, bias);
	float gas_gate = mix(0.55, 1.0, lobe) * (1.0 - void_w * 0.75);

	vec3 c = vec3(bg_density(dir)) * 1.35;
	c += mix(secondary_color, primary_color, 0.45) * 0.04 * gas_gate;

	float dstar = max(0.0, 1.0 - dot(dir, normalize(star_dir)));
	float dd = 8.0 * exp(-sqrt(4096.0 * dstar)) + 4.0 * exp(-sqrt(sqrt(1024.0 * dstar)));
	c += dd * primary_color;

	vec3 march_dir = dir * kScale * (1.0 + bias * 0.08);
	float w = 1.0 / float(kSamples);
	vec3 c_emit = primary_color;
	vec3 emit_acc = vec3(0.0);
	for (int i = 0; i < 64; i++) {
		if (i >= kSamples) {
			break;
		}
		vec3 p = march_dir * (float(i) + 0.5) * w * 12.0;
		float t = magic(p);
		t = exp(-t * t);
		vec3 wave = lut_wave(t);

		const float k = 3.6;
		const float q = 1.2;
		vec3 vs = exp(-q * wave * t);
		vs -= 1.15 * exp(-pow(8.0 * abs(t - 0.90), 0.75));
		vec3 filament_emit = 0.55 * c_emit * exp(-pow(10.0 * abs(t - 0.88), 0.50));
		filament_emit += 0.22 * secondary_color * pow(clamp(t, 0.0, 1.0), 1.4);
		vs += filament_emit;
		c *= exp(-k * w * max(vs, vec3(0.0)) * mix(0.55, 1.0, gas_gate));
		emit_acc += filament_emit * w * gas_gate * (0.55 + bias * 0.5);
	}
	c += emit_acc;

	vec3 gn = normalize(galaxy_normal);
	float plane = 1.0 - abs(dot(dir, gn));
	float band = pow(clamp(plane, 0.0, 1.0), max(band_width * 0.95, 2.5));
	c += band_color * band * 0.10 * band_strength * gas_gate;
	c += mix(primary_color, secondary_color, 0.35) * bias * 0.18 * gas_gate;

	vec3 col = mix(bg_color * 0.55, c, 0.95);
	col = mix(col, bg_color * 0.25, void_w * 0.65);
	col *= 1.0 - void_w * 0.25;
	col *= 1.15;

	vec2 suv = dir.xy * 110.0 + dir.z * 45.0 + seed;
	float cell = hash21(floor(suv));
	if (cell > 0.986 && void_w < 0.42) {
		vec2 f = fract(suv) - 0.5;
		float spark = exp(-dot(f, f) * 150.0) * (0.22 + cell * 0.32);
		col += vec3(0.85, 0.9, 1.0) * spark * 0.4;
	}
	return max(col, vec3(0.0));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Cubemap bake = LT TexCube generate(); background samples the baked radiance.
	if (AT_CUBEMAP_PASS) {
		COLOR = generate(dir);
	} else {
		COLOR = texture(RADIANCE, dir).rgb;
	}
}
