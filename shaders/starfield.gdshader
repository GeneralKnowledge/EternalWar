shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix, specular_disabled;

// Camera-facing star billboard with soft disc + magnitude.
uniform float soft_radius = 0.42;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 mv = VIEW_MATRIX * vec4(world_pos, 1.0);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec2 local = VERTEX.xy;
	mv.xy += local * vec2(sx, sy);
	MODELVIEW_MATRIX = mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		mv
	);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float core = 1.0 - smoothstep(0.0, soft_radius * 0.45, d);
	float halo = 1.0 - smoothstep(0.0, soft_radius, d);
	float a = max(core * 0.95, halo * 0.55);
	if (a < 0.02) {
		discard;
	}
	vec3 col = COLOR.rgb;
	ALBEDO = col;
	EMISSION = col * (1.4 + core * 3.5);
	ALPHA = a;
}
