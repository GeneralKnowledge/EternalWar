shader_type canvas_item;

// LT-inspired post: vignette + mild expmap film curve (tonemap2 spirit).
// Compatibility-safe fullscreen pass — no glow hex tiles.
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float vignette_strength : hint_range(0.0, 0.6) = 0.25;
uniform float expmap_k : hint_range(0.5, 4.0) = 2.3;
uniform float expmap_p : hint_range(0.5, 2.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 c = textureLod(SCREEN_TEXTURE, SCREEN_UV, 0.0).rgb;
	// Mild expmap: 1 - exp(-k * c^p)
	vec3 mapped = 1.0 - exp(-expmap_k * pow(max(c, vec3(0.0)), vec3(expmap_p)));
	vec3 outc = mix(c, mapped, 0.55 * strength);
	// Pre-tonemap-ish vignette (LT Renderer vignette ≈ 0.25)
	vec2 d = SCREEN_UV * 2.0 - 1.0;
	float vig = 1.0 - vignette_strength * strength * dot(d, d);
	outc *= clamp(vig, 0.0, 1.0);
	COLOR = vec4(outc, 1.0);
}
