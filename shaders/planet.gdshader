shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

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

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 nrm = normalize(v_obj);
	float lat = abs(nrm.y);
	float n = fbm(nrm * 3.8);
	float n_fine = fbm(nrm * 9.0 + vec3(seed_offset));

	// Gas giant banding
	float bands = sin(nrm.y * 18.0 + n * 3.0 + seed_offset) * 0.5 + 0.5;
	vec3 gas = mix(color_a.rgb, color_b.rgb, bands);
	gas = mix(gas, color_c.rgb, smoothstep(0.35, 0.85, n_fine) * 0.45);

	vec3 land = mix(color_a.rgb, color_b.rgb, smoothstep(0.22, 0.78, n));
	land = mix(land, color_c.rgb, smoothstep(0.45, 0.95, lat * 0.4 + n_fine * 0.6));
	// Extra crater / roughness variation for rocky surfaces
	float craters = smoothstep(0.62, 0.78, n_fine) * (1.0 - gas_giant);
	land *= 1.0 - craters * 0.28;
	// Desert washes greens toward sand
	land = mix(land, mix(color_c.rgb, color_a.rgb, n), desert * 0.85);

	float ocean = step(n, ocean_level) * (1.0 - gas_giant) * (1.0 - desert * 0.7);
	vec3 ocean_col = color_a.rgb * 0.45 + vec3(0.04, 0.1, 0.28);
	// Specular-ish ocean: brighter toward view via NORMAL/VIEW
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
	ocean_col += vec3(0.35, 0.45, 0.55) * fres * 0.55;

	vec3 col = mix(land, ocean_col, ocean);
	col = mix(col, gas, gas_giant);

	float ice = smoothstep(0.58, 0.88, lat);
	ice = max(ice, ice_world * smoothstep(0.35, 0.7, n));
	col = mix(col, color_d.rgb, ice * (1.0 - ocean * 0.25) * (1.0 - gas_giant * 0.5));

	float cloud_n = fbm(nrm * 6.2 + vec3(seed_offset * 1.3, 0.2, -seed_offset));
	float clouds = smoothstep(cloud_level, cloud_level + 0.22, cloud_n);
	clouds *= (1.0 - gas_giant * 0.7);
	col = mix(col, vec3(0.93, 0.95, 0.98), clouds * 0.6 * clamp(1.0 - ocean * 0.15, 0.0, 1.0));

	// Soft limb atmosphere tint on the sphere itself
	float limb = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.8);
	col += color_a.rgb * limb * atmosphere_tint * 0.35;

	ALBEDO = col;
	ROUGHNESS = mix(0.18, roughness_val, 1.0 - ocean * 0.75);
	METALLIC = 0.04 + ocean * 0.08;
	EMISSION = col * atmosphere_tint * 0.06 + ocean_col * ocean * fres * 0.12;
}
