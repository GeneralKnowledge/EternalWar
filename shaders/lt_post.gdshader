shader_type canvas_item;

// LT-inspired post: vignette + expmap + soft bloom2 (no Compatibility hex tiles).
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float vignette_strength : hint_range(0.0, 0.6) = 0.25;
uniform float expmap_k : hint_range(0.5, 4.0) = 2.3;
uniform float expmap_p : hint_range(0.5, 2.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float bloom_threshold : hint_range(0.0, 2.0) = 0.72;
uniform float bloom_intensity : hint_range(0.0, 1.5) = 0.45;
uniform float bloom_radius : hint_range(0.5, 8.0) = 3.5;

vec3 bright_pass(vec3 c) {
	float l = max(c.r, max(c.g, c.b));
	float k = smoothstep(bloom_threshold, bloom_threshold + 0.55, l);
	return c * k;
}

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(SCREEN_TEXTURE, 0));
	vec3 c = textureLod(SCREEN_TEXTURE, SCREEN_UV, 0.0).rgb;

	// Soft dual-pass-ish bloom via 9-tap + wider ring (bloom2 spirit, no hex bokeh).
	vec3 bloom = vec3(0.0);
	float wsum = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			float w = 1.0 / (1.0 + float(x * x + y * y));
			vec2 o = vec2(float(x), float(y)) * px * bloom_radius;
			bloom += bright_pass(textureLod(SCREEN_TEXTURE, SCREEN_UV + o, 0.0).rgb) * w;
			wsum += w;
		}
	}
	bloom /= max(wsum, 1e-4);
	// Wider halo ring
	vec3 halo = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398; // pi/4
		vec2 o = vec2(cos(a), sin(a)) * px * bloom_radius * 2.4;
		halo += bright_pass(textureLod(SCREEN_TEXTURE, SCREEN_UV + o, 0.0).rgb);
	}
	halo *= 0.125;
	c += (bloom * 0.75 + halo * 0.45) * bloom_intensity * strength;

	vec3 mapped = 1.0 - exp(-expmap_k * pow(max(c, vec3(0.0)), vec3(expmap_p)));
	vec3 outc = mix(c, mapped, 0.55 * strength);
	vec2 d = SCREEN_UV * 2.0 - 1.0;
	float vig = 1.0 - vignette_strength * strength * dot(d, d);
	outc *= clamp(vig, 0.0, 1.0);
	COLOR = vec4(outc, 1.0);
}
