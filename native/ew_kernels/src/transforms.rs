//! MultiMesh Transform3D packing from SoA ship state.

use godot::builtin::{Basis, PackedFloat32Array, PackedInt32Array, Transform3D, Vector3};
use godot::classes::MultiMesh;
use godot::obj::Gd;
use std::time::Instant;

/// Pack n transforms into a flat f32 buffer (12 floats each) using Godot math types
/// so the layout matches MultiMesh / Transform3D exactly.
pub fn pack_ship_transforms(
	positions: &[f32],
	headings: &[f32],
	scales: &[f32],
	hidden: &[i32],
	out: &mut [f32],
) {
	let n = scales.len();
	debug_assert_eq!(positions.len(), n * 3);
	debug_assert_eq!(headings.len(), n * 3);
	debug_assert_eq!(hidden.len(), n);
	debug_assert_eq!(out.len(), n * 12);

	for i in 0..n {
		let i3 = i * 3;
		let o = i * 12;
		let xform = make_transform(
			positions[i3],
			positions[i3 + 1],
			positions[i3 + 2],
			headings[i3],
			headings[i3 + 1],
			headings[i3 + 2],
			scales[i],
			hidden[i] != 0,
		);
		write_transform(xform, &mut out[o..o + 12]);
	}
}

fn make_transform(
	px: f32,
	py: f32,
	pz: f32,
	hx: f32,
	hy: f32,
	hz: f32,
	scale: f32,
	hidden: bool,
) -> Transform3D {
	let pos = Vector3::new(px, py, pz);
	if hidden {
		return Transform3D::new(Basis::from_scale(Vector3::ZERO), pos);
	}
	let mut heading = Vector3::new(hx, hy, hz);
	if heading.length_squared() < 0.001 {
		heading = Vector3::new(0.0, 0.0, -1.0);
	} else {
		heading = heading.normalized();
	}
	let basis = Basis::looking_at(heading, Vector3::UP, false).scaled(Vector3::splat(scale));
	Transform3D::new(basis, pos)
}

fn write_transform(t: Transform3D, out: &mut [f32]) {
	// Godot MultiMesh TRANSFORM_3D buffer: 12 floats, columns of the 3×4 matrix.
	let b = t.basis;
	let o = t.origin;
	let x = b.col_a();
	let y = b.col_b();
	let z = b.col_c();
	out[0] = x.x;
	out[1] = y.x;
	out[2] = z.x;
	out[3] = o.x;
	out[4] = x.y;
	out[5] = y.y;
	out[6] = z.y;
	out[7] = o.y;
	out[8] = x.z;
	out[9] = y.z;
	out[10] = z.z;
	out[11] = o.z;
}

pub fn pack_ship_transforms_godot(
	positions: PackedFloat32Array,
	headings: PackedFloat32Array,
	scales: PackedFloat32Array,
	hidden: PackedInt32Array,
) -> PackedFloat32Array {
	let n = scales.len();
	let mut out = PackedFloat32Array::new();
	out.resize(n * 12);
	if positions.len() != n * 3 || headings.len() != n * 3 || hidden.len() != n {
		return out;
	}
	pack_ship_transforms(
		positions.as_slice(),
		headings.as_slice(),
		scales.as_slice(),
		hidden.as_slice(),
		out.as_mut_slice(),
	);
	out
}

/// Apply transforms to MultiMesh instances by local index. Returns count written.
pub fn apply_ship_transforms_godot(
	mm: &mut Gd<MultiMesh>,
	local_indices: PackedInt32Array,
	positions: PackedFloat32Array,
	headings: PackedFloat32Array,
	scales: PackedFloat32Array,
	hidden: PackedInt32Array,
) -> i32 {
	let n = scales.len();
	if local_indices.len() != n
		|| positions.len() != n * 3
		|| headings.len() != n * 3
		|| hidden.len() != n
	{
		return 0;
	}
	let mut written = 0i32;
	for i in 0..n {
		let i3 = i * 3;
		let xform = make_transform(
			positions[i3],
			positions[i3 + 1],
			positions[i3 + 2],
			headings[i3],
			headings[i3 + 1],
			headings[i3 + 2],
			scales[i],
			hidden[i] != 0,
		);
		mm.set_instance_transform(local_indices[i], xform);
		written += 1;
	}
	written
}

pub fn bench_transforms(n: usize, iters: usize) -> f32 {
	let mut positions = vec![0.0f32; n * 3];
	let mut headings = vec![0.0f32; n * 3];
	let scales = vec![1.0f32; n];
	let hidden = vec![0i32; n];
	let mut out = vec![0.0f32; n * 12];
	for i in 0..n {
		positions[i * 3] = i as f32;
		headings[i * 3 + 2] = -1.0;
	}
	let t0 = Instant::now();
	for _ in 0..iters {
		pack_ship_transforms(&positions, &headings, &scales, &hidden, &mut out);
	}
	t0.elapsed().as_secs_f32() * 1000.0
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn hidden_writes_zero_basis() {
		let positions = [1.0, 2.0, 3.0];
		let headings = [0.0, 0.0, -1.0];
		let scales = [1.0];
		let hidden = [1];
		let mut out = [0.0; 12];
		pack_ship_transforms(&positions, &headings, &scales, &hidden, &mut out);
		assert_eq!(out[3], 1.0);
		assert_eq!(out[7], 2.0);
		assert_eq!(out[11], 3.0);
		assert!(out[0].abs() < 1e-6);
		assert!(out[5].abs() < 1e-6);
		assert!(out[10].abs() < 1e-6);
	}
}
