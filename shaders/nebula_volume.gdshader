shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, specular_disabled;

// Bounded volumetric nebula — density(world_pos), not noise(UV).
// Raymarches only inside the mass sphere described by SkyComposition.

uniform vec3 volume_center = vec3(0.0);
uniform float volume_radius = 3000.0;
uniform vec3 primary_color = vec3(0.4, 0.3, 0.7);
uniform vec3 secondary_color = vec3(0.25, 0.35, 0.55);
uniform float seed = 0.0;
uniform float density_scale = 1.0;
uniform float core_strength = 0.55;
uniform float cavity_strength = 0.45;
uniform float filament_strength = 0.55;
uniform float emission_strength = 0.85;
uniform float absorb_strength = 1.15;
uniform vec3 elongation = vec3(1.0, 0.7, 1.15); // anisotropic large shape
uniform int ray_steps = 24;
uniform int debug_mode = 0; // 0=beauty, 1=density, 2=depth, 3=absorption

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(seed * 0.0011, seed * 0.0007, seed * 0.0013));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	mat3 m = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64)
	);
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = m * p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// Hierarchical density: large shape × mid clouds × filaments × cavities × core.
float sample_density(vec3 world_p, out float emit_w, out float absorb_w) {
	vec3 local = (world_p - volume_center) / max(volume_radius, 1.0);
	// Anisotropic envelope — avoid spherical smoke-ball
	vec3 stretched = local / max(elongation, vec3(0.2));
	float r = length(stretched);
	float large = 1.0 - smoothstep(0.35, 1.05, r);
	if (large <= 0.001) {
		emit_w = 0.0;
		absorb_w = 0.0;
		return 0.0;
	}

	vec3 q = local * 2.4 + vec3(seed * 0.01, seed * 0.017, seed * 0.013);
	float n_lo = fbm3(q * 0.85);
	float n_mid = fbm3(q * 2.4 + 11.0);
	float n_hi = fbm3(q * 6.2 + 29.0);

	float clouds = smoothstep(0.32, 0.78, n_lo * 0.62 + n_mid * 0.42);
	float filaments = smoothstep(0.5, 0.92, n_mid * 0.45 + n_hi * 0.55) * filament_strength;
	// Cavities: carve dark tunnels (not marble)
	float cavity = smoothstep(0.22, 0.68, abs(n_lo - 0.5) * 2.0 + n_mid * 0.25);
	float cavity_mask = mix(1.0, 1.0 - cavity_strength * 0.95, cavity);
	float core = exp(-r * r * mix(2.2, 5.5, 1.0 - core_strength)) * core_strength;

	float dens = large * (clouds * 0.55 + filaments * 0.45 + core * 0.5) * cavity_mask * density_scale;
	dens = max(dens, 0.0);

	// Emission ≠ density: thin wisps brighter; dense interiors darker
	emit_w = (filaments * 1.35 + core * 0.7 + clouds * 0.35) * (1.0 - clouds * 0.45);
	absorb_w = dens * (0.55 + clouds * 0.9) * absorb_strength;
	return dens;
}

bool intersect_sphere(vec3 ro, vec3 rd, vec3 c, float rad, out float t0, out float t1) {
	vec3 oc = ro - c;
	float b = dot(oc, rd);
	float disc = b * b - (dot(oc, oc) - rad * rad);
	if (disc < 0.0) {
		return false;
	}
	float s = sqrt(disc);
	t0 = -b - s;
	t1 = -b + s;
	return t1 > 0.0;
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(v_world - ro);

	float t0;
	float t1;
	float rad = volume_radius * 1.02;
	if (!intersect_sphere(ro, rd, volume_center, rad, t0, t1)) {
		discard;
	}
	t0 = max(t0, 0.0);
	if (t1 <= t0) {
		discard;
	}

	int steps = clamp(ray_steps, 8, 48);
	float dt = (t1 - t0) / float(steps);
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	float dens_acc = 0.0;
	float depth_acc = 0.0;
	float abs_acc = 0.0;

	for (int i = 0; i < 48; i++) {
		if (i >= steps || alpha > 0.92) {
			break;
		}
		float t = t0 + (float(i) + 0.5) * dt;
		vec3 p = ro + rd * t;
		float emit_w;
		float absorb_w;
		float d = sample_density(p, emit_w, absorb_w);
		if (d <= 0.0005) {
			continue;
		}
		float step_a = 1.0 - exp(-absorb_w * dt * 0.00115);
		vec3 tint = mix(secondary_color, primary_color, clamp(emit_w, 0.0, 1.0));
		// Soft self-shadow: denser samples slightly cooler/darker
		tint *= mix(1.15, 0.55, clamp(d * 1.2, 0.0, 1.0));
		vec3 emit = tint * emit_w * emission_strength * d * dt * 0.00135;
		col += (1.0 - alpha) * emit;
		alpha += (1.0 - alpha) * step_a;
		dens_acc += d * dt;
		depth_acc += t * d * dt;
		abs_acc += step_a;
	}

	if (alpha < 0.02 && dens_acc < 0.01) {
		discard;
	}

	if (debug_mode == 1) {
		float dnorm = clamp(dens_acc * 0.00025, 0.0, 1.0);
		ALBEDO = vec3(dnorm);
		EMISSION = vec3(dnorm);
		ALPHA = max(dnorm, 0.15);
		return;
	}
	if (debug_mode == 2) {
		float davg = dens_acc > 0.001 ? depth_acc / dens_acc : t0;
		float dn = clamp((davg - t0) / max(t1 - t0, 1.0), 0.0, 1.0);
		ALBEDO = vec3(dn, 0.2, 1.0 - dn);
		EMISSION = ALBEDO * 0.6;
		ALPHA = 0.65;
		return;
	}
	if (debug_mode == 3) {
		float a = clamp(abs_acc, 0.0, 1.0);
		ALBEDO = vec3(a, a * 0.4, 0.1);
		EMISSION = ALBEDO;
		ALPHA = max(a, 0.2);
		return;
	}

	ALBEDO = col;
	EMISSION = col * 1.15;
	ALPHA = clamp(alpha, 0.0, 0.88);
}
