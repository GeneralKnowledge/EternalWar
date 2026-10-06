shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, specular_disabled;

// Multi-frequency nebula mass: large lobes, mid wisps, dark lanes, bright core.
uniform vec4 nebula_color : source_color = vec4(0.35, 0.25, 0.55, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.25, 0.3, 0.5, 1.0);
uniform float seed_offset = 0.0;
uniform float density = 0.55;
uniform float soft_edge = 0.4;
uniform float brightness = 0.45;
uniform float core_strength = 0.55;
uniform float dark_lanes = 0.45;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
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
	float n_lo = fbm(uv * 1.4 + vec2(seed_offset * 0.07, seed_offset * 0.05));
	float n_mid = fbm(uv * 3.6 - vec2(seed_offset * 0.04, 0.35));
	float n_hi = fbm(uv * 8.0 + vec2(0.2, seed_offset * 0.03));

	float lobe = smoothstep(1.0 - density, 1.0, n_lo * 0.7 + n_mid * 0.4);
	float wisps = smoothstep(0.45, 0.9, n_mid * 0.55 + n_hi * 0.5);
	float core = exp(-length(uv) * length(uv) * mix(2.5, 6.0, 1.0 - core_strength)) * core_strength;

	// Dark lanes carve structure (absorption)
	float lane = smoothstep(0.3, 0.75, abs(n_mid - 0.48) * 2.2);
	float absorb = mix(1.0, 1.0 - dark_lanes * 0.9, lane);

	float alpha = (lobe * 0.65 + wisps * 0.4 + core * 0.55) * radial * brightness * absorb;
	vec3 col = mix(nebula_color.rgb, secondary_color.rgb, n_mid * 0.55);
	col *= 0.55 + n_lo * 0.6 + core * 0.8;
	ALBEDO = col;
	EMISSION = col * (0.65 + core * 1.1 + wisps * 0.35);
	ALPHA = clamp(alpha, 0.0, 0.7);
}
