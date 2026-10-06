//! MultiMesh instance packing — asteroid (euler) and starfield (uniform scale).
//! LTR analogue: InstanceBatch / AsteroidInstancedRenderer SoA → one write path.

use godot::builtin::{Basis, Color, EulerOrder, PackedFloat32Array, PackedInt32Array, Transform3D, Vector3};
use godot::classes::MultiMesh;
use godot::obj::Gd;

/// Fill MultiMesh instances 0..n-1 with uniform-scale identity bases at positions.
/// Used for starfield / dust billboards (QuadMesh facing handled by material/shader).
pub fn fill_scaled_instances(
	mm: &mut Gd<MultiMesh>,
	positions: &[f32],
	scales: &[f32],
) -> i32 {
	let n = scales.len();
	if positions.len() != n * 3 {
		return 0;
	}
	for i in 0..n {
		let i3 = i * 3;
		let pos = Vector3::new(positions[i3], positions[i3 + 1], positions[i3 + 2]);
		let s = scales[i];
		let xform = Transform3D::new(Basis::from_scale(Vector3::splat(s)), pos);
		mm.set_instance_transform(i as i32, xform);
	}
	n as i32
}

/// Fill MultiMesh with euler-rotated + scaled instances (asteroid fields).
/// `eulers` is n*3 radians (x,y,z).
pub fn fill_euler_instances(
	mm: &mut Gd<MultiMesh>,
	positions: &[f32],
	eulers: &[f32],
	scales: &[f32],
) -> i32 {
	let n = scales.len();
	if positions.len() != n * 3 || eulers.len() != n * 3 {
		return 0;
	}
	for i in 0..n {
		let i3 = i * 3;
		let pos = Vector3::new(positions[i3], positions[i3 + 1], positions[i3 + 2]);
		let euler = Vector3::new(eulers[i3], eulers[i3 + 1], eulers[i3 + 2]);
		let s = scales[i];
		let basis = Basis::from_euler(EulerOrder::YXZ, euler).scaled(Vector3::splat(s));
		mm.set_instance_transform(i as i32, Transform3D::new(basis, pos));
	}
	n as i32
}

/// Write instance colors from packed RGBA floats (n*4). Indices optional:
/// if `indices` empty, writes 0..n-1; else length must equal n.
pub fn fill_instance_colors(
	mm: &mut Gd<MultiMesh>,
	colors_rgba: &[f32],
	indices: &[i32],
) -> i32 {
	let n = colors_rgba.len() / 4;
	if colors_rgba.len() != n * 4 {
		return 0;
	}
	if !indices.is_empty() && indices.len() != n {
		return 0;
	}
	for i in 0..n {
		let c4 = i * 4;
		let col = Color::from_rgba(
			colors_rgba[c4],
			colors_rgba[c4 + 1],
			colors_rgba[c4 + 2],
			colors_rgba[c4 + 3],
		);
		let idx = if indices.is_empty() {
			i as i32
		} else {
			indices[i]
		};
		mm.set_instance_color(idx, col);
	}
	n as i32
}

pub fn fill_scaled_instances_godot(
	mm: &mut Gd<MultiMesh>,
	positions: PackedFloat32Array,
	scales: PackedFloat32Array,
) -> i32 {
	fill_scaled_instances(mm, positions.as_slice(), scales.as_slice())
}

pub fn fill_euler_instances_godot(
	mm: &mut Gd<MultiMesh>,
	positions: PackedFloat32Array,
	eulers: PackedFloat32Array,
	scales: PackedFloat32Array,
) -> i32 {
	fill_euler_instances(mm, positions.as_slice(), eulers.as_slice(), scales.as_slice())
}

pub fn fill_instance_colors_godot(
	mm: &mut Gd<MultiMesh>,
	colors_rgba: PackedFloat32Array,
	indices: PackedInt32Array,
) -> i32 {
	fill_instance_colors(mm, colors_rgba.as_slice(), indices.as_slice())
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn color_layout() {
		let rgba = [1.0f32, 0.5, 0.25, 1.0];
		assert_eq!(rgba.len() / 4, 1);
	}
}
