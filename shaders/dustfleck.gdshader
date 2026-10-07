shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_opaque, specular_disabled;

// Limit Theory effect/dustfleck.glsl — thin distance-faded flecks.
uniform vec3 fleck_cool : source_color = vec3(0.1, 0.5, 1.0);
uniform vec3 fleck_warm : source_color = vec3(1.0, 0.5, 0.1);

void fragment() {
	float u = UV.x * 2.0 - 1.0;
	float v = UV.y;
	float alpha = exp(-pow(2.0 * u, 2.0));
	alpha *= 0.12;
	alpha *= 1.0 - exp(-8.0 * v);
	alpha *= 1.0 - exp(-8.0 * (1.0 - v));
	float vy = 1.0 - v;
	alpha *= 1.0 - vy * vy * vy * vy;
	float dist = length(VERTEX);
	alpha *= exp(-4.0 * max(0.0, dist / 1024.0 - 0.8));
	alpha *= 1.0 - exp(-16.0 * max(0.0, dist / 1024.0 - 0.1));
	if (alpha < 0.01) {
		discard;
	}
	vec3 c = 1.0 / mix(fleck_cool, fleck_warm, 1.0 - v);
	float lum = max(dot(c, vec3(0.299, 0.587, 0.114)), 1e-4);
	c = c / lum;
	c *= sqrt(c);
	ALBEDO = c * alpha;
	EMISSION = c * alpha * 1.2;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
