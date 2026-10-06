# Limit Theory Redux — code study

Study of [Limit-Theory-Redux/ltheory](https://github.com/Limit-Theory-Redux/ltheory) (default branch `main`, sparse checkout of `engine/` + `script/`) for EternalWar / Godot mapping. **Not a port.** Ideas only.

Companion to [`limit-theory-research.md`](limit-theory-research.md) and [`native-kernels.md`](native-kernels.md).

---

## 1. What the codebase actually is

| Layer | Tech | Role |
|-------|------|------|
| `engine/bin/ltr` | Rust binary | Loads settings, `dlopen`s `phx`, calls `Engine_Entry` |
| `engine/lib/phx` | Rust **cdylib** | Full engine: window, GL render thread, Rapier physics, audio, UI, math, event bus |
| `engine/lib/luajit-ffi-gen` | proc-macro | Auto-generates C ABI + LuaJIT FFI wrappers from `#[luajit_ffi]` on Rust `impl` / enums |
| `script/` | Lua | Gameplay: ECS modules, legacy Entity/Jobs, gen (ShipLib, nebula, starfield), UI |

Primary languages reported: ~68% Lua, ~28% Rust. Gameplay is script-heavy; native is a **real engine**, not a few kernels.

Workspace policy: `unsafe_code = "deny"` at workspace level; `ltr` links `phx` as a **dylib** so LTO’d engine code does not get pulled statically into the launcher (see comments in `engine/bin/ltr/src/main.rs`).

---

## 2. Script ↔ native boundary

### Generation

`luajit-ffi-gen` turns Rust methods into:

1. `#[no_mangle] extern "C"` wrappers
2. Lua loader modules under `engine/lib/phx/script/ffi_gen/`

Example pattern (from the crate README): annotate `impl MyStruct { ... }` → Lua sees `My_Struct.SetU32(...)`.

### Crossing style

LTR prefers **typed engine objects** (RigidBody, Mesh, Renderer, InstanceBatch) over raw float buffers for most APIs. Script holds handles; native owns memory and heavy loops.

**Exception — instancing:** `InstanceData` is an explicit `#[repr(C)]` struct (model matrix 16×f32 + color + scale). Lua packs arrays of these via `ffi.new('InstanceData[N]')` and passes them into one draw. That is the closest analogue to our `PackedFloat32Array` SoA kernels.

### EternalWar mapping

| LTR | EternalWar |
|-----|------------|
| LuaJIT FFI → `phx` | GDScript → GDExtension `NativeKernels` |
| Typed RigidBody / Mesh | Godot Nodes + MultiMesh (engine already native) |
| `InstanceData` batches | `apply_ship_transforms` / future instance packs |
| Full engine in Rust | Godot is the engine; Rust only for **proven SoA loops** |

We should **not** rebuild Rapier/render in Rust. We **should** keep growing packed-array kernels the way LTR packs instance data.

---

## 3. Frame loop

`FrameStage` in Rust (`engine/lib/phx/src/engine/event_bus/frame_stage.rs`):

```
PreInput → Input → PostInput → PreSim → Sim → PostSim → PreRender → Render → PostRender
```

Lua systems subscribe via `EventBus` (e.g. `TransformSystem` on PreSim/PostSim, `MarketplaceSystem` on PreRender).

**Transform sync pattern (important):**

1. **PreSim:** dirty Transform components → push into RigidBody (`setPos` / `setRot`)
2. **Sim:** native physics step (Rapier)
3. **PostSim:** RigidBody → Transform components

Script authors forces; native integrates.

---

## 4. Ships, flight, travel

### Modern ECS path (`script/Modules/Constructs`)

- `ShipFlightSystem` — reads input, calls `rb:applyForce` / `rb:applyTorque` (native RigidBody). Boost disabled while travel drive active.
- `TravelDriveSystem` — state machine Idle → Charging → Active → Decelerating; applies multiplied forward thrust; zone speed caps via `GravityWellSystem`.

### Legacy path (`script/Legacy/GameObjects`)

- `Ship` entity mixin stack (RigidBody, VisibleMesh, Actions, Jobs, …)
- Jobs (`Mine`, `Transport`, `Patrolling`) with payout/pressure heuristics — already mirrored conceptually in EternalWar’s `EconomySystem` / `ShipAI`

**Takeaway for FPS:** LTR does **not** put ship AI travel integration in Rust. It puts **physics integration** in Rust and leaves Think/Job/TravelDrive policy in Lua. Our kinematic `integrate_travel` kernel is still valid for Godot (no Rapier fleet), but LTR’s real win for many bodies is **instanced draw + physics**, not rewriting job graphs in native.

---

## 5. Instancing & render (the frame-rate lesson)

### AsteroidInstancedRenderer (legacy overlay)

File: `script/Legacy/Systems/Overlay/AsteroidInstancedRenderer.lua`

- Groups asteroids by **(mesh variant, LOD)**
- Packs `InstanceData` (camera-relative world matrix + scale)
- One `drawInstancedWithData` per group
- Comment claim: ~600 draws → ~16–128 instanced draws

### Rust side

- `InstanceData` — 84-byte `repr(C)` layout
- `InstanceBatch` — accumulate transforms/colors, single `glDrawElementsInstanced`
- Dedicated **render thread** + command queue (`render/thread/*`); optional `immediate` feature for single-threaded debug
- `RenderCoreSystem` — frustum cull scratch buffers, shader-key batching, camera-relative origin (precision)

### EternalWar mapping

| LTR | EternalWar today | Next native opportunity |
|-----|------------------|-------------------------|
| InstanceBatch by mesh+LOD | MultiMesh by ship class + VisualLOD | Pack asteroid / starfield instance buffers in Rust |
| Camera-relative matrices | Godot world space | Optional eye-relative pack for large systems |
| Render thread | Godot renderer | Already covered |
| Frustum cull in Renderer | Godot / distance LOD | Bulk distance classify kernel |

Our `apply_ship_transforms` is the right *shape* of work: script decides visibility/LOD; native builds transforms and writes MultiMesh.

---

## 6. Economy

- **Legacy:** Job objects with `getPayout`, `getPressure`, state machines (Transport dock/buy/sell…).
- **Modules:** `MarketplaceSystem` — price discovery, volatility, pull toward equilibrium, pending trades; runs on PreRender with per-marketplace timers.

Keep economy in GDScript. Native only if a bulk price/job-score pass shows up in profiles at 5k+ agents.

---

## 7. Gen / visuals (script)

Still largely Lua under `script/Legacy/Systems/Gen/` (ShipLib, Starfield, Nebula) and CelestialObjects modules. Procedural mesh helpers live near ShapeLib; rendering of results goes through Mesh + materials + instancing.

EternalWar’s GDScript generators + shaders are the correct Godot equivalent; native mesh build is a later kernel candidate if SurfaceTool times dominate.

---

## 8. Lessons for EternalWar (actionable)

1. **Keep script ownership of AI/jobs** — matches LTR. Our batch travel kernel is an optimization of kinematic movement, not a replacement for Think.
2. **Double down on instance packing** — LTR’s FPS story for crowds is instancing, not Lua→Rust job ports. Extend `ew_kernels` toward asteroid/starfield/ship color+transform packs in one call.
3. **Typed boundary where Godot allows** — passing `MultiMesh` into Rust (as we do) matches LTR’s “hand the engine object to native” style better than only returning float buffers.
4. **Explicit frame stages** — optional later: document PreSim/Sim/PostSim equivalents (`StarSystemSim.tick` vs `sync_ships`) so presenters never write transforms mid-sim.
5. **Do not port Rapier/GL** — Godot already is LibPHX for us.
6. **Profiler culture** — LTR wraps systems in `QuickProfiler` and has an optional stats HTTP server. Keep `perf.*` counters; add native kernel ms next to `travel_batch_ms`.

---

## 9. Suggested next kernels (ordered by LTR evidence)

| Priority | Kernel | Why (from LTR) |
|----------|--------|----------------|
| 1 | Bulk MultiMesh transform+color write (ships) | InstanceBatch analogue — **started** |
| 2 | Asteroid field instance pack by mesh key | AsteroidInstancedRenderer |
| 3 | Distance/LOD classify SoA | LOD selection before draw |
| 4 | Kinematic travel batch | Fleet without full physics — **started** |
| 5 | Mesh build helpers | Only if mesh_ms dominates benchmarks |

---

## 10. Files read (primary)

**Rust:** `engine/bin/ltr/src/main.rs`, `engine/lib/phx/src/lib.rs`, `physics/rigid_body.rs`, `engine/event_bus/frame_stage.rs`, `engine/main_loop.rs`, `render/thread/instance_data.rs`, `instance_batch.rs`, `luajit-ffi-gen/README.md`, workspace `Cargo.toml`

**Lua:** `Modules/Constructs/Systems/{ShipFlight,TravelDrive}System.lua`, `Modules/Physics/Systems/TransformSystem.lua`, `Modules/Rendering/Systems/{RenderCore,MeshRendering}System.lua`, `Modules/Economy/Systems/MarketplaceSystem.lua`, `Legacy/Systems/Overlay/AsteroidInstancedRenderer.lua`, `Legacy/GameObjects/{Job,Entities/Ship/Ship}.lua`, Jobs Transport/Mine/Patrolling
