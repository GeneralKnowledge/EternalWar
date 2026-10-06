# Visual Generation — Development Note

## Focus

Come close to how **Limit Theory looked** in Godot. Simulation (economy, AI, seeds) is the inhabited canvas; it does not drive the roadmap until visual milestones A–E clear a screenshot bar.

Constraint: visual systems **read** simulation data; they never own world state. Headless tests must stay green.

## Current stack (post foundation)

| Layer | Path | Role |
|-------|------|------|
| Seeds | `simulation/seed_hash.gd`, `seeded_rng.gd` | Hierarchical child seeds |
| World gen | `simulation/system_generator.gd` | Star, planets, yields, stations, ships + visual metadata |
| Presenter | `presentation/system_presenter.gd` | Environment, bodies, fields, LOD ships |
| Generators | `presentation/generators/*` | Starfield, ShapeLib-lite, asteroids, stations |
| Primitives | `presentation/generators/shape_prims.gd` | Shared boxes, tapers, cylinders, mirrors |
| Cache | `presentation/mesh_cache.gd` | ArrayMesh by design key |
| Shaders | `shaders/{star,planet,atmosphere,nebula,starfield}.gdshader` | LT-inspired look |

## Limit Theory look pillars

1. **Atmospheric space** — true dark sky, structured nebulae, dust, soft star glow (not a flat tint wash)
2. **Believable starfield** — clustered billboard points with temperature colours and magnitude
3. **Painterly planets** — class-distinct surfaces, fresnel atmosphere limb, rings that catch light
4. **Intentional ships** — ShapeLib-style composition (silhouette language), not random boxes
5. **Architectural stations** — role-readable spines, rings, docking arms
6. **Field identity** — ore vs ice regions distinguishable without HUD

## Milestone acceptance

| Milestone | Done when |
|-----------|-----------|
| **A** Sky | Observe-mode orbit stills look like “a place in space,” not gray void with dots |
| **B** Bodies | Each planet class recognizable at mid orbit |
| **C** Shapes | F3 ship inspect shows a memorable silhouette; miners ≠ patrols ≠ haulers at ~200 m |
| **D** Fields | Two yield compositions distinguishable in screenshots without labels |
| **E** Showcase | Cinematic presets (keys 1–3) + stills read as LT-inspired Godot, not placeholder |
| **F** Systems | Only after E — factions, conflict, galaxy, fleets |

## Screenshot checklist (E)

- [ ] Deep-space wide shot (preset 1) — nebula structure + starfield readable
- [ ] Planet approach (preset 2) — atmosphere limb + surface identity
- [ ] Station flyby (preset 3) — architectural silhouette + traffic life
- [ ] Near ship (fly / F3) — class-readable ShapeLib-lite hull
- [ ] Two yield fields — composition colours/scatter differ

## Near vs far ships

- **Near** (`LOD_NEAR`): per-design `MeshInstance3D` from `ShipMeshGen.build(ship.design)`
- **Far**: class MultiMesh archetypes (cheap batches)
- Docked non-player ships hidden (zero scale)

## Out of scope until F

- Full ShapeLib joint/warp port
- Galaxy / multi-system LOD
- Faction politics, conflict, fleets
- Offline planet cubemap bake (fragment fbm is enough for now)
