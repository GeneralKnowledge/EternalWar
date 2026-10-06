# Visual Generation — Development Note

## Current generation system (pre-phase)

- `SystemGenerator` uses a single `SeededRNG` stream for the whole system.
- Planets, yields, stations, and ships are plain dictionaries (`SimEntities`).
- Visual identity was minimal: random colours, simple radii, faction colours on stations/ships.
- Order-dependent RNG: advancing the stream for object N changed later objects (mitigated for reproducibility only when regenerating the entire system from the same seed).

## Current rendering system

- `SystemPresenter` builds Node3D spheres/boxes and one MultiMesh for all ships.
- Flat colour background + ~400 MultiMesh star points.
- No mesh cache, no visual LOD, no design-driven geometry.

## Reusable components to keep

- `StarSystemSim` / `EconomySystem` / `ShipAI` — simulation source of truth
- `SeededRNG` (with `_rng.*` GlobalScope footgun fix)
- MultiMesh ship sync path
- Observe / fly player modes
- Headless tests in `tests/run_tests.gd`

## Shortcomings

- Placeholders do not communicate industry/faction/role
- No hierarchical seeds → cannot lazily regenerate one object
- Starfield too sparse; planets identical spheres; stations are boxes; ships are prisms
- Simulation↔visual coupling weak (ore fields not looking like ore fields)

## Extension points

1. `simulation/seed_hash.gd` — parent+tag → child seed
2. Enrich entity dictionaries with `seed`, `design`, `planet_class`, `modules`, `composition`
3. `presentation/generators/*` — mesh builders driven by those fields
4. `presentation/mesh_cache.gd` — cache ArrayMesh by design seed
5. `SystemPresenter` — starfield / star / planet shaders / asteroid MultiMesh / modular stations / LOD ships
6. Debug overlay — inspect selected generated object

## Constraint

All existing simulation behaviour and tests must keep working. Visual systems read simulation data; they do not own world state.
