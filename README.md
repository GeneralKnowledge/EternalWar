# Limit Theory Prototype

A Godot 4.3 procedural space simulation inspired by the cancelled indie game **Limit Theory** by Josh Parnell.

This is **not** a clone. It studies publicly released Limit Theory / Limit Theory Redux source for architectural ideas (economy job boards, payout-driven AI, seeded generation, simulation/presentation split), then reimplements those ideas cleanly in modern Godot.

**Current focus:** procedural visuals — come close to how brilliant Limit Theory *looked*. Systems work (economy, AI) is foundation and frozen until the look clears the screenshot bar.

See [`docs/limit-theory-research.md`](docs/limit-theory-research.md), [`docs/limit-theory-redux-code-study.md`](docs/limit-theory-redux-code-study.md), and [`docs/visual-generation-devnote.md`](docs/visual-generation-devnote.md).

## What works in this prototype

- Deterministic seeded star system with **hierarchical child seeds**
- Deep-space sky: billboard starfield, seeded nebula layers, dust motes, star corona
- Planet classes with fresnel atmospheres, rings, class-distinct shaders
- ShapeLib-lite modular ships & stations (near-field per-design meshes)
- Composition-driven asteroid fields (iron / silicate / carbon / ice)
- ~400 autonomous ships as **data**, MultiMesh far-field + detailed near-field
- Mining → delivery and station-to-station trade jobs (foundation)
- Observe mode with cinematic presets + fly mode
- Debug overlay with sim stats + nearest-ship design inspect (F3 pause)

## Requirements

- Godot **4.3+**

## Run

1. Open this folder in Godot 4.3+
2. Press **F5** (main scene: `scenes/main.tscn`)

Or:

```bash
godot --path .
```

## Controls

| Input | Action |
|-------|--------|
| **F1** | Toggle observe ↔ fly |
| Arrow keys | Orbit camera (observe) |
| `+` / `-` | Zoom (observe) |
| **1 / 2 / 3** | Cinematic presets: system orbit / planet approach / station flyby |
| Mouse | Look (fly, click to capture) |
| WASD | Thrust (fly) |
| Space / C | Up / down (fly) |
| **F2** | Dock with nearest station & trade (fly, within range) |
| **F3** | Pause sim (inspect) |
| Esc | Release mouse |

## Tests

Headless simulation tests (no window):

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

## Architecture

```
Game
├── simulation/     # Data-oriented world (no Nodes) — foundation, frozen
│   ├── seeded_rng.gd / seed_hash.gd
│   ├── system_generator.gd
│   ├── economy_system.gd / ship_ai.gd
│   ├── native_bridge.gd   # Rust GDExtension ↔ GDScript fallback
│   └── star_system_sim.gd
├── native/ew_kernels/     # Rust hot-path kernels (GDExtension)
├── bin/                   # libew_kernels.so + .gdextension
├── presentation/   # Rendering + design grammar — active
│   ├── style_profile.gd / materials.gd / visual_lod.gd / stellar_colour.gd
│   └── generators/ # ShipDesign, StationDesign, meshes, starfield
├── shaders/
├── player/
├── scenes/main.tscn
└── docs/procedural-visuals.md
```

Ships, stations, and markets live as dictionaries inside `StarSystemSim`. Godot Nodes render and interact; they are not the source of truth.

See [`docs/procedural-visuals.md`](docs/procedural-visuals.md) for the full visual architecture.

## Milestones

### Foundation (frozen — do not expand until visual ladder clears)

| # | Goal | Status |
|---|------|--------|
| 0 | LT research doc | Done |
| 1 | Procedural system + hierarchical seeds | Done |
| 2 | Autonomous ships | Done |
| 3 | Economy (job board, production, prices) | Done (prototype) |

### Visual-first ladder (active)

Each exit criterion is **screenshot proof**, not new sim features. Living system stays as the canvas.

| # | Goal | Status |
|---|------|--------|
| A | Sky & atmosphere — deep space, billboard stars, nebula, dust, corona | In progress |
| B | World bodies — fresnel atmospheres, class-distinct planets, rings | In progress |
| C | Shape language — ShapeLib-lite ships/stations, near-field per-design | In progress |
| D | Field identity — composition-driven yields, life particles | In progress |
| E | Showcase pass — cinematic presets, acceptance checklist | In progress |
| F | Systems resume — factions, conflict, galaxy, fleets | Blocked on E |

## Rust / native kernels

Native code is **in use**, not deferred. Hot paths call a Rust GDExtension when present and fall back to identical GDScript SoA math when missing.

| Kernel | Path | Purpose |
|--------|------|---------|
| `integrate_travel` | ship TRAVEL batch | Bulk position/heading/velocity integration |
| `apply_ship_transforms` | MultiMesh sync | `Basis.looking_at` + scale for far-field ships |

```bash
# Requires Rust toolchain (rustc 1.78+)
./native/build.sh          # release → bin/libew_kernels.so
./native/build.sh debug    # debug build
```

Godot loads `bin/ew_kernels.gdextension`. Headless tests print `native_backend=rust|gdscript`. Simulation ownership stays in GDScript; Rust only runs packed-array kernels.

See [`docs/native-kernels.md`](docs/native-kernels.md).

## License note

Limit Theory original materials are under the Unlicense (public domain). This project’s own code is separate; do not copy large sections of LT source — study ideas, then rewrite.
