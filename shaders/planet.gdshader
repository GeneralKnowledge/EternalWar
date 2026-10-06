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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 nrm = normalize(v_obj);
	float n = fbm(nrm * 3.5);
	float lat = abs(nrm.y);
	vec3 land = mix(color_a.rgb, color_b.rgb, smoothstep(0.3, 0.7, n));
	land = mix(land, color_c.rgb, smoothstep(0.55, 0.9, lat * 0.5 + n * 0.5));
	float ocean = step(n, ocean_level);
	vec3 col = mix(land, color_a.rgb * 0.55 + vec3(0.05, 0.12, 0.25), ocean);
	float ice = smoothstep(0.65, 0.9, lat);
	col = mix(col, color_d.rgb, ice * (1.0 - ocean * 0.3));
	float clouds = smoothstep(cloud_level, cloud_level + 0.25, fbm(nrm * 6.0 + vec3(seed_offset)));
	col = mix(col, vec3(0.92, 0.94, 0.97), clouds * 0.55 * clamp(1.0 - ocean * 0.2, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.25, roughness_val, 1.0 - ocean * 0.7);
	METALLIC = 0.05;
	EMISSION = col * atmosphere_tint * 0.08;
}
