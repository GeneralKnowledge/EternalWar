shader_type canvas_item;
render_mode unshaded;

// Limit Theory post stack approximation (filter/vignette + filter/tonemap2 spirit).
// Vignette defaults: strength 0.25, hardness 20 (Renderer.lua / ImageFilter).
// Tonemap2: c = 1 - 1/(1 + K * pow(c, P)) with K=1.50, P=1.25 — mild so it
// complements Godot Environment filmic rather than replacing it twice hard.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.22;
uniform float vignette_hardness : hint_range(2.0, 32.0) = 18.0;
uniform float tonemap_mix : hint_range(0.0, 1.0) = 0.35;
uniform float tonemap_k = 1.50;
uniform float tonemap_p = 1.25;

void fragment() {
	vec3 c = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	c = max(c, vec3(0.0));
	vec3 mapped = vec3(1.0) - 1.0 / (vec3(1.0) + tonemap_k * pow(c + vec3(1e-5), vec3(tonemap_p)));
	c = mix(c, mapped, tonemap_mix);
	vec2 uvp = vec2(1.0) - 2.0 * abs(vec2(0.5) - SCREEN_UV);
	float a = 1.0;
	a *= 1.0 - vignette_strength * exp(-vignette_hardness * max(uvp.x, 1e-4));
	a *= 1.0 - vignette_strength * exp(-vignette_hardness * max(uvp.y, 1e-4));
	COLOR = vec4(c * a, 1.0);
}
