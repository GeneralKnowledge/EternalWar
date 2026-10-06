shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, specular_disabled;

// Planetary limb — brighter on lit rim, thinner dark-side falloff (LT planet presentation).
uniform vec4 atmo_color : source_color = vec4(0.35, 0.55, 0.95, 1.0);
uniform float intensity = 0.95;
uniform float power = 2.6;
uniform vec3 light_dir = vec3(0.4, 0.7, 0.3);

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, power);
	float lit = clamp(dot(normalize(NORMAL), normalize(light_dir)), 0.0, 1.0);
	float day = mix(0.35, 1.15, lit);
	float a = rim * intensity * day;
	vec3 col = mix(atmo_color.rgb * 0.65, atmo_color.rgb, lit);
	ALBEDO = col;
	EMISSION = col * (1.0 + rim * 2.4 * day);
	ALPHA = clamp(a, 0.0, 0.92);
}
