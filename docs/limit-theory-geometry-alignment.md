# Limit Theory Geometry & Systems Alignment

**Principle (same as nebula):** stop inventing parallel generators. Port Limit Theory’s actual pipelines from `JoshParnell/ltheory`.

---

## 1. Full gap audit (LT vs EternalWar)

| Area | LT source of truth | EW today | Status |
| --- | --- | --- | --- |
| **Nebula** | `gen/nebula.glsl` IFS TexCube | Direction-space IFS sky | Aligned (live sky; bake later) |
| **Starfield** | `Starfield.lua` — cluster growth, `Exp^2.5`, blackbody, far quads | `StarfieldGen` MultiMesh tiers | Mostly aligned |
| **Fighter** | `ShipFighter.Standard` + ShapeLib | **ShapeLib port** for Patrol | **In progress** |
| **Capital** | `ShipCapital.Sausage` | **ShapeLib sausage** (Hauler/Trader) | Aligned |
| **Station** | Active: `Box` + `greeble` | **ShapeLib station** + role accents | Aligned |
| **Asteroid mesh** | `sdf/asteroid.glsl` + 8-band LodMesh | **ShapeLibAsteroid** SDF + detail bands 0..3 | Aligned (no Tex3D bake) |
| **Asteroid field** | `SystemBasic` — exp ball + planetary belts | **SystemBasic layout** in `system_generator` | Aligned |
| **Planet surface** | `gen/planet.glsl` — IFS height/color/clouds → TexCube | **IFS live shader** (`planet.gdshader`) | Aligned (live; bake later) |
| **Planet materials** | `material/planet.glsl`, atmosphere | Simple spatial shader | Partial |
| **Local star / corona** | Engine lighting + bloom | Mesh + DirectionalLight | Partial (post differs) |
| **Thruster / VFX** | `effect/thruster.glsl`, pulse, explosion | **Thruster plume shader** + soft particles | Aligned (plume); pulse later |
| **Dust flecks** | `effect/dustfleck.glsl`, dustcloud | Galactic dust MultiMesh | Partial |
| **Ship materials** | AO + metal/triplanar | StandardMaterial3D matte | Partial |
| **Post** | tonemap2, bloom2, vignette, colorgrade | Env glow + **`lt_post` vignette/tonemap2** | Aligned (approx) |
| **UV / diffuse bake** | `UVMap.lua`, `DiffuseMap.lua` | Vertex color | Optional later |
| **System layout** | `SystemBasic.lua` scale 5000, fields/stations/planets/belts | **Ported placement** (EW counts) | Aligned |

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

Wired: **Patrol** → `ShapeLibShipFighter.standard` (other roles still loft until Capital port).

---

## 4. Station / asteroid

- **Station:** greebled box primary; role modules secondary accents.
- **Asteroid:** `d = |p| - mix(0.05,1, fCellNoise(2p))` via radial search on sphere (full Tex3D LOD later).

---

## 5. Other high-value missing ports (priority)

1. ~~**Planet TexCube**~~ — live IFS in `planet.gdshader` (bake optional later).
2. ~~**ShipCapital.Sausage**~~ — ShapeLib path for Hauler/Trader.
3. ~~**SystemBasic layout**~~ — exp-ball fields, equatorial stations/planets, planetary belts.
4. ~~**Thruster VFX**~~ — `shaders/thruster.gdshader` plume (pulse/explosion still open).
5. ~~**Post stack**~~ — stronger Env bloom + `shaders/lt_post.gdshader` vignette/tonemap2 mix.
6. ~~**Asteroid LodMesh bands**~~ — detail 0..3 SDF resolution (full Tex3D bake still open).

**Still open:** pulse/explosion FX, planet TexCube bake, true 8-band Tex3D asteroid, ship AO/triplanar.

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
