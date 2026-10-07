shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Limit Theory–aligned planet (gen/planet.glsl principles):
// IFS height / colour / clouds on the sphere — not reinvented FBM bands.
// Live shader uses fewer iterations than the LT TexCube bake.

uniform vec4 color_a : source_color = vec4(0.2, 0.35, 0.55, 1.0);
uniform vec4 color_b : source_color = vec4(0.15, 0.45, 0.25, 1.0);
uniform vec4 color_c : source_color = vec4(0.55, 0.5, 0.35, 1.0);
uniform vec4 color_d : source_color = vec4(0.85, 0.85, 0.9, 1.0);
uniform float ocean_level : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_level : hint_range(-0.2, 1.0) = 0.1;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;
uniform float seed_offset = 0.0;
uniform float atmosphere_tint : hint_range(0.0, 1.0) = 0.35;
uniform float gas_giant : hint_range(0.0, 1.0) = 0.0;
uniform float desert : hint_range(0.0, 1.0) = 0.0;
uniform float ice_world : hint_range(0.0, 1.0) = 0.0;
uniform float freq = 4.0;
uniform float power = 1.35;
uniform vec4 coef = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

float hash31(vec3 p) {
	p = fract(p * 0.1031 + seed_offset);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float noise1(float x) {
	return hash31(vec3(x, x * 1.7, seed_offset));
}

float noise4(float x) {
	return hash31(vec3(x * 0.13, x * 0.37 + 2.1, seed_offset + 5.8));
}

// Approximate LT cell noise for cloud warp
float cell_n(vec3 p, float s) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d = 8.0;
	for (int xo = -1; xo <= 1; xo++) {
		for (int yo = -1; yo <= 1; yo++) {
			for (int zo = -1; zo <= 1; zo++) {
				vec3 g = i + vec3(float(xo), float(yo), float(zo));
				vec3 h = vec3(hash31(g + vec3(s)), hash31(g + vec3(s + 1.7)), hash31(g + vec3(s + 3.1)));
				vec3 r = vec3(float(xo), float(yo), float(zo)) + h - f;
				d = min(d, dot(r, r));
			}
		}
	}
	return clamp(1.0 - sqrt(d), 0.0, 1.0);
}

float gain_fn(float x, float k) {
	float a = 0.5 * pow(2.0 * ((x < 0.5) ? x : 1.0 - x), k);
	return (x < 0.5) ? a : 1.0 - a;
}

// LT genHeight — Kaliset-style IFS (reduced iters for live shading)
float gen_height(vec3 p) {
	vec4 z = vec4(p / 4.0 + 0.75, 0.3);
	float a = 0.0;
	float l = 0.0;
	float w = 1.0;
	for (int i = 0; i < 12; i++) {
		float m = dot(z, z);
		z = abs(z) / max(m, 1e-4) - vec4(0.4, 0.5, 0.6, 0.3);
		z += 0.1 * log(1.0e-10 + noise4(float(i) + seed_offset));
		z *= 1.0 + 0.25 * noise1(float(i) + seed_offset * 2.0 + 32.0);
		z = z.yzwx;
		m = coef.x * z.x * z.x + coef.y * z.y * z.y + coef.z * z.z * z.z + coef.w * z.w * z.w;
		if (i > 0) {
			a += w * exp(-abs(m - l));
			w *= 0.8 + 0.2 * (2.0 * noise1(seed_offset + 3.3 * float(i)) - 1.0);
		}
		l = m;
	}
	return gain_fn(pow(0.5 + 0.5 * sin(freq * a), power), 4.0);
}

// LT genColor
float gen_color(vec3 p) {
	vec4 z = vec4(p / 4.0 + 0.75, 0.3);
	float a = 0.0;
	float w = 1.0;
	for (int i = 0; i < 10; i++) {
		float m = dot(z, z);
		z = abs(z) / max(m, 1e-4) - vec4(0.4, 0.5, 0.6, 0.4);
		z += 0.1 * log(1.0e-10 + noise4(float(i) + seed_offset + 58.329));
		z *= 1.0 + 0.25 * noise1(float(i) + seed_offset * 5.0 + 12.0);
		z = z.yzwx;
		m = coef.x * z.x * z.x + coef.y * z.y * z.y + coef.z * z.z * z.z + coef.w * z.w * z.w;
		a += w * exp(-m);
		w *= 0.85;
	}
	return 0.5 + 0.5 * sin(4.0 * a);
}

// LT genClouds (lighter)
float gen_clouds(vec3 p) {
	vec3 q = p + 0.5 * vec3(
		cell_n(p * 2.2, seed_offset + 1.0),
		cell_n(p * 2.2, seed_offset + 5.0),
		cell_n(p * 2.2, seed_offset + 8.0));
	return 0.5 + 0.5 * sin(8.0 * cell_n(q * 1.4, seed_offset + 6.0));
}

void fragment() {
	vec3 nrm = normalize(v_obj);
	float lat = abs(nrm.y);
	float h = gen_height(nrm);
	float cfield = gen_color(nrm);
	float clouds_f = gen_clouds(nrm);

	// Gas giant: use colour field as bands instead of inventing sine stripes
	float bands = 0.5 + 0.5 * sin(nrm.y * 14.0 + cfield * 6.0 + seed_offset);
	vec3 gas = mix(color_a.rgb, color_b.rgb, bands);
	gas = mix(gas, color_c.rgb, smoothstep(0.35, 0.85, cfield) * 0.45);

	vec3 land = mix(color_a.rgb, color_b.rgb, smoothstep(0.22, 0.78, cfield));
	land = mix(land, color_c.rgb, smoothstep(0.4, 0.95, h));
	land *= 1.0 - smoothstep(0.62, 0.85, cfield) * 0.22 * (1.0 - gas_giant);
	land = mix(land, mix(color_c.rgb, color_a.rgb, cfield), desert * 0.85);

	float ocean = step(h, ocean_level) * (1.0 - gas_giant) * (1.0 - desert * 0.7);
	vec3 ocean_col = color_a.rgb * 0.45 + vec3(0.04, 0.1, 0.28);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
	ocean_col += vec3(0.35, 0.45, 0.55) * fres * 0.55;

	vec3 col = mix(land, ocean_col, ocean);
	col = mix(col, gas, gas_giant);

	float ice = smoothstep(0.58, 0.88, lat);
	ice = max(ice, ice_world * smoothstep(0.35, 0.7, h));
	col = mix(col, color_d.rgb, ice * (1.0 - ocean * 0.25) * (1.0 - gas_giant * 0.5));

	float clouds = smoothstep(cloud_level, cloud_level + 0.28, clouds_f);
	clouds *= (1.0 - gas_giant * 0.7);
	col = mix(col, vec3(0.93, 0.95, 0.98), clouds * 0.55 * clamp(1.0 - ocean * 0.15, 0.0, 1.0));

	float limb = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.8);
	col += color_a.rgb * limb * atmosphere_tint * 0.35;

	ALBEDO = col;
	ROUGHNESS = mix(0.18, roughness_val, 1.0 - ocean * 0.75);
	METALLIC = 0.04 + ocean * 0.08;
	// Mild fill so Compatibility/low-ambient captures still show IFS colour.
	EMISSION = col * (0.12 + atmosphere_tint * 0.1) + ocean_col * ocean * fres * 0.14;
}
