# Native kernels (Rust GDExtension)

EternalWar keeps simulation ownership in GDScript (LT-style script-over-native) but **does not defer** native acceleration. Proven bulk loops run in Rust via GDExtension when the library is present.

## Layout

```
native/
  build.sh                 # cargo build + install into bin/
  ew_kernels/              # Rust crate (gdext / godot 0.2, api-4-3)
    src/lib.rs             # NativeKernels class
    src/travel.rs          # TRAVEL integration SoA kernel
    src/transforms.rs      # MultiMesh Transform3D packing / apply
bin/
  ew_kernels.gdextension
  libew_kernels.so         # linux x86_64 release (committed for convenience)
simulation/native_bridge.gd  # capability detect + GDScript fallback
```

## Build

```bash
./native/build.sh
```

Requires `rustc` / `cargo`. Target: Godot **4.3** (`features = ["api-4-3"]`).

## Boundary rules

1. **GDScript owns world state** — ships remain dictionaries; Rust never holds sim entities.
2. **Packed arrays only** — `PackedFloat32Array` / `PackedInt32Array` cross the boundary.
3. **Fallback required** — `NativeBridge` must produce the same TRAVEL math without the `.so`.
4. **Determinism** — kernels are pure functions of inputs; no `rand`, no `Date.now`.

## Current kernels

### `integrate_travel`

Moves a batch of ships toward destinations (same formula as `ShipAI._travel`). Returns per-ship status: traveling / arrived / invalid. `StarSystemSim` batches all `TRAVEL` ships each tick, then runs `on_arrive` in GDScript.

### `apply_ship_transforms` / `pack_ship_transforms`

Builds `Basis.looking_at` + scale transforms and writes them to a `MultiMesh`. Used by `SystemPresenter.sync_ships` for far-field instances.

## Next candidates (when profiled)

- Bulk asteroid / starfield instance transforms
- Hierarchical seed / galaxy generation
- Mesh build helpers (SurfaceTool-heavy paths)

## Verify

```bash
cargo test --manifest-path native/ew_kernels/Cargo.toml
godot --headless --path . -s res://tests/run_tests.gd
# Look for: native_backend=rust  and native bench lines
```
