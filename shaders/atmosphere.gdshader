shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, specular_disabled;

uniform vec4 atmo_color : source_color = vec4(0.35, 0.55, 0.95, 1.0);
uniform float intensity = 0.85;
uniform float power = 3.2;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, power);
	float a = rim * intensity;
	ALBEDO = atmo_color.rgb;
	EMISSION = atmo_color.rgb * (1.2 + rim * 2.0);
	ALPHA = clamp(a, 0.0, 0.9);
}
