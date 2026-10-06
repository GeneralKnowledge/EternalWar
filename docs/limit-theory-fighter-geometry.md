# Limit Theory Fighter Geometry

Evidence-based notes for reconstructing a fighter-like geometric **kernel** in EternalWar.

Sources: `JoshParnell/ltheory` `script/Gen/ShipFighter.lua`, `ShapeLib/{Shape,Warp,BasicShapes}.lua`; screenshots in `tools/visual_compare/reference/ships/`.

---

## Established from source (fact)

| Operation | Where | Behaviour |
| --- | --- | --- |
| Prism base | `BasicShapes.Prism(stacks, slices)` | Stacked N-gon rings → caps + side quads |
| Forward extrude | `Shape:extrudePoly` | Face verts lerp toward centroid by `scale`, then offset by `dir * length` |
| Aft stub | same | Short rear extrude with scale ~0.5 |
| Surface default | `ShipFighter.SurfaceDetail` / `Standard` final | **`bevel(t)`** most common; stellate/extrude/greeble rare (~5%) |
| Bevel | `Shape:bevel(t)` | Topology-aware: corner faces + edge quads + reconnect faces (`t` 0–1) |
| Wings classic | `WingsStandard` | Thin box → extrude tip (`point` taper) → tip point → optional winglet → mirror |
| Wings TIE | `WingsTie` | Flat panel + boom connector + mirror |
| Wing mounts | `WingMounts` | Side prisms, mirrored — create **gaps** beside hull |
| Symmetry | `mirror(true,false,false)` | Bilateral X mirror after decorating one side |
| Normalize | `scale(rcpRadius…)` | Unitize after assembly |

Fighter pipeline (`ShipFighter.Standard`):

```
HullStandard (prism + extrude taper)
    + WingsStandard | WingsTie
    + WingMounts
    + bevel
    + normalize
```

---

## Established from screenshots (fact)

| Observation | Evidence |
| --- | --- |
| Edges catch light (true bevels, not painted lines) | `ss_03`, `ss_05`, `lt_ship_fighter_*` |
| Side masses separated from fuselage (negative space) | `ss_03`, `ss_01` |
| Aft engines are structural terminations, often rect/beveled ports | `ss_05`, `ss_01` |
| Hull cross-section changes along length | rear blocky → mid narrower → nose taper |
| Dark matte primary, lighter panel accents | multiple stills |

---

## Inferences (marked)

| Inference | Rationale |
| --- | --- |
| Longitudinal stations ≈ discrete extrude steps | Source uses one/two extrudes; screenshots suggest more section variety — EW uses multi-station loft as compatible generalisation |
| Corner rounding in profile ≈ cheap bevel for realtime | Full LT topology bevel is expensive; profile-corner chamfer + loft yields edge highlights with controllable cost |
| Hardpoints sit on structural shelves | Screenshots show mounts as raised housings, not floating cubes |

---

## EternalWar kernel mapping

| LT concept | EternalWar `GeometryKernel` |
| --- | --- |
| Prism / extrude taper | `loft_hull(stations)` with width/height profiles |
| Bevel | `bevel_profile` corner chamfer → lofted strips |
| WingsStandard | `wing_planform(root, tip, chords, sweep, dihedral, thickness)` |
| WingMounts | `hardpoint_shelf` + gap from hull |
| Engine prism | `engine_block` structural housing + recessed exhaust |
| Mirror | explicit L/R emission (semantic symmetry) |

Pipeline for canonical fighter:

```
cross-section profile
    → bevel corners
    → loft stations (nose→body→shoulder→aft)
    → wing planforms
    → engine blocks + hardpoint shelves
    → cockpit blister
    → materials by region
```

---

## Canonical test

`LT_FIGHTER_REFERENCE` — seed **42**, role **PATROL**, style **military**, LOD **0**.

Diagnostic scene: `scenes/lt_fighter_gallery.tscn` (silhouette / clay / material / lit / compare / orthographic).

### Implementation (EternalWar)

| Kernel op | File | Notes |
| --- | --- | --- |
| `bevel_profile` / `fighter_profile` | `presentation/generators/geometry_kernel.gd` | Corner chamfer on XY profile before loft |
| `loft_hull(stations)` | same | Nose → body → shoulder → aft stations |
| `wing_planform` | same | Trapezoid root/tip chords, sweep, dihedral, thickness |
| `engine_block` | same | Housing loft + recessed exhaust well |
| `hardpoint_shelf` | same | Structural shelf + mount stub by role |
| `cockpit_blister` | same | Raised tapered canopy following deck |

PATROL / wedge designs emit `hull.language = "loft"` with ≥4 stations from `ShipDesign._fighter_stations`. Semantic architecture unchanged: ShipDesign → StyleProfile → ShipMeshGen → GeometryKernel.

### LOD

| LOD | Bevel | Secondary | Engines |
| --- | --- | --- | --- |
| 0 | full segs | wings, mounts, plates | full housing |
| 1 | 1 seg | wings, mounts | full housing |
| 2 | reduced | skip plates | full housing |
| 3 | none | box approx wings | box |

### Negative space (canonical fighter)

- Wing roots outboard of fuselage (`root_x ≈ 0.62 × width`) with side mount prisms
- Twin engines spaced with rear gap
- Raised cockpit leaves deck shoulder visible
- Recessed exhaust wells

### Material regions (vertex colour cues)

primary hull · secondary mount · cockpit / glass · engine housing · exhaust · weapon mount · accent plates
