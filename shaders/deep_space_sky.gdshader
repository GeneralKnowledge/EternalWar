shader_type sky;

// Limit Theory direction-space nebula — port of gen/nebula.glsl `generate(dir)`.
// Structure comes from Kaliset IFS + absorption along the view ray into dir-space,
// NOT soft lobes / lattices painted on a sky sphere.
//
// Live notes (Godot Compatibility / mediump radiance cubemap):
// - Pure LT `c *= exp(-k*w*vs)` underflows to irreversible black.
// - Wide un-gated emission washes the whole dome cyan (sphere look).
// - Working live recipe: clamp absorb, additive filament emit_acc, and a larger
//   dir-space sample extent so magic() actually walks the IFS (LT bake uses
//   128 samples offline; we use fewer with extent scale).

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
// Live extent: LT offline uses 128 samples along kScale; with ~48 samples we
// stretch the march so magic() still explores filamentary IFS structure.
const float kExtent = 12.0;
const int kSamplesBg = 48;
const int kSamplesCube = 32;
const int kIterations = 22;
const float kBrightConstant = 0.075;
const float kBrightCell = 0.100;
const float kAbsorb = 3.6;

float hash11(float x) {
	return fract(sin(x * 127.1 + seed * 0.13) * 43758.5453);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed * 0.01);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise4(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

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
	for (int o = 0; o < 6; o++) {
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
	return kBrightConstant + kBrightCell * f_smooth_noise(p * 4.0 + vec3(seed), 6, 2.0);
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
	float r = lut1(t, lut_r.x * 0.35, lut_r.x, lut_rg_mid.x, lut_r.y, lut_r.z);
	float g = lut1(t, lut_g.x * 0.35, lut_g.x, lut_rg_mid.y, lut_g.y, lut_g.z);
	float b = lut1(t, lut_b.x * 0.4, lut_b_edge.x, lut_b.x, lut_b_edge.y, lut_b.z);
	vec3 wave = vec3(r, g, b);
	wave = mix(wave, mix(secondary_color, primary_color, t), 0.22);
	wave *= sqrt(max(wave, vec3(0.0)));
	return wave;
}

// Direction-space IFS only — no mass lobes, void discs, galaxy band, or sparkle grid.
vec3 generate(vec3 dir_in, int sample_count) {
	vec3 dir = normalize(dir_in);
	vec3 c = vec3(bg_density(dir)) * 1.15;

	// Large-scale IFS mood at this direction (not a painted mass lobe).
	float m_sky = magic(dir * 0.018);
	float sky_t = exp(-m_sky * m_sky);
	vec3 sky_wave = lut_wave(sky_t);
	c += sky_wave * 0.035;
	c += mix(secondary_color, primary_color, sky_t) * 0.03 * sky_t;

	float dstar = max(0.0, 1.0 - dot(dir, normalize(star_dir)));
	float dd = 8.0 * exp(-sqrt(4096.0 * dstar)) + 4.0 * exp(-sqrt(sqrt(1024.0 * dstar)));
	c += dd * primary_color;

	vec3 march = dir * kScale;
	float w = 1.0 / float(sample_count);
	vec3 c_emit = primary_color;
	vec3 emit_acc = vec3(0.0);
	// Without composition lobes the old live path used gas_gate≈0.55 so absorb
	// did not crush the whole product to black on mediump.
	const float absorb_scale = 0.55;

	for (int i = 0; i < 64; i++) {
		if (i >= sample_count) {
			break;
		}
		// Centered samples across an extended IFS interval (live stand-in for
		// LT's denser 128-sample bake). Still pure direction-space.
		vec3 p = march * (float(i) + 0.5) * w * kExtent;
		float m = magic(p);
		float t = exp(-m * m);
		vec3 wave = lut_wave(t);

		const float q = 1.2;
		vec3 vs = exp(-q * wave * t);
		float cavity = exp(-pow(8.0 * abs(t - 0.90), 0.75));
		float filament = exp(-pow(10.0 * abs(t - 0.88), 0.50));
		vs -= 1.25 * cavity;
		vec3 filament_emit = 0.70 * c_emit * filament;
		filament_emit += 0.28 * secondary_color * cavity;
		// Sharper ring gate — prefer filaments over soft body wash.
		float rings = 0.35 + 0.65 * pow(abs(sin(48.0 * m) * cos(36.0 * m)), 1.25);
		filament_emit *= clamp(rings, 0.08, 1.0);
		vs += filament_emit;

		c *= exp(-kAbsorb * w * max(vs, vec3(0.0)) * absorb_scale);
		emit_acc += filament_emit * w * 0.85 * wave;
	}

	c += emit_acc;
	c = mix(bg_color * 0.40, c, 0.96);
	c *= 1.12;
	return max(c, bg_color * 0.16);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	int samples = kSamplesBg;
	if (AT_CUBEMAP_PASS) {
		samples = kSamplesCube;
	}
	COLOR = generate(dir, samples);
}
