# Visual Generation — Development Note

## Focus

Come close to how **Limit Theory looked** in Godot. Simulation (economy, AI, seeds) is the inhabited canvas; it does not drive the roadmap until visual milestones clear a screenshot bar.

Constraint: visual systems **read** simulation data; they never own world state. Headless tests must stay green.

Full architecture: [`procedural-visuals.md`](procedural-visuals.md).

## Current stack

| Layer | Path | Role |
|-------|------|------|
| Seeds | `simulation/seed_hash.gd` | Hierarchical child seeds |
| World gen | `simulation/system_generator.gd` | Star, planets (+terrain/atmo seeds), yields, stations, ships |
| Style | `presentation/style_profile.gd` | Faction/style visual profiles |
| Materials | `presentation/materials.gd` | Shared material vocabulary |
| LOD | `presentation/visual_lod.gd` | Tiers 0–4 |
| Design | `generators/ship_design.gd`, `station_design.gd` | Semantic descriptors |
| Generators | `generators/*` | Starfield, ships, stations, asteroids, ShapePrims |
| Presenter | `system_presenter.gd` | Env, bodies, fields, LOD ships |
| Shaders | `shaders/*` | Star, starfield, nebula, planet, atmosphere |
| Colour | `stellar_colour.gd` | Temperature → stellar RGB |

## Limit Theory look pillars

1. Atmospheric space — dark sky, structured nebulae, dust, soft star glow
2. Believable starfield — clusters + galactic plane bias + temperature colours
3. Painterly planets — class archetypes, fresnel atmosphere, rings
4. Intentional ships — design grammar, role silhouettes, style constraints
5. Architectural stations — module graphs, role patterns
6. Field identity — composition-driven asteroid families

## Milestone acceptance

| Milestone | Done when |
|-----------|-----------|
| **A** Sky | Observe orbit stills = place in space, not black void |
| **B** Bodies | Planet classes recognisable at mid orbit |
| **C** Shapes | F3 ship inspect memorable silhouette; roles distinct at ~200 m |
| **D** Fields | Two yield compositions distinguishable without labels |
| **E** Showcase | Presets 1–3 + stills read as LT-inspired Godot |
| **F** Systems | Only after E |

## Screenshot checklist (E)

- [x] Deep-space wide shot (preset 1)
- [x] Planet approach (preset 2)
- [x] Station flyby (preset 3)
- [x] Near ship (fly / F3)
- [x] Yield fields differ by composition family

## Out of scope until F

- Full ShapeLib joint/warp port
- Galaxy / multi-system LOD
- Faction politics, conflict, fleets
- Offline planet cubemap bake
