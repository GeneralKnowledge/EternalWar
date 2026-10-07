shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_opaque, specular_disabled;

// Limit Theory effect/explosion.glsl — expanding noisy disc.
uniform float age = 0.15;
uniform float seed = 1.0;
uniform float anim_speed = 0.4;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise2(p);
		p *= 2.0;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float t = anim_speed * age;
	float r = length(uv);
	float rd = 0.3 * (2.0 * fbm(2.0 * uv + 1337.0 * seed + 39.0) - 1.0);
	r = pow(max(0.0, r + rd - (1.0 - exp(-t))), 2.0);
	float a =
		10.0 * exp(-abs(128.0 * r)) +
		2.0 * exp(-abs(64.0 * r)) +
		0.2 * exp(-sqrt(16.0 * r));
	a *= 2.0 * fbm(2.0 * uv + 33.0);
	a *= exp(-5.0 * max(0.0, t));
	a *= 1.0 - exp(-32.0 * max(0.0, t));
	if (a < 0.02) {
		discard;
	}
	vec3 c = mix(mix(vec3(1.0, 0.2, 0.0), vec3(1.0, 0.5, 0.2), a), vec3(4.0, 2.0, 1.0), a);
	ALBEDO = c * a;
	EMISSION = c * a * 1.5;
	ALPHA = clamp(a, 0.0, 1.0);
}
