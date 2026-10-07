shader_type sky;

// Limit Theory direction-space nebula — port of gen/nebula.glsl `generate(dir)`.
// Structure comes from Kaliset IFS + absorption along the view ray into dir-space,
// NOT soft lobes / lattices painted on a sky sphere.
//
// LT runtime path: bake this into a TexCube, then sample with skybox.glsl.
// We evaluate live (Godot Sky) with a reduced sample count for realtime.

uniform float seed = 42.0;
uniform vec3 bg_color = vec3(0.02, 0.025, 0.05);
uniform vec3 primary_color = vec3(0.4, 0.3, 0.7);
uniform vec3 secondary_color = vec3(0.3, 0.35, 0.55);
uniform vec3 star_dir = vec3(0.2, 0.55, 0.15);
uniform float roughness = 0.72;

// Approx LT ColorLUT knots (5 samples each channel), filled from GDScript.
uniform vec3 lut_r = vec3(0.2, 0.55, 0.9);
uniform vec3 lut_g = vec3(0.25, 0.5, 0.75);
uniform vec3 lut_b = vec3(0.35, 0.55, 0.85);
uniform vec2 lut_rg_mid = vec2(0.45, 0.4);
uniform vec2 lut_b_edge = vec2(0.3, 0.7);

// Kept for GDScript wiring / future bake bias — NOT used to paint dome lobes.
uniform vec3 band_color = vec3(0.45, 0.4, 0.7);
uniform vec3 galaxy_normal = vec3(0.15, 1.0, 0.1);
uniform float band_width = 3.6;
uniform float band_strength = 0.55;
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
// LT bake uses 128; live sky budget. Cubemap pass can go lower.
const int kSamplesBg = 72;
const int kSamplesCube = 40;
const int kIterations = 30;
const float kBrightConstant = 0.075;
const float kBrightCell = 0.100;

float hash11(float x) {
	return fract(sin(x * 127.1 + seed * 0.13) * 43758.5453);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed * 0.01);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Cheap stand-in for LT noise4(float) used inside magic().
float noise4(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

// fSmoothNoise-ish: multi-octave value noise for bgDensity (LT uses 8 octaves).
float smooth_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash21(i.xy + i.z * 19.0);
	float n100 = hash21(i.xy + vec2(1.0, 0.0) + i.z * 19.0);
	float n010 = hash21(i.xy + vec2(0.0, 1.0) + i.z * 19.0);
	float n110 = hash21(i.xy + vec2(1.0, 1.0) + i.z * 19.0);
	float n001 = hash21(i.xy + (i.z + 1.0) * 19.0);
	float n101 = hash21(i.xy + vec2(1.0, 0.0) + (i.z + 1.0) * 19.0);
	float n011 = hash21(i.xy + vec2(0.0, 1.0) + (i.z + 1.0) * 19.0);
	float n111 = hash21(i.xy + vec2(1.0, 1.0) + (i.z + 1.0) * 19.0);
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float f_smooth_noise(vec3 p, int octaves, float lac) {
	float sum = 0.0;
	float amp = 1.0;
	float norm = 0.0;
	vec3 q = p;
	for (int o = 0; o < 8; o++) {
		if (o >= octaves) {
			break;
		}
		sum += amp * smooth_noise3(q);
		norm += amp;
		amp *= 0.5;
		q *= lac;
	}
	return sum / max(norm, 1e-4);
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
		// LT divides by m directly; guard only the singularity.
		z = abs(z) / max(m, 1e-8) - c;
		z += 0.02 * log(1.0e-10 + noise4(float(i) + seed));
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
	return 0.5 + 0.5 * min(cos(30.0 * t), sin(40.0 * t));
}

float bg_density(vec3 p) {
	// LT: kBrightConstant + kBrightCell * fSmoothNoise(p*4 + seed, 8, 2.0)
	return kBrightConstant + kBrightCell * f_smooth_noise(p * 4.0 + vec3(seed * 0.01), 8, 2.0);
}

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
	// Approximate texture1D(lut*, t) then wave *= sqrt(wave) as in LT.
	float r = lut1(t, lut_r.x * 0.35, lut_r.x, lut_rg_mid.x, lut_r.y, lut_r.z);
	float g = lut1(t, lut_g.x * 0.35, lut_g.x, lut_rg_mid.y, lut_g.y, lut_g.z);
	float b = lut1(t, lut_b.x * 0.4, lut_b_edge.x, lut_b.x, lut_b_edge.y, lut_b.z);
	vec3 wave = vec3(r, g, b);
	// Mild mood tint — keep LUT-driven structure dominant (not a dome wash).
	wave = mix(wave, mix(secondary_color, primary_color, t), 0.18);
	wave *= sqrt(max(wave, vec3(0.0)));
	return wave;
}

// LT Nebula1 / gen/nebula.glsl generate(dir) — absorption IFS, no dome paints.
vec3 generate(vec3 dir_in, int sample_count) {
	vec3 dir = normalize(dir_in);
	vec3 c = vec3(bg_density(dir));

	// Central star term (also present as a mesh; this matches LT bake energy).
	float dstar = max(0.0, 1.0 - dot(dir, normalize(star_dir)));
	float dd = 8.0 * exp(-sqrt(4096.0 * dstar)) + 4.0 * exp(-sqrt(sqrt(1024.0 * dstar)));
	c += dd * primary_color;

	// Critical LT path: sample along dir * kScale * i / N  (NOT a sphere surface paint).
	vec3 march = dir * kScale;
	float w = 1.0 / float(sample_count);
	vec3 c_emit = primary_color;
	for (int i = 0; i < 128; i++) {
		if (i >= sample_count) {
			break;
		}
		vec3 p = march * float(i) * w;
		float t = magic(p);
		t = exp(-t * t);
		vec3 wave = lut_wave(t);

		// LT constants: k=6, q=1.2, cavity at t≈0.90, emit 0.50*cEmit.
		// Do NOT clamp vs — negative vs is intentional (boost / filament).
		const float k = 6.0;
		const float q = 1.2;
		vec3 vs = exp(-q * wave * t);
		vs -= 1.25 * exp(-pow(8.0 * abs(t - 0.90), 0.75));
		vs += 0.50 * c_emit * exp(-pow(10.0 * abs(t - 0.90), 0.50));
		c *= exp(-k * w * vs);
	}

	return max(c, vec3(0.0));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Always evaluate generate() for the visible sky. Compatibility RADIANCE
	// sampling can return black if we only write during AT_CUBEMAP_PASS.
	int samples = kSamplesBg;
	if (AT_CUBEMAP_PASS) {
		samples = kSamplesCube;
	}
	COLOR = generate(dir, samples);
}
