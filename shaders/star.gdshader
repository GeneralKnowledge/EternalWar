shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 star_color : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform float emission_energy = 4.0;
uniform float corona = 0.35;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 2.0);
	vec3 col = star_color.rgb;
	ALBEDO = col;
	EMISSION = col * (emission_energy + rim * corona * 6.0);
}
