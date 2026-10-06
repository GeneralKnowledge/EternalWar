shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_add, specular_disabled;

// Camera-facing star billboard — sharp points, controlled halo only for bright gems.
// Avoid the "bokeh disc field" look: ordinary stars stay tight.
uniform float soft_radius = 0.42;

void vertex() {
	vec4 mv_origin = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = mat4(
		vec4(sx, 0.0, 0.0, 0.0),
		vec4(0.0, sy, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		mv_origin
	);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	// Tight core; halo only when COLOR is bright (gems / notables)
	float lum = max(COLOR.r, max(COLOR.g, COLOR.b));
	float core = exp(-d * d * 48.0);
	float halo = exp(-d * d * 14.0) * smoothstep(0.55, 1.4, lum) * 0.35;
	float a = core * 0.98 + halo;
	if (a < 0.04 || d > soft_radius) {
		discard;
	}
	vec3 col = COLOR.rgb;
	ALBEDO = col;
	EMISSION = col * (1.35 + core * 2.2);
	ALPHA = clamp(a, 0.0, 1.0);
}
