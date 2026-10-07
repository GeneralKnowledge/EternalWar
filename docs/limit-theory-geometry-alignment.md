# Limit Theory Geometry & Systems Alignment

**Principle (same as nebula):** stop inventing parallel generators. Port Limit Theory’s actual pipelines from `JoshParnell/ltheory`.

---

## 1. Full gap audit (LT vs EternalWar)

| Area | LT source of truth | EW today | Status |
| --- | --- | --- | --- |
| **Nebula** | `gen/nebula.glsl` IFS TexCube | Direction-space IFS sky | Aligned (live sky; bake later) |
| **Starfield** | `Starfield.lua` — cluster growth, `Exp^2.5`, blackbody, far quads | `StarfieldGen` MultiMesh tiers | Mostly aligned |
| **Fighter** | `ShipFighter.Standard` + ShapeLib | **ShapeLib** Patrol + Miner, all LODs | Aligned (detail tiers) |
| **Capital** | `ShipCapital.Sausage` | **ShapeLib** Hauler + Trader, all LODs | Aligned (detail tiers) |
| **Station** | Active: `Box` + `greeble` | **ShapeLib station** + role accents | **In progress** |
| **Asteroid mesh** | `sdf/asteroid.glsl` cell-noise SDF | **ShapeLibAsteroid** SDF displace | **In progress** |
| **Asteroid field** | `SystemBasic` — exp ball + planetary belts | `system_generator` yields | Layout still EW-specific |
| **Planet surface** | `gen/planet.glsl` — IFS height/color/clouds → TexCube | `planet.gdshader` FBM bands | **Missing** — reinvented |
| **Planet materials** | `material/planet.glsl`, atmosphere | Simple spatial shader | Partial |
| **Local star / corona** | Engine lighting + bloom | Mesh + DirectionalLight | Partial (post differs) |
| **Thruster / VFX** | `effect/thruster.glsl`, pulse, explosion | Minimal / none | **Missing** |
| **Dust flecks** | `effect/dustfleck.glsl`, dustcloud | Galactic dust MultiMesh | Partial |
| **Ship materials** | AO + metal/triplanar | StandardMaterial3D matte | Partial |
| **Post** | tonemap2, bloom2, vignette, colorgrade | Godot Environment filmic + glow | Partial |
| **UV / diffuse bake** | `UVMap.lua`, `DiffuseMap.lua` | Vertex color | Optional later |
| **System layout** | `SystemBasic.lua` scale 5000, fields/stations/planets/belts | `system_generator.gd` | Different numbers; port layout next |

---

## 2. ShapeLib source of truth

| Op | File |
| --- | --- |
| verts/polys, `extrudePoly`, `finalize` | `ShapeLib/Shape.lua` |
| `scale`, `rotate`, `mirror`, `bevel`, `greeble`, `tessellate` | `ShapeLib/Warp.lua` |
| `Box`, `Prism` | `ShapeLib/BasicShapes.lua` |
| Fighter assembly | `ShipFighter.lua` |
| Station (active) | `Station.lua` `if true` → Box + greeble |
| Asteroid | `Asteroid.lua` + `sdf/asteroid.glsl` |

EternalWar port lives under `presentation/generators/shapelib/`.

---

## 3. Fighter pipeline (verbatim LT)

```
HullStandard: Prism → pitch90 → extrudePoly forward/aft → scale
+ WingsStandard | WingsTie (mirror)
+ WingMounts (mirror)
+ bevel
+ normalize radius→3
→ finalize
```

Wired: **Patrol/Miner** → `ShapeLibShipFighter.standard(detail)`; **Hauler/Trader** → `ShapeLibShipCapital.sausage(detail)`.
All VisualLODs use ShapeLib (no loft dual path). Role framing is **uniform scale to design length** (not AABB squash).
`detail`: FULL=2, SIMPLE=1, LOW/BATCH=0. Engines appended ≤LOW; BATCH is hull-only.

---

## 4. Station / asteroid

- **Station:** greebled box primary; role modules secondary accents.
- **Asteroid:** `d = |p| - mix(0.05,1, fCellNoise(2p))` via radial search on sphere (full Tex3D LOD later).

---

## 5. Other high-value missing ports (priority)

1. **Planet TexCube** — port `gen/planet.glsl` height/color/clouds (same “don’t invent FBM” rule as nebula).
2. **ShipCapital.Sausage** — Hauler/Trader silhouette.
3. **SystemBasic layout** — field/station/planet/belt placement constants.
4. **Thruster / pulse VFX** — `effect/thruster.glsl` language.
5. **Post stack** — closer bloom/tonemap/vignette to LT filters.
6. **True asteroid LodMesh** — 8-band Tex3D bake like `Asteroid.lua`.

---

## 6. Non-goals

- New pretty ship families unrelated to ShapeLib
- Proportion guessing without IoU vs LT crops
- Rust until GDScript ShapeLib is correct
- Station disabled prism path before greeble matches

---

## 7. Definition of done

| Checkpoint | Metric |
| --- | --- |
| Fighter | ShapeLib default for Patrol; clay IoU vs engines crop |
| Capital | Sausage port for Hauler |
| Station | Greebled-box primary vs LT station stills |
| Asteroid | SDF look; no chunky icosa family |
| Planet | IFS cubemap language vs LT planet stills |

Progress = compare / IoU vs LT refs — not “more modules.”
