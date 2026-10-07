//! Limit Theory–style nebula IFS bake (gen/nebula.glsl `generate(dir)`).
//!
//! Bakes an equirectangular panorama once per system seed so Godot can sample
//! a PanoramaSky instead of evaluating heavy IFS live on Compatibility.

use godot::builtin::{Dictionary, PackedFloat32Array};
use rayon::prelude::*;
use std::f32::consts::{PI, TAU};
use std::time::Instant;

const K_SCALE: f32 = 0.040;
const K_EXTENT: f32 = 12.0;
const K_BRIGHT_CONSTANT: f32 = 0.075;
const K_BRIGHT_CELL: f32 = 0.100;
const K_ABSORB: f32 = 3.6;
const ABSORB_SCALE: f32 = 0.55;

#[derive(Clone, Copy)]
pub struct NebulaParams {
	pub seed: f32,
	pub roughness: f32,
	pub primary: [f32; 3],
	pub secondary: [f32; 3],
	pub bg: [f32; 3],
	pub star_dir: [f32; 3],
	pub lut_r: [f32; 3],
	pub lut_g: [f32; 3],
	pub lut_b: [f32; 3],
	pub lut_rg_mid: [f32; 2],
	pub lut_b_edge: [f32; 2],
	pub samples: usize,
	pub iterations: usize,
}

fn fract(x: f32) -> f32 {
	x - x.floor()
}

fn mix(a: f32, b: f32, t: f32) -> f32 {
	a + (b - a) * t
}

fn clamp01(x: f32) -> f32 {
	x.clamp(0.0, 1.0)
}

fn hash11(x: f32, seed: f32) -> f32 {
	fract((x * 127.1 + seed * 0.13).sin() * 43758.5453)
}

fn hash21(x: f32, y: f32, seed: f32) -> f32 {
	let mut px = fract(x * 123.34 + seed * 0.01);
	let mut py = fract(y * 456.21 + seed * 0.01);
	let d = px * (px + 45.32) + py * (py + 45.32);
	px = fract(px + d);
	py = fract(py + d);
	fract(px * py)
}

fn noise4(x: f32, seed: f32) -> f32 {
	let i = x.floor();
	let mut f = x - i;
	f = f * f * (3.0 - 2.0 * f);
	mix(hash11(i, seed), hash11(i + 1.0, seed), f)
}

fn smooth_noise3(p: [f32; 3], seed: f32) -> f32 {
	let ix = p[0].floor();
	let iy = p[1].floor();
	let iz = p[2].floor();
	let mut fx = p[0] - ix;
	let mut fy = p[1] - iy;
	let mut fz = p[2] - iz;
	fx = fx * fx * (3.0 - 2.0 * fx);
	fy = fy * fy * (3.0 - 2.0 * fy);
	fz = fz * fz * (3.0 - 2.0 * fz);
	let z0 = iz * 19.0;
	let z1 = (iz + 1.0) * 19.0;
	let n000 = hash21(ix, iy + z0, seed);
	let n100 = hash21(ix + 1.0, iy + z0, seed);
	let n010 = hash21(ix, iy + 1.0 + z0, seed);
	let n110 = hash21(ix + 1.0, iy + 1.0 + z0, seed);
	let n001 = hash21(ix, iy + z1, seed);
	let n101 = hash21(ix + 1.0, iy + z1, seed);
	let n011 = hash21(ix, iy + 1.0 + z1, seed);
	let n111 = hash21(ix + 1.0, iy + 1.0 + z1, seed);
	let nx00 = mix(n000, n100, fx);
	let nx10 = mix(n010, n110, fx);
	let nx01 = mix(n001, n101, fx);
	let nx11 = mix(n011, n111, fx);
	mix(mix(nx00, nx10, fy), mix(nx01, nx11, fy), fz)
}

fn f_smooth_noise(p: [f32; 3], seed: f32, octaves: usize, lac: f32) -> f32 {
	let mut sum = 0.0;
	let mut amp = 1.0;
	let mut norm = 0.0;
	let mut q = p;
	for _ in 0..octaves.min(6) {
		sum += amp * smooth_noise3(q, seed);
		norm += amp;
		amp *= 0.5;
		q = [q[0] * lac, q[1] * lac, q[2] * lac];
	}
	sum / norm.max(1e-4)
}

fn magic(p: [f32; 3], seed: f32, roughness: f32, iterations: usize) -> f32 {
	let mut z = [0.53 + p[0], 0.53 + p[1], 0.53 + p[2], 0.0];
	let mut a = 0.0;
	let mut l = 0.0;
	let mut tw = 0.0;
	let mut w = 1.0;
	let mut c = [0.5, 0.55, 0.45, 0.6];
	for i in 0..iterations.min(30) {
		let m = z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3];
		let inv = 1.0 / m.max(1e-8);
		z = [
			z[0].abs() * inv - c[0],
			z[1].abs() * inv - c[1],
			z[2].abs() * inv - c[2],
			z[3].abs() * inv - c[3],
		];
		let n = 0.02 * (1.0e-10 + noise4(i as f32 + seed, seed)).ln();
		z[0] += n + 0.25 * z[0].sin();
		z[1] += n + 0.25 * z[1].sin();
		z[2] += n + 0.25 * z[2].sin();
		z[3] += n + 0.25 * z[3].sin();
		let lm = l - m;
		a += w * (-2.0 * lm * lm).exp();
		tw += w;
		if i > 3 {
			w *= roughness;
		}
		l = m;
		c = [c[1], c[2], c[3], c[0]];
	}
	let t = a / tw.max(1e-4);
	0.5 + 0.5 * (30.0 * t).cos().min((40.0 * t).sin())
}

fn bg_density(dir: [f32; 3], seed: f32) -> f32 {
	let p = [dir[0] * 4.0 + seed, dir[1] * 4.0 + seed, dir[2] * 4.0 + seed];
	K_BRIGHT_CONSTANT + K_BRIGHT_CELL * f_smooth_noise(p, seed, 6, 2.0)
}

fn lut1(t: f32, a: f32, b: f32, c: f32, d: f32, e: f32) -> f32 {
	let t = clamp01(t);
	if t < 0.25 {
		mix(a, b, t / 0.25)
	} else if t < 0.5 {
		mix(b, c, (t - 0.25) / 0.25)
	} else if t < 0.75 {
		mix(c, d, (t - 0.5) / 0.25)
	} else {
		mix(d, e, (t - 0.75) / 0.25)
	}
}

fn lut_wave(t: f32, p: &NebulaParams) -> [f32; 3] {
	let mut r = lut1(
		t,
		p.lut_r[0] * 0.35,
		p.lut_r[0],
		p.lut_rg_mid[0],
		p.lut_r[1],
		p.lut_r[2],
	);
	let mut g = lut1(
		t,
		p.lut_g[0] * 0.35,
		p.lut_g[0],
		p.lut_rg_mid[1],
		p.lut_g[1],
		p.lut_g[2],
	);
	let mut b = lut1(
		t,
		p.lut_b[0] * 0.4,
		p.lut_b_edge[0],
		p.lut_b[0],
		p.lut_b_edge[1],
		p.lut_b[2],
	);
	let mood = [
		mix(p.secondary[0], p.primary[0], t),
		mix(p.secondary[1], p.primary[1], t),
		mix(p.secondary[2], p.primary[2], t),
	];
	r = mix(r, mood[0], 0.22);
	g = mix(g, mood[1], 0.22);
	b = mix(b, mood[2], 0.22);
	r *= r.max(0.0).sqrt();
	g *= g.max(0.0).sqrt();
	b *= b.max(0.0).sqrt();
	[r, g, b]
}

fn normalize3(v: [f32; 3]) -> [f32; 3] {
	let len = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt().max(1e-8);
	[v[0] / len, v[1] / len, v[2] / len]
}

fn dot3(a: [f32; 3], b: [f32; 3]) -> f32 {
	a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

/// Direction-space IFS generate — matches live `deep_space_sky.gdshader` recipe.
pub fn generate(dir_in: [f32; 3], p: &NebulaParams) -> [f32; 3] {
	let dir = normalize3(dir_in);
	let mut c = {
		let d = bg_density(dir, p.seed) * 1.15;
		[d, d, d]
	};

	let m_sky = magic([dir[0] * 0.018, dir[1] * 0.018, dir[2] * 0.018], p.seed, p.roughness, p.iterations);
	let sky_t = (-m_sky * m_sky).exp();
	let sky_wave = lut_wave(sky_t, p);
	c[0] += sky_wave[0] * 0.035 + mix(p.secondary[0], p.primary[0], sky_t) * 0.03 * sky_t;
	c[1] += sky_wave[1] * 0.035 + mix(p.secondary[1], p.primary[1], sky_t) * 0.03 * sky_t;
	c[2] += sky_wave[2] * 0.035 + mix(p.secondary[2], p.primary[2], sky_t) * 0.03 * sky_t;

	let star = normalize3(p.star_dir);
	let dstar = (1.0 - dot3(dir, star)).max(0.0);
	let dd = 8.0 * (-(4096.0 * dstar).sqrt()).exp() + 4.0 * (-(1024.0 * dstar).sqrt().sqrt()).exp();
	c[0] += dd * p.primary[0];
	c[1] += dd * p.primary[1];
	c[2] += dd * p.primary[2];

	let march = [dir[0] * K_SCALE, dir[1] * K_SCALE, dir[2] * K_SCALE];
	let w = 1.0 / (p.samples.max(1) as f32);
	let mut emit_acc = [0.0, 0.0, 0.0];

	for i in 0..p.samples {
		let t_step = (i as f32 + 0.5) * w * K_EXTENT;
		let pos = [march[0] * t_step, march[1] * t_step, march[2] * t_step];
		let m = magic(pos, p.seed, p.roughness, p.iterations);
		let t = (-m * m).exp();
		let wave = lut_wave(t, p);

		let q = 1.2;
		let mut vs = [
			(-q * wave[0] * t).exp(),
			(-q * wave[1] * t).exp(),
			(-q * wave[2] * t).exp(),
		];
		let cavity = (-(8.0 * (t - 0.90).abs()).powf(0.75)).exp();
		let filament = (-(10.0 * (t - 0.88).abs()).powf(0.50)).exp();
		vs[0] -= 1.25 * cavity;
		vs[1] -= 1.25 * cavity;
		vs[2] -= 1.25 * cavity;

		let rings = 0.35 + 0.65 * ((48.0 * m).sin() * (36.0 * m).cos()).abs().powf(1.25);
		let gate = rings.clamp(0.08, 1.0);
		let mut filament_emit = [
			(0.70 * p.primary[0] * filament + 0.28 * p.secondary[0] * cavity) * gate,
			(0.70 * p.primary[1] * filament + 0.28 * p.secondary[1] * cavity) * gate,
			(0.70 * p.primary[2] * filament + 0.28 * p.secondary[2] * cavity) * gate,
		];
		vs[0] += filament_emit[0];
		vs[1] += filament_emit[1];
		vs[2] += filament_emit[2];

		for k in 0..3 {
			let absorb = vs[k].max(0.0);
			c[k] *= (-K_ABSORB * w * absorb * ABSORB_SCALE).exp();
			filament_emit[k] *= wave[k];
			emit_acc[k] += filament_emit[k] * w * 0.85;
		}
	}

	c[0] = (c[0] + emit_acc[0]).max(0.0);
	c[1] = (c[1] + emit_acc[1]).max(0.0);
	c[2] = (c[2] + emit_acc[2]).max(0.0);
	for k in 0..3 {
		c[k] = mix(p.bg[k] * 0.40, c[k], 0.96) * 1.45;
		c[k] = c[k].max(p.bg[k] * 0.18);
	}
	c
}

/// Godot panorama convention: v=0 at +Y, u wraps longitude.
fn dir_from_equirect(u: f32, v: f32) -> [f32; 3] {
	let theta = v * PI;
	let phi = u * TAU - PI;
	let st = theta.sin();
	[st * phi.sin(), theta.cos(), -st * phi.cos()]
}

/// Bake equirect RGBAF floats (length = width * height * 4).
pub fn bake_panorama(width: usize, height: usize, p: &NebulaParams) -> Vec<f32> {
	let w = width.max(8);
	let h = height.max(4);
	let mut rgba = vec![0.0f32; w * h * 4];
	rgba.par_chunks_mut(w * 4)
		.enumerate()
		.for_each(|(y, row)| {
			let v = (y as f32 + 0.5) / h as f32;
			for x in 0..w {
				let u = (x as f32 + 0.5) / w as f32;
				let dir = dir_from_equirect(u, v);
				let c = generate(dir, p);
				let i = x * 4;
				row[i] = c[0];
				row[i + 1] = c[1];
				row[i + 2] = c[2];
				row[i + 3] = 1.0;
			}
		});
	rgba
}

/// Packed params layout (length ≥ 27):
/// 0 width, 1 height, 2 samples, 3 iterations, 4 seed, 5 roughness,
/// 6..8 primary, 9..11 secondary, 12..14 bg, 15..17 star_dir,
/// 18..20 lut_r, 21..23 lut_g, 24..26 lut_b,
/// 27..28 lut_rg_mid, 29..30 lut_b_edge
pub fn bake_nebula_panorama_godot(params: PackedFloat32Array) -> Dictionary {
	let mut out = Dictionary::new();
	if params.len() < 27 {
		out.set("ok", false);
		out.set("error", "params length < 27");
		return out;
	}
	let get = |i: usize| params.get(i).unwrap_or(0.0);
	let w = (get(0) as i32).clamp(16, 2048) as usize;
	let h = (get(1) as i32).clamp(8, 1024) as usize;
	if w * h > 2048 * 1024 {
		out.set("ok", false);
		out.set("error", "resolution too large");
		return out;
	}
	let p = NebulaParams {
		seed: get(4),
		roughness: get(5).clamp(0.35, 0.95),
		primary: [get(6), get(7), get(8)],
		secondary: [get(9), get(10), get(11)],
		bg: [get(12), get(13), get(14)],
		star_dir: [get(15), get(16), get(17)],
		lut_r: [get(18), get(19), get(20)],
		lut_g: [get(21), get(22), get(23)],
		lut_b: [get(24), get(25), get(26)],
		lut_rg_mid: [
			if params.len() > 28 { get(27) } else { 0.45 },
			if params.len() > 28 { get(28) } else { 0.4 },
		],
		lut_b_edge: [
			if params.len() > 30 { get(29) } else { 0.3 },
			if params.len() > 30 { get(30) } else { 0.7 },
		],
		samples: (get(2) as i32).clamp(8, 128) as usize,
		iterations: (get(3) as i32).clamp(8, 30) as usize,
	};
	let t0 = Instant::now();
	let rgba = bake_panorama(w, h, &p);
	let ms = t0.elapsed().as_secs_f32() * 1000.0;
	let mut packed = PackedFloat32Array::new();
	packed.resize(rgba.len());
	{
		let slice = packed.as_mut_slice();
		slice.copy_from_slice(&rgba);
	}
	out.set("ok", true);
	out.set("width", w as i32);
	out.set("height", h as i32);
	out.set("rgba", packed);
	out.set("ms", ms);
	out.set("backend", "rust");
	out
}

#[cfg(test)]
mod tests {
	use super::*;

	fn test_params() -> NebulaParams {
		NebulaParams {
			seed: 42.0,
			roughness: 0.72,
			primary: [0.25, 0.55, 0.55],
			secondary: [0.15, 0.35, 0.40],
			bg: [0.02, 0.03, 0.04],
			star_dir: [0.2, 0.55, 0.15],
			lut_r: [0.2, 0.55, 0.9],
			lut_g: [0.25, 0.5, 0.75],
			lut_b: [0.35, 0.55, 0.85],
			lut_rg_mid: [0.45, 0.4],
			lut_b_edge: [0.3, 0.7],
			samples: 24,
			iterations: 16,
		}
	}

	#[test]
	fn generate_is_finite_and_lit() {
		let p = test_params();
		let c = generate([0.2, 0.5, 0.8], &p);
		assert!(c[0].is_finite() && c[1].is_finite() && c[2].is_finite());
		assert!(c[0] + c[1] + c[2] > 0.05);
	}

	#[test]
	fn bake_panorama_size() {
		let p = test_params();
		let rgba = bake_panorama(32, 16, &p);
		assert_eq!(rgba.len(), 32 * 16 * 4);
		let mean: f32 = rgba.iter().step_by(4).map(|r| *r).sum::<f32>() / (32.0 * 16.0);
		assert!(mean > 0.01, "mean={mean}");
	}
}
