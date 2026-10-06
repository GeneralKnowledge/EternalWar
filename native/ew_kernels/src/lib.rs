//! EternalWar native kernels (GDExtension).
//!
//! Hot-path math that GDScript can call with packed arrays.
//! Simulation ownership stays in GDScript; Rust only accelerates bulk loops.

use godot::classes::MultiMesh;
use godot::prelude::*;

mod instances;
mod lod;
mod travel;
mod transforms;

struct EwKernelsExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EwKernelsExtension {}

/// Entry point visible from GDScript as `NativeKernels`.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct NativeKernels {
	base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for NativeKernels {
	fn init(base: Base<RefCounted>) -> Self {
		Self { base }
	}
}

#[godot_api]
impl NativeKernels {
	#[func]
	fn version() -> GString {
		GString::from("0.2.0-travel+transforms+lod+instances")
	}

	#[func]
	fn is_available() -> bool {
		true
	}

	#[func]
	fn integrate_travel(
		positions: PackedFloat32Array,
		headings: PackedFloat32Array,
		velocities: PackedFloat32Array,
		destinations: PackedFloat32Array,
		speeds: PackedFloat32Array,
		arrive: PackedFloat32Array,
		dt: f32,
	) -> Dictionary {
		travel::integrate_travel_godot(
			positions,
			headings,
			velocities,
			destinations,
			speeds,
			arrive,
			dt,
		)
	}

	#[func]
	fn pack_ship_transforms(
		positions: PackedFloat32Array,
		headings: PackedFloat32Array,
		scales: PackedFloat32Array,
		hidden: PackedInt32Array,
	) -> PackedFloat32Array {
		transforms::pack_ship_transforms_godot(positions, headings, scales, hidden)
	}

	#[func]
	fn apply_ship_transforms(
		mut mm: Gd<MultiMesh>,
		local_indices: PackedInt32Array,
		positions: PackedFloat32Array,
		headings: PackedFloat32Array,
		scales: PackedFloat32Array,
		hidden: PackedInt32Array,
	) -> i32 {
		transforms::apply_ship_transforms_godot(
			&mut mm,
			local_indices,
			positions,
			headings,
			scales,
			hidden,
		)
	}

	/// Classify world positions into VisualLOD tiers relative to camera.
	/// `thresholds` = [full, simple, low, batch] distances (defaults if short).
	/// Returns { ok, lods: PackedInt32Array, distances: PackedFloat32Array }.
	#[func]
	fn classify_lod(
		positions: PackedFloat32Array,
		camera: Vector3,
		thresholds: PackedFloat32Array,
	) -> Dictionary {
		lod::classify_lod_godot(positions, camera, thresholds)
	}

	/// Starfield / dust: identity basis × uniform scale at each position (instances 0..n-1).
	#[func]
	fn fill_scaled_instances(
		mut mm: Gd<MultiMesh>,
		positions: PackedFloat32Array,
		scales: PackedFloat32Array,
	) -> i32 {
		instances::fill_scaled_instances_godot(&mut mm, positions, scales)
	}

	/// Asteroid fields: Basis.from_euler(xyz) × scale at each position (instances 0..n-1).
	#[func]
	fn fill_euler_instances(
		mut mm: Gd<MultiMesh>,
		positions: PackedFloat32Array,
		eulers: PackedFloat32Array,
		scales: PackedFloat32Array,
	) -> i32 {
		instances::fill_euler_instances_godot(&mut mm, positions, eulers, scales)
	}

	/// Write MultiMesh instance colors from packed RGBA (n*4). Empty indices → 0..n-1.
	#[func]
	fn fill_instance_colors(
		mut mm: Gd<MultiMesh>,
		colors_rgba: PackedFloat32Array,
		indices: PackedInt32Array,
	) -> i32 {
		instances::fill_instance_colors_godot(&mut mm, colors_rgba, indices)
	}

	#[func]
	fn bench_travel(n: i32, iters: i32) -> f32 {
		travel::bench_travel(n.max(0) as usize, iters.max(1) as usize)
	}

	#[func]
	fn bench_transforms(n: i32, iters: i32) -> f32 {
		transforms::bench_transforms(n.max(0) as usize, iters.max(1) as usize)
	}

	#[func]
	fn bench_classify_lod(n: i32, iters: i32) -> f32 {
		lod::bench_classify(n.max(0) as usize, iters.max(1) as usize)
	}
}
