shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, specular_disabled;

uniform vec4 star_color : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform float emission_energy = 5.0;
uniform float corona = 0.55;
uniform float core_hot = 1.35;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 1.6);
	float core = pow(facing, 0.45);
	vec3 col = star_color.rgb;
	vec3 hot = mix(col, vec3(1.0, 0.98, 0.92), 0.65);
	ALBEDO = mix(col, hot, core);
	EMISSION = hot * (emission_energy * core_hot * (0.55 + core * 0.9))
		+ col * rim * corona * 8.0;
}
