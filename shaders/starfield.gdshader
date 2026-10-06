shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_add, specular_disabled;

// Camera-facing star billboard with soft disc + magnitude.
uniform float soft_radius = 0.48;

void vertex() {
	// Preserve instance scale, force camera-facing axes (Godot MultiMesh-safe).
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
	float core = exp(-d * d * 14.0);
	float halo = exp(-d * d * 4.0);
	float a = core * 0.95 + halo * 0.35;
	if (a < 0.04 || d > soft_radius) {
		discard;
	}
	vec3 col = COLOR.rgb;
	ALBEDO = col;
	EMISSION = col * (2.0 + core * 5.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
