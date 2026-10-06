# Limit Theory Prototype

A Godot 4.3 procedural space simulation inspired by the cancelled indie game **Limit Theory** by Josh Parnell.

This is **not** a clone. It studies publicly released Limit Theory / Limit Theory Redux source for architectural ideas (economy job boards, payout-driven AI, seeded generation, simulation/presentation split), then reimplements those ideas cleanly in modern Godot.

See [`docs/limit-theory-research.md`](docs/limit-theory-research.md) for research notes.

## What works in this prototype

- Deterministic seeded star system (planets, ore fields, stations, factions)
- ~400 autonomous ships as **data**, not Nodes
- Mining → delivery and station-to-station trade jobs
- Production chains: ore → metal → components (+ energy/food sinks)
- Supply/demand price response
- Observe mode (watch the universe) and fly mode (enter the simulation)
- Debug overlay with simulation / economy timing

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
| Mouse | Look (fly, click to capture) |
| WASD | Thrust (fly) |
| Space / C | Up / down (fly) |
| **F2** | Dock with nearest station & trade (fly, within range) |
| Esc | Release mouse |

## Tests

Headless simulation tests (no window):

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

## Architecture

```
Game
├── simulation/     # Data-oriented world (no Nodes)
│   ├── seeded_rng.gd
│   ├── system_generator.gd
│   ├── economy_system.gd
│   ├── ship_ai.gd
│   └── star_system_sim.gd
├── presentation/   # Rendering + HUD
├── player/         # Fly / observe controls
├── scenes/main.tscn
└── docs/limit-theory-research.md
```

Ships, stations, and markets live as dictionaries inside `StarSystemSim`. Godot Nodes render and interact; they are not the source of truth.

## Milestones

| # | Goal | Status |
|---|------|--------|
| 0 | LT research doc | Done |
| 1 | Procedural system | Done |
| 2 | Autonomous ships | Done |
| 3 | Economy | Done (prototype) |
| 4 | Factions | Partial (colors / ownership) |
| 5+ | Conflict, LOD, galaxy, fleets | Planned |

## Rust policy

Start in GDScript. Profile. Optimise algorithms. Only then consider a tiny Rust GDExtension for proven hot paths.

## License note

Limit Theory original materials are under the Unlicense (public domain). This project’s own code is separate; do not copy large sections of LT source — study ideas, then rewrite.
