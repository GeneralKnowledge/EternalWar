# Limit Theory Geometry & Systems Alignment

**Principle (same as nebula):** stop inventing parallel generators. Port Limit Theory’s actual pipelines from `JoshParnell/ltheory`.

---

## 1. Gap audit (LT vs EternalWar) — living list

| Area | LT source of truth | EW today | Status |
| --- | --- | --- | --- |
| **Nebula IFS** | `gen/nebula.glsl` direction-space | Live sky + Rust bake | **Done** |
| **Nebula bake quality** | ~1024 TexCube + mips | **1024×512 / 96 spp / 24 iter** | Partial (mips/mood still) |
| **IRMap / starbg** | `genIRMap(256)` | Starfield `ir_suppress` + `nebula_tint` | Partial (no true IR bake) |
| **Starfield** | `Starfield.lua` cluster + Exp^2.5 | `StarfieldGen` MultiMesh tiers | Mostly aligned |
| **Fighter** | `ShipFighter.Standard` | ShapeLib all LODs + SurfaceDetail lottery | **Done** (IoU polish open) |
| **Capital** | `ShipCapital.Sausage` | ShapeLib all LODs + `addAtIntersection` | **Done** (Joint still missing) |
| **Ship finalize AO** | `computeAO` | Soft neighbourhood AO in `finalize_mesh` | Partial |
| **UV / DiffuseMap** | `UVMap.lua`, `DiffuseMap.lua` | Vertex colour | Missing (optional) |
| **Station** | `Box` + `greeble` | ShapeLib station + role accents | Partial |
| **Asteroid SDF** | `sdf/asteroid.glsl` | ShapeLibAsteroid radial displace | Partial |
| **Asteroid LodMesh** | 8-band Tex3D bake | **8-band subdiv/octave tiers** (no Tex3D) | Partial |
| **Asteroid fields** | SystemBasic exp ball + belts | **LT field + belt formulas** | Partial (counts EW-scaled) |
| **Planet surface** | `gen/planet.glsl` → TexCube | Live IFS (18/16 iters); gas = colour field | Partial (**TexCube bake still missing**) |
| **Planet materials** | `material/planet.glsl` | Spatial + fresnel atmo | Partial |
| **Thruster VFX** | `effect/thruster.glsl` | **`thruster.gdshader` plume + spray** | Partial (pulse/explosion still missing) |
| **Dust flecks** | `effect/dustfleck.glsl` | **`dustfleck.gdshader` quads** | Partial |
| **Post** | tonemap2 expmap + vignette + bloom2 | **`lt_post` expmap+vignette**; glow off | Partial (bloom blocked on Compatibility) |
| **System layout** | `SystemBasic` scale 5000 | **`SYSTEM_RADIUS=5000`** + LT place formulas | Partial (richer EW counts) |
| **Ship materials** | AO + metal/triplanar | Soft AO + StandardMaterial3D | Partial |
| **Local star / corona** | Engine lighting + bloom | Mesh + DirectionalLight | Partial |
| **Style.lua warps** | Favored shapes by style | StyleProfile paint/exhaust | Approximate |
| **ShapeLib Joint** | `ShapeLib/Joint` | Not ported | Missing |
| **Pulse / explosion** | `effect/pulse`, explosion | None | Missing |
| **Economy / AI / fleets** | Think / Universe | Foundation; frozen until visuals | Frozen |

---

## 2. ShapeLib source of truth

| Op | File |
| --- | --- |
| verts/polys, `extrudePoly`, `finalize`, `addAtIntersection` | `ShapeLib/Shape.lua` |
| `scale`, `rotate`, `mirror`, `bevel`, `greeble`, `tessellate`, `stellate`, `sphereize` | `ShapeLib/Warp.lua` |
| `Box`, `Prism` | `ShapeLib/BasicShapes.lua` |
| Fighter assembly + `SurfaceDetail` | `ShipFighter.lua` |
| Station (active) | `Station.lua` `if true` → Box + greeble |
| Asteroid | `Asteroid.lua` + `sdf/asteroid.glsl` |

EternalWar port: `presentation/generators/shapelib/`.

---

## 3. Fighter / capital pipeline

```
HullStandard: Prism|sphereize → pitch90 → extrude → scale
+ WingsStandard | WingsTie
+ WingMounts
+ SurfaceDetail (bevel default; ~5% stellate/extrude/greeble)
+ normalize radius→3
→ finalize (+ soft AO)
```

- **Patrol/Miner** → `ShapeLibShipFighter.standard(detail)`
- **Hauler/Trader** → `ShapeLibShipCapital.sausage(detail)` with ray `addAtIntersection` for cockpit/plate
- All VisualLODs; uniform scale to design length; BATCH hull-only
- Cache key: `v7shapelib`

---

## 4. SystemBasic layout (ported formulas)

| LT | EW |
| --- | --- |
| `kSystemScale = 5000` | `SYSTEM_RADIUS = 5000` |
| Fields: `dir3 * scale * Exp^(1/3)` | Yield `field_kind=field` |
| Belts: `r = 2R ± 0.2R`, thin y | Yield `field_kind=belt` |
| Planets: `dir2 * (R + scale*(0.25+0.75*sqrt(u)))` | `_make_planet` |
| Stations: `dir2 * scale` (mix) | 35% equatorial LT / 65% planet-anchored |

---

## 5. Presentation ports

| Shader / pass | Path |
| --- | --- |
| Thruster plume | `shaders/thruster.gdshader` |
| Dust flecks | `shaders/dustfleck.gdshader` |
| Post (expmap + vignette) | `shaders/lt_post.gdshader` |
| Starfield IR tint | `shaders/starfield.gdshader` uniforms |
| Planet IFS | `shaders/planet.gdshader` (live; TexCube later) |
| Nebula bake | NativeBridge `bake_nebula_panorama` 1024×512 |

---

## 6. Highest-leverage remaining

1. **Planet TexCube bake** (`gen/planet.glsl` offline cubemap) — still the largest reinvented surface risk  
2. **True asteroid Tex3D LodMesh** (8-band SDF bake)  
3. **True IRMap** for starbg (not uniform tint)  
4. **bloom2 without Compatibility hex tiles** (Forward+/custom blur)  
5. **ShapeLib Joint + Style.lua favored warps**  
6. **Pulse / explosion VFX**  
7. **UV / DiffuseMap bake**  
8. **Nebula mood / anisotropy** to close compare scores (~79 ship, ~72 star)

---

## 7. Non-goals

- New pretty ship families unrelated to ShapeLib  
- Proportion guessing without IoU vs LT crops  
- Station disabled prism path before greeble matches  
- Economy / multi-system until visual bar clears  

---

## 8. Definition of done

| Checkpoint | Metric |
| --- | --- |
| Fighter | ShapeLib + SurfaceDetail; clay IoU vs engines crop |
| Capital | Sausage + ray attach; Hauler gallery |
| Station | Greebled-box vs LT station stills |
| Asteroid | SDF look + band LODs; Tex3D later |
| Planet | IFS language now; TexCube bake next |
| Thruster | Plume shader on nearest ship |
| Post | Vignette + expmap without hex sky tiles |

Progress = compare / IoU vs LT refs — not “more modules.”
