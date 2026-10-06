# Procedural Visual Generation Architecture

EternalWar’s visual layer makes the simulation visible. Simulation stays data-oriented and headless-safe; presentation turns semantic descriptions into meshes and shaders.

This is an **independent Godot implementation** inspired by Limit Theory’s architectural ideas (seeded generation, ShapeLib-style composition, sim/render split). It is not a port.

## Pipeline

```
Simulation dictionaries
        ↓
Semantic design descriptors  (ShipDesign / StationDesign / planet extras)
        ↓
Procedural visual generators (ShipMeshGen / StationMeshGen / AsteroidMeshGen / StarfieldGen)
        ↓
MeshCache + VisualMaterials + shaders
        ↓
SystemPresenter (LOD, MultiMesh, Environment)
```

Generators must not import economy/AI internals. They consume explicit design fields only.

## Seed hierarchy

```
Universe/System seed
 ├── star
 ├── nebula / nebula_layers / starfield / galactic_dust
 ├── planet:i
 │    ├── terrain
 │    ├── atmosphere
 │    ├── rings
 │    └── name
 ├── yield:i
 │    └── field
 ├── station:i
 │    ├── layout
 │    ├── detail
 │    ├── module:k
 │    └── name
 └── ship:i
      └── design
           ├── hull
           ├── engine
           ├── module
           └── detail
```

`SeedHash.derive(parent, tag)` ensures generation order cannot scramble unrelated objects. Same system seed → same visual universe.

## Ship design grammar

`ShipDesign.build(design)` produces:

- role dims (fighter/patrol compact, hauler long, miner industrial)
- style profile (`StyleProfile`: symmetry, taper, ornament, materials)
- engine attachments on the aft structural region
- role modules (drill/ore_bay, cargo, cockpit/sensors)
- optional wings/hardpoints with symmetry constraints
- hierarchical child seeds for hull/engine/module/detail

`ShipMeshGen` turns that into ShapeLib-lite geometry at a requested `VisualLOD` tier.

## Station design graph

Stations carry `modules[]` from simulation. `StationDesign` places them via an architectural layout map, connects non-core modules to the core with edges, and adds role extras (rings/spines). Geometry follows the graph — not a single role `match` of boxes.

## Sky layers

1. **Deep background** — clustered temperature-coloured billboard stars (`StarfieldGen` + `StellarColour`)
2. **Galactic structure** — plane-biased star density + faint galactic dust MultiMesh
3. **Nebulae** — distant soft noise planes (`nebula.gdshader`), subtle, not a full-sky wash

Local star uses `StellarColour.from_temperature` + corona shells.

## Planets & asteroids

- Planet class → shader flags + palette; `terrain_seed` / `atmosphere_seed` drive noise offset and rim shells
- Asteroid **families** (chunk / shard / lobed / crag) biased by composition — variety in mesh, not only scale

## LOD

| Tier | Distance | Representation |
|------|----------|----------------|
| 0 FULL | < 280 | Per-design mesh, full detail |
| 1 SIMPLE | < 550 | Per-design, reduced detail |
| 2 LOW | < 1100 | Per-design, minimal modules |
| 3 BATCH | < 4500 | Class MultiMesh archetype |
| 4 SIM | farther | Simulation only (no draw) |

## Materials

`VisualMaterials` presets: metal_dark/light, industrial, painted, ceramic, glass, energy, rock, ice, gas, atmosphere. Style profiles select presets; tint comes from faction colour.

## Debug seeds

F3 inspect shows system / object / design / hull / engine / module / detail seeds. Planet[0] shows terrain + atmosphere seeds. Station[0] shows layout seed + module list.

## Performance

Headless `_test_perf_benchmarks` times system gen + mesh builds + 60 ticks for 400 and 1000 ships. Larger populations (5k / 10k / 50k) should be measured locally. Prefer shaders, MultiMesh, MeshCache, LOD before any Rust/GDExtension. Candidates for future native kernels: bulk mesh build, spatial queries, galaxy generation — keep the boundary at explicit data structures.

## Limit Theory mapping

See [`limit-theory-research.md`](limit-theory-research.md). Visual milestones A–E in the README. Systems features (factions depth, conflict, galaxy) remain frozen until the visual bar clears.
