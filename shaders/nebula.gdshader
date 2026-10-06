shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, specular_disabled;

// Soft layered nebula — IFS-like fbm on a large billboard plane.
uniform vec4 nebula_color : source_color = vec4(0.25, 0.15, 0.45, 1.0);
uniform float seed_offset = 0.0;
uniform float density = 0.55;
uniform float soft_edge = 0.35;
uniform float brightness = 0.45;

varying vec2 v_uv;
varying vec3 v_world;

void vertex() {
	v_uv = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed_offset);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
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
		v += a * noise(p);
		p = m * p * 2.05;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = v_uv * 2.0 - 1.0;
	float radial = 1.0 - smoothstep(soft_edge, 1.0, length(uv));
	float n = fbm(uv * 2.8 + vec2(seed_offset * 0.1, seed_offset * 0.07));
	float n2 = fbm(uv * 5.5 - vec2(seed_offset * 0.05, 0.3));
	float veil = smoothstep(1.0 - density, 1.0, n * 0.65 + n2 * 0.45);
	float alpha = veil * radial * brightness;
	vec3 col = nebula_color.rgb * (0.5 + n2 * 0.55);
	ALBEDO = col;
	EMISSION = col * (0.55 + n * 0.45);
	ALPHA = clamp(alpha, 0.0, 0.55);
}
