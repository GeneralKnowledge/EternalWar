shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_opaque, specular_disabled;

// Limit Theory pulse head/tail spirit — tapered bolt with core.
uniform vec3 pulse_color : source_color = vec3(0.45, 0.75, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float u = UV.x * 2.0 - 1.0;
	float v = clamp(UV.y, 0.0, 1.0);
	float core = exp(-28.0 * abs(u));
	float body = exp(-8.0 * abs(u)) * (1.0 - exp(-10.0 * v)) * exp(-4.0 * v);
	float a = (core * 1.4 + body) * intensity;
	if (a < 0.03) {
		discard;
	}
	vec3 c = pulse_color * (0.6 + core * 1.8);
	ALBEDO = c * a;
	EMISSION = c * a * 2.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
