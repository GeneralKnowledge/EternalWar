shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_opaque, specular_disabled;

// Limit Theory effect/thruster.glsl — plume falloff along UV.
uniform vec3 thruster_color : source_color = vec3(1.0, 0.55, 0.25);
uniform float alpha = 1.0;
uniform float time_scale = 1.0;

void fragment() {
	float u = UV.x * 2.0 - 1.0;
	float v = clamp(UV.y, 0.0, 1.0);
	float uw = max(0.0, abs(u) - 0.25 * sqrt(v));
	float a = exp(-12.0 * uw) + 0.25 * exp(-12.0 * sqrt(uw));
	a *= (1.0 - exp(-pow(16.0 * v, 2.0))) * exp(-10.0 * v);
	a *= 1.0 + 4.0 * exp(-12.0 * v);
	float t = TIME * time_scale;
	float variation = pow(fract(sin(dot(vec2(u, 20.0 * v - 10.0 * t), vec2(12.9898, 78.233))) * 43758.5453), 2.0);
	a *= mix(1.0, 1.5, variation);
	a *= 2.0;
	if (a * alpha < 0.02) {
		discard;
	}
	vec3 col = thruster_color * (a * alpha);
	ALBEDO = col;
	EMISSION = col * 1.8;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
