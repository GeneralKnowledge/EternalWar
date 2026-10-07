//! EternalWar native kernels (GDExtension).
//!
//! Hot-path math that GDScript can call with packed arrays.
//! Simulation ownership stays in GDScript; Rust only accelerates bulk loops.

use godot::classes::MultiMesh;
use godot::prelude::*;

mod nebula;
mod travel;
mod transforms;

struct EwKernelsExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EwKernelsExtension {}

/// Entry point visible from GDScript as `NativeKernels`.
///
/// All methods take / return packed arrays so the Godot↔Rust boundary stays
/// explicit and cheap. When the extension is missing, GDScript falls back to
/// pure implementations in `simulation/native_bridge.gd`.
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
	/// Library identity for capability checks from GDScript.
	#[func]
	fn version() -> GString {
		GString::from("0.2.0-travel+transforms+nebula")
	}

	/// Always true when this class loads — GDScript uses ClassDB to detect presence.
	#[func]
	fn is_available() -> bool {
		true
	}

	/// Integrate TRAVEL for a batch of ships.
	///
	/// Layout (length = n * 3 for vec3 packs, n for scalars):
	/// - `positions`  xyz… (mutated)
	/// - `headings`   xyz… (mutated)
	/// - `velocities` xyz… (mutated)
	/// - `destinations` xyz…
	/// - `speeds`     float per ship
	/// - `arrive`     arrive radius per ship
	/// - `dt`
	///
	/// Returns a Dictionary with updated packs + `status` PackedInt32Array:
	///   0 = still traveling, 1 = arrived this step, 2 = invalid
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

	/// Build packed Transform3D floats (n * 12) from SoA ship state.
	#[func]
	fn pack_ship_transforms(
		positions: PackedFloat32Array,
		headings: PackedFloat32Array,
		scales: PackedFloat32Array,
		hidden: PackedInt32Array,
	) -> PackedFloat32Array {
		transforms::pack_ship_transforms_godot(positions, headings, scales, hidden)
	}

	/// Write transforms directly onto a MultiMesh (skips GDScript Transform3D build).
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

	/// Micro-benchmark: run `integrate_travel` `iters` times over `n` synthetic ships.
	/// Returns elapsed milliseconds (f32). Used by headless tests.
	#[func]
	fn bench_travel(n: i32, iters: i32) -> f32 {
		travel::bench_travel(n.max(0) as usize, iters.max(1) as usize)
	}

	/// Micro-benchmark: pack transforms for `n` ships, `iters` times. Returns ms.
	#[func]
	fn bench_transforms(n: i32, iters: i32) -> f32 {
		transforms::bench_transforms(n.max(0) as usize, iters.max(1) as usize)
	}

	/// Bake LT-style nebula IFS to an equirectangular panorama (RGBAF floats).
	///
	/// `params` PackedFloat32Array layout — see `nebula::bake_nebula_panorama_godot`.
	/// Returns Dictionary: ok, width, height, rgba, ms, backend.
	#[func]
	fn bake_nebula_panorama(params: PackedFloat32Array) -> Dictionary {
		nebula::bake_nebula_panorama_godot(params)
	}
}
