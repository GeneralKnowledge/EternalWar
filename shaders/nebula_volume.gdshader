shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, specular_disabled;

// Bounded volumetric nebula — density(world_pos), not noise(UV).
// Anisotropic filament ridges + domain warp; emission ≠ density.

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
uniform vec3 elongation = vec3(1.0, 0.7, 1.15);
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
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		p = vec3(p.y + p.z * 0.6, p.z - p.x * 0.8, p.x * 0.6 + p.y * 0.48);
		a *= 0.5;
	}
	return v;
}

vec3 sample_density_pack(vec3 world_p) {
	// returns dens, emit_w, absorb_w
	vec3 local = (world_p - volume_center) / max(volume_radius, 1.0);
	// Stronger domain warp breaks concentric radial shells
	vec3 warp = vec3(
		fbm3(local * 1.3 + vec3(seed * 0.01, 2.1, 0.0)),
		fbm3(local * 1.1 + vec3(0.0, seed * 0.013, 4.7)),
		fbm3(local * 1.4 + vec3(3.3, 0.0, seed * 0.017))
	) - 0.5;
	local += warp * 0.42;
	vec3 stretched = local / max(elongation, vec3(0.2));
	float r = length(stretched);
	float large = 1.0 - smoothstep(0.12, 1.05, r + warp.x * 0.18);
	if (large <= 0.001) {
		return vec3(0.0);
	}

	vec3 q = local * 1.8 + vec3(seed * 0.01, seed * 0.017, seed * 0.013);
	float n_lo = fbm3(q * 0.7);
	float n_mid = fbm3(q * 2.1 + 11.0);
	float n_hi = fbm3(q * 5.4 + 29.0);

	// Noise-modulate envelope so large scale is not a pure sphere
	large *= smoothstep(0.08, 0.55, n_lo * 0.65 + n_mid * 0.25);

	float clouds = smoothstep(0.18, 0.7, n_lo * 0.6 + n_mid * 0.45);

	// Anisotropic filament ridges (elongated mid-frequency edges, not isotropic fill)
	vec3 q_fil = vec3(q.x * elongation.z * 1.4, q.y * 2.6, q.z * elongation.x * 1.2);
	float n_fil = fbm3(q_fil * 3.8 + 19.0);
	float n_fil2 = fbm3(q_fil * 7.2 + 41.0);
	float ridge = 1.0 - abs(n_fil * 2.0 - 1.0);
	float ridge2 = 1.0 - abs(n_fil2 * 2.0 - 1.0);
	float filaments = smoothstep(0.36, 0.7, ridge * 0.65 + ridge2 * 0.25 + n_mid * 0.25) * filament_strength;
	float filament_ridges = pow(smoothstep(0.5, 0.9, ridge * 0.7 + ridge2 * 0.4), 1.45) * filament_strength;

	// Tight cavities — dark lanes without washing the mass
	float cavity = smoothstep(0.55, 0.92, abs(n_lo - 0.5) * 2.2);
	float lane = smoothstep(0.65, 0.95, abs(n_mid - 0.45) * 1.7);
	float cavity_mask = mix(1.0, 1.0 - cavity_strength * 0.38, cavity * 0.8 + lane * 0.3);

	float core = exp(-r * r * mix(1.4, 3.8, 1.0 - core_strength)) * core_strength;
	core *= smoothstep(0.08, 0.5, n_lo + warp.y * 0.25);

	// Structure as edges: lower filament density, higher filament emission
	float dens = large * (
		0.12 + clouds * 0.55 + filaments * 0.5 + filament_ridges * 0.42 + core * 0.55
	) * cavity_mask * density_scale;
	dens = max(dens, 0.0);
	float emit_w = (
		filaments * 2.4 + filament_ridges * 2.0 + core * 0.95 + clouds * 0.22
	) * mix(1.2, 0.5, clouds);
	float absorb_w = dens * (0.55 + clouds * 0.65 + filament_ridges * 0.3) * absorb_strength;
	return vec3(dens, emit_w, absorb_w);
}

void fragment() {
	vec3 ro = INV_VIEW_MATRIX[3].xyz;
	vec3 rd = normalize(v_world - ro);

	vec3 oc = ro - volume_center;
	float rad = volume_radius * 1.02;
	float b = dot(oc, rd);
	float disc = b * b - (dot(oc, oc) - rad * rad);
	if (disc < 0.0) {
		discard;
	}
	float s = sqrt(disc);
	float t0 = max(-b - s, 0.0);
	float t1 = -b + s;
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
		if (i < steps && alpha <= 0.90) {
			// Stronger jitter to break raymarch step banding / slices
			float jitter = hash13(rd * float(i + 1) + vec3(seed * 0.001)) * 0.85 - 0.2;
			float t = t0 + (float(i) + 0.5 + jitter) * dt;
			vec3 p = ro + rd * t;
			vec3 pack = sample_density_pack(p);
			float d = pack.x;
			float emit_w = pack.y;
			float absorb_w = pack.z;
			if (d > 0.0005) {
				float step_scale = dt * 0.0024;
				float step_a = 1.0 - exp(-absorb_w * step_scale);
				vec3 tint = mix(secondary_color, primary_color, clamp(emit_w, 0.0, 1.0));
				tint *= mix(1.1, 0.72, clamp(d * 0.7, 0.0, 1.0));
				// Soft-knee emission — avoid blown white cores that flatten mid-edges
				float e_lin = emit_w * emission_strength * d * step_scale * 1.55;
				vec3 emit = tint * (e_lin / (1.0 + e_lin * 1.8));
				col += (1.0 - alpha) * emit;
				alpha += (1.0 - alpha) * step_a;
				dens_acc += d * dt;
				depth_acc += t * d * dt;
				abs_acc += step_a;
			}
		}
	}

	if (alpha < 0.02 && dens_acc < 0.01) {
		discard;
	}

	vec3 out_alb = col;
	vec3 out_emi = col * 1.15;
	// Lower alpha cap so IFS sky colour shows through the mass
	float out_a = clamp(alpha, 0.0, 0.72);

	if (debug_mode == 1) {
		float dnorm = clamp(dens_acc * 0.00025, 0.0, 1.0);
		out_alb = vec3(dnorm);
		out_emi = vec3(dnorm);
		out_a = max(dnorm, 0.15);
	} else if (debug_mode == 2) {
		float davg = dens_acc > 0.001 ? depth_acc / dens_acc : t0;
		float dn = clamp((davg - t0) / max(t1 - t0, 1.0), 0.0, 1.0);
		out_alb = vec3(dn, 0.2, 1.0 - dn);
		out_emi = out_alb * 0.6;
		out_a = 0.65;
	} else if (debug_mode == 3) {
		float aa = clamp(abs_acc, 0.0, 1.0);
		out_alb = vec3(aa, aa * 0.4, 0.1);
		out_emi = out_alb;
		out_a = max(aa, 0.2);
	}

	ALBEDO = out_alb;
	EMISSION = out_emi;
	ALPHA = out_a;
}
