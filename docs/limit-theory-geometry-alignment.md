# Limit Theory Geometry Alignment (Ships / Stations / Asteroids)

**Principle (same as nebula):** stop inventing parallel generators. Port Limit Theory’s actual pipelines from `JoshParnell/ltheory` `script/Gen/`.

---

## 1. Source of truth

| Asset | LT method (fact) | Files |
| --- | --- | --- |
| **Fighter** | ShapeLib mesh: Prism → `extrudePoly` taper → wings → mounts → `bevel` (default) → `mirror` → `finalize` | `ShipFighter.lua` (`Standard`), `ShapeLib/*` |
| **Capital** | Segmented “sausage”: overlapping hull segments + optional cockpit/plate | `ShipCapital.lua` (`Sausage`), `ShipLib/*` |
| **Station (active)** | `BasicShapes.Box()` + `greeble(rng, 2, 0.01, 0.05)` → finalize | `Station.lua` (`if true` branch) |
| **Station (alt, disabled)** | Prism extrusions + engines + mirrored wings + bevel | same file, `else` |
| **Asteroid** | Cell-noise SDF → Tex3D → mesh + occlusion, 8 LOD bands | `Asteroid.lua`, `res/shader/fragment/sdf/asteroid.glsl` |

Shared infrastructure:

- `ShapeLib/Shape.lua` — verts/polys, `extrudePoly`, `bevel`, `stellate`, `greeble`, `mirror`, `clone`, `add`, `finalize`
- `ShapeLib/BasicShapes.lua` — `Box`, `Prism`, `Ellipsoid`, …
- `ShapeLib/Warp.lua` — axial push, sphereize, etc.
- Finalize → UV map + AO (LT engine); Godot equivalent = ArrayMesh + matte materials

---

## 2. What EternalWar does today (gap)

| Asset | EternalWar | Match? |
| --- | --- | --- |
| Ships | `ShipDesign` → `GeometryKernel` loft/planform/bevel_profile — **inspired by** LT, not a ShapeLib port | Partial (proportions); topology ops diverge |
| Stations | Role module graph + rings/spines (`StationDesign`) | No — different architecture |
| Asteroids | Subdivided chunk/shard/lobed/crag families (`AsteroidMeshGen`) | No — not SDF |

Guessing risk: tuning loft stations / module offsets / icosa noise without ShapeLib ops or the SDF formula. That is the same class of mistake as inventing volume raymarch for nebulas.

---

## 3. Fighter pipeline (verbatim LT)

From `ShipFighter.Standard` / `HullStandard` / `WingsStandard` / `WingMounts` / `SurfaceDetail`:

```
HullStandard:
  Prism(2, res) → rotate Y90
  → extrudePoly(front, length, scale=(point,point,1), dir=forward)
  → extrudePoly(back, 0.3, scale=0.5, dir=aft)
  → scale(radius, radius, 1)

+ WingsStandard | WingsTie   (mirrored)
+ WingMounts                 (side prisms, mirrored)
+ SurfaceDetail              (~85%+ bevel; stellate/extrude/greeble each ~5%)
+ normalize to unit radius
→ finalize()
```

`Ship.lua` dispatches: fighter → mostly `Standard`; capital → `Sausage`.

---

## 4. Station pipeline (verbatim LT)

**Active path in repo today** (`if true`):

```
Box() → greeble(rng, tessellations=2, size 0.01–0.05) → finalize()
```

The elaborate prism/wing station is **behind `else`** (disabled). Matching LT as shipped means greebled boxes first; optional later: enable the prism path as a variant.

---

## 5. Asteroid pipeline (verbatim LT)

```glsl
// sdf/asteroid.glsl
n = fCellNoise(2*p, seed, octaves=8, smoothness=2.5)
d = length(p) - mix(0.05, 1.0, n)
```

```
for LOD i in 1..8:
  ShaderToTex3D(R32F, res) → SDF → mesh + normals + occlusion
  res /= 1.5; distance band expands
→ LodMesh
```

EternalWar should bake density with the same formula (GDScript/Rust or compute), extract isosurface, matte rock materials — not invent chunk families as the primary look.

---

## 6. Implementation order (no guessing)

1. **ShapeLib core (GDScript)**  
   Port `Shape` + `BasicShapes.Box/Prism` + `extrudePoly` + `bevel` + `mirror` + `greeble` + `finalize→ArrayMesh`.  
   Unit tests: prism face counts, mirror symmetry, bevel manifold-ish.

2. **ShipFighter.Standard**  
   Port hull/wings/mounts/surface detail with seeded RNG (no LT Settings UI).  
   Wire **Patrol / Military** through ShapeLib path; keep old loft as fallback flag.  
   Gate: clay silhouette IoU vs `lt_fighter_engines_crop` / gallery refs.

3. **ShipCapital.Sausage**  
   Port for Hauler / heavy Trader roles.

4. **Station**  
   Replace primary mesh with LT greebled box; keep role modules as optional low-weight accents if needed for gameplay readability.

5. **Asteroid SDF**  
   Port cell-noise SDF + isosurface; single high-res mesh first, LOD later.

6. **Evidence loop**  
   `ship_gallery` / station / asteroid captures → silhouette + side-by-side vs LT refs (same as nebula mood sheet discipline).

---

## 7. Non-goals

- New “pretty” ship families unrelated to ShapeLib
- Proportion guessing without IoU against LT crops
- Moving to Rust until GDScript ShapeLib is correct and measured hot
- Re-enabling Station’s disabled prism path before the active greeble path matches

---

## 8. Definition of done

| Checkpoint | Metric |
| --- | --- |
| Fighter | ShapeLib path default for Patrol; IoU ≥ current clay baseline vs engines crop |
| Capital | Sausage silhouette reads as spine + gaps (gallery) |
| Station | Greebled-box primary; side-by-side vs LT station stills |
| Asteroid | Cell-noise SDF; no obvious icosa-chunk look in asteroid field shots |

Progress = climbing compare scores / silhouette IoU against LT references — not “more modules.”
