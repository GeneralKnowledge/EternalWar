//! Bulk TRAVEL integration — pure math, no Godot types in the core loop.

use godot::builtin::{Dictionary, PackedFloat32Array, PackedInt32Array};
use std::time::Instant;

/// Status: still moving.
pub const STATUS_TRAVELING: i32 = 0;
/// Status: arrived this step (dist <= arrive).
pub const STATUS_ARRIVED: i32 = 1;
/// Status: bad input (e.g. dest coincides / NaN).
pub const STATUS_INVALID: i32 = 2;

/// Core travel step over SoA buffers. All vec3 packs are length `n * 3`.
pub fn integrate_travel(
	positions: &mut [f32],
	headings: &mut [f32],
	velocities: &mut [f32],
	destinations: &[f32],
	speeds: &[f32],
	arrive: &[f32],
	dt: f32,
	status: &mut [i32],
) {
	let n = speeds.len();
	debug_assert_eq!(positions.len(), n * 3);
	debug_assert_eq!(headings.len(), n * 3);
	debug_assert_eq!(velocities.len(), n * 3);
	debug_assert_eq!(destinations.len(), n * 3);
	debug_assert_eq!(arrive.len(), n);
	debug_assert_eq!(status.len(), n);

	for i in 0..n {
		let i3 = i * 3;
		let px = positions[i3];
		let py = positions[i3 + 1];
		let pz = positions[i3 + 2];
		let dx = destinations[i3] - px;
		let dy = destinations[i3 + 1] - py;
		let dz = destinations[i3 + 2] - pz;
		let dist_sq = dx * dx + dy * dy + dz * dz;
		if !dist_sq.is_finite() {
			status[i] = STATUS_INVALID;
			continue;
		}
		let dist = dist_sq.sqrt();
		let arr = arrive[i];
		if dist <= arr {
			status[i] = STATUS_ARRIVED;
			velocities[i3] = 0.0;
			velocities[i3 + 1] = 0.0;
			velocities[i3 + 2] = 0.0;
			continue;
		}
		let inv = 1.0 / dist;
		let dir_x = dx * inv;
		let dir_y = dy * inv;
		let dir_z = dz * inv;
		headings[i3] = dir_x;
		headings[i3 + 1] = dir_y;
		headings[i3 + 2] = dir_z;
		let speed = speeds[i];
		let max_step = (dist - arr * 0.5).max(0.0);
		let step = (speed * dt).min(max_step);
		positions[i3] = px + dir_x * step;
		positions[i3 + 1] = py + dir_y * step;
		positions[i3 + 2] = pz + dir_z * step;
		velocities[i3] = dir_x * speed;
		velocities[i3 + 1] = dir_y * speed;
		velocities[i3 + 2] = dir_z * speed;
		status[i] = STATUS_TRAVELING;
	}
}

pub fn integrate_travel_godot(
	mut positions: PackedFloat32Array,
	mut headings: PackedFloat32Array,
	mut velocities: PackedFloat32Array,
	destinations: PackedFloat32Array,
	speeds: PackedFloat32Array,
	arrive: PackedFloat32Array,
	dt: f32,
) -> Dictionary {
	let n = speeds.len();
	let mut status = vec![STATUS_INVALID; n];

	let pos_slice = positions.as_mut_slice();
	let head_slice = headings.as_mut_slice();
	let vel_slice = velocities.as_mut_slice();
	let dest_slice = destinations.as_slice();
	let speed_slice = speeds.as_slice();
	let arrive_slice = arrive.as_slice();

	if pos_slice.len() != n * 3
		|| head_slice.len() != n * 3
		|| vel_slice.len() != n * 3
		|| dest_slice.len() != n * 3
		|| arrive_slice.len() != n
	{
		let mut out = Dictionary::new();
		out.set("ok", false);
		out.set("error", "length mismatch");
		out.set("positions", positions);
		out.set("headings", headings);
		out.set("velocities", velocities);
		out.set("status", PackedInt32Array::new());
		return out;
	}

	integrate_travel(
		pos_slice,
		head_slice,
		vel_slice,
		dest_slice,
		speed_slice,
		arrive_slice,
		dt,
		&mut status,
	);

	let mut status_arr = PackedInt32Array::new();
	status_arr.resize(n);
	status_arr.as_mut_slice().copy_from_slice(&status);

	let mut out = Dictionary::new();
	out.set("ok", true);
	out.set("positions", positions);
	out.set("headings", headings);
	out.set("velocities", velocities);
	out.set("status", status_arr);
	out
}

pub fn bench_travel(n: usize, iters: usize) -> f32 {
	let mut positions = vec![0.0f32; n * 3];
	let mut headings = vec![0.0f32; n * 3];
	let mut velocities = vec![0.0f32; n * 3];
	let mut destinations = vec![0.0f32; n * 3];
	let speeds = vec![80.0f32; n];
	let arrive = vec![35.0f32; n];
	let mut status = vec![0i32; n];
	for i in 0..n {
		let i3 = i * 3;
		positions[i3] = (i as f32) * 0.1;
		destinations[i3] = positions[i3] + 500.0;
		destinations[i3 + 1] = 10.0;
		destinations[i3 + 2] = 20.0;
	}
	let t0 = Instant::now();
	for _ in 0..iters {
		integrate_travel(
			&mut positions,
			&mut headings,
			&mut velocities,
			&destinations,
			&speeds,
			&arrive,
			0.05,
			&mut status,
		);
	}
	t0.elapsed().as_secs_f32() * 1000.0
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn arrives_when_close() {
		let mut positions = vec![0.0, 0.0, 0.0];
		let mut headings = vec![0.0, 0.0, -1.0];
		let mut velocities = vec![1.0, 0.0, 0.0];
		let destinations = vec![10.0, 0.0, 0.0];
		let speeds = vec![50.0];
		let arrive = vec![35.0];
		let mut status = vec![0];
		integrate_travel(
			&mut positions,
			&mut headings,
			&mut velocities,
			&destinations,
			&speeds,
			&arrive,
			0.05,
			&mut status,
		);
		assert_eq!(status[0], STATUS_ARRIVED);
		assert_eq!(velocities, vec![0.0, 0.0, 0.0]);
	}

	#[test]
	fn moves_toward_destination() {
		let mut positions = vec![0.0, 0.0, 0.0];
		let mut headings = vec![0.0, 0.0, -1.0];
		let mut velocities = vec![0.0, 0.0, 0.0];
		let destinations = vec![1000.0, 0.0, 0.0];
		let speeds = vec![100.0];
		let arrive = vec![35.0];
		let mut status = vec![0];
		integrate_travel(
			&mut positions,
			&mut headings,
			&mut velocities,
			&destinations,
			&speeds,
			&arrive,
			0.05,
			&mut status,
		);
		assert_eq!(status[0], STATUS_TRAVELING);
		assert!((positions[0] - 5.0).abs() < 1e-3);
		assert!((headings[0] - 1.0).abs() < 1e-4);
	}
}
