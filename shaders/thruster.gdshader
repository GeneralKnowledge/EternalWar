shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Limit Theory effect/thruster.glsl — additive jet plume on a billboard.
// UV: x across [-1,1] via remap, y along jet (0 = nozzle, 1 = tip).

uniform vec3 thruster_color : source_color = vec3(0.3, 0.5, 1.0);
uniform float alpha = 1.0;
uniform float plume_time = 0.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	float u = v_uv.x * 2.0 - 1.0;
	float v = clamp(v_uv.y, 0.0, 1.0);
	float uw = max(0.0, abs(u) - 0.25 * sqrt(v));
	float a = exp(-12.0 * uw) + 0.25 * exp(-12.0 * sqrt(uw));
	a *= (1.0 - exp(-(16.0 * v) * (16.0 * v))) * exp(-10.0 * v);
	a *= 1.0 + 4.0 * exp(-12.0 * v);
	// Cheap 2-octave noise stand-in for fSmoothNoise(uv.x, 20v - 10t)
	float n1 = fract(sin(dot(vec2(u, 20.0 * v - 10.0 * plume_time), vec2(12.9898, 78.233))) * 43758.5453);
	float n2 = fract(sin(dot(vec2(u * 1.6, 32.0 * v - 16.0 * plume_time), vec2(39.346, 11.135))) * 24634.6345);
	float variation = pow(mix(n1, n2, 0.45), 2.0);
	a *= mix(1.0, 1.5, variation);
	a *= 2.0;
	ALBEDO = thruster_color;
	EMISSION = thruster_color * alpha * a;
	ALPHA = clamp(alpha * a, 0.0, 1.0);
}
