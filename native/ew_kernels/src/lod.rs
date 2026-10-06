//! Bulk distance → LOD tier classification (VisualLOD thresholds).

use godot::builtin::{Dictionary, PackedFloat32Array, PackedInt32Array, Vector3};
use std::time::Instant;

/// Default EternalWar VisualLOD distance thresholds (must match `visual_lod.gd`).
pub const DIST_FULL: f32 = 280.0;
pub const DIST_SIMPLE: f32 = 550.0;
pub const DIST_LOW: f32 = 1100.0;
pub const DIST_BATCH: f32 = 4500.0;

pub const LOD_FULL: i32 = 0;
pub const LOD_SIMPLE: i32 = 1;
pub const LOD_LOW: i32 = 2;
pub const LOD_BATCH: i32 = 3;
pub const LOD_SIM: i32 = 4;

pub fn lod_for_distance(dist: f32, full: f32, simple: f32, low: f32, batch: f32) -> i32 {
	if dist < full {
		LOD_FULL
	} else if dist < simple {
		LOD_SIMPLE
	} else if dist < low {
		LOD_LOW
	} else if dist < batch {
		LOD_BATCH
	} else {
		LOD_SIM
	}
}

/// Classify n positions relative to camera. Writes lod + distance packs.
pub fn classify_lod(
	positions: &[f32],
	cam_x: f32,
	cam_y: f32,
	cam_z: f32,
	full: f32,
	simple: f32,
	low: f32,
	batch: f32,
	lods: &mut [i32],
	dists: &mut [f32],
) {
	let n = lods.len();
	debug_assert_eq!(positions.len(), n * 3);
	debug_assert_eq!(dists.len(), n);
	for i in 0..n {
		let i3 = i * 3;
		let dx = positions[i3] - cam_x;
		let dy = positions[i3 + 1] - cam_y;
		let dz = positions[i3 + 2] - cam_z;
		let dist = (dx * dx + dy * dy + dz * dz).sqrt();
		dists[i] = dist;
		lods[i] = lod_for_distance(dist, full, simple, low, batch);
	}
}

pub fn classify_lod_godot(
	positions: PackedFloat32Array,
	camera: Vector3,
	thresholds: PackedFloat32Array,
) -> Dictionary {
	let n = positions.len() / 3;
	let mut out = Dictionary::new();
	if positions.len() != n * 3 || n == 0 {
		out.set("ok", false);
		out.set("lods", PackedInt32Array::new());
		out.set("distances", PackedFloat32Array::new());
		return out;
	}
	let full = thresholds.get(0).unwrap_or(DIST_FULL);
	let simple = thresholds.get(1).unwrap_or(DIST_SIMPLE);
	let low = thresholds.get(2).unwrap_or(DIST_LOW);
	let batch = thresholds.get(3).unwrap_or(DIST_BATCH);

	let mut lods = PackedInt32Array::new();
	let mut dists = PackedFloat32Array::new();
	lods.resize(n);
	dists.resize(n);
	classify_lod(
		positions.as_slice(),
		camera.x,
		camera.y,
		camera.z,
		full,
		simple,
		low,
		batch,
		lods.as_mut_slice(),
		dists.as_mut_slice(),
	);
	out.set("ok", true);
	out.set("lods", lods);
	out.set("distances", dists);
	out
}

pub fn bench_classify(n: usize, iters: usize) -> f32 {
	let mut positions = vec![0.0f32; n * 3];
	let mut lods = vec![0i32; n];
	let mut dists = vec![0.0f32; n];
	for i in 0..n {
		positions[i * 3] = (i as f32) * 3.0;
		positions[i * 3 + 2] = (i as f32) * 0.5;
	}
	let t0 = Instant::now();
	for _ in 0..iters {
		classify_lod(
			&positions,
			0.0,
			0.0,
			0.0,
			DIST_FULL,
			DIST_SIMPLE,
			DIST_LOW,
			DIST_BATCH,
			&mut lods,
			&mut dists,
		);
	}
	t0.elapsed().as_secs_f32() * 1000.0
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn tiers_match_visual_lod() {
		assert_eq!(lod_for_distance(100.0, DIST_FULL, DIST_SIMPLE, DIST_LOW, DIST_BATCH), LOD_FULL);
		assert_eq!(lod_for_distance(400.0, DIST_FULL, DIST_SIMPLE, DIST_LOW, DIST_BATCH), LOD_SIMPLE);
		assert_eq!(lod_for_distance(800.0, DIST_FULL, DIST_SIMPLE, DIST_LOW, DIST_BATCH), LOD_LOW);
		assert_eq!(lod_for_distance(2000.0, DIST_FULL, DIST_SIMPLE, DIST_LOW, DIST_BATCH), LOD_BATCH);
		assert_eq!(lod_for_distance(9000.0, DIST_FULL, DIST_SIMPLE, DIST_LOW, DIST_BATCH), LOD_SIM);
	}
}
