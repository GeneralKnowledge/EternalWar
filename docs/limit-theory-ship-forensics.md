# Limit Theory Ship Forensics

Direct study of **JoshParnell/ltheory** ship generators (`script/Gen/Ship*.lua`, `ShapeLib/`) against official LT screenshots in `tools/visual_compare/reference/ships/`.

Goal: extract the procedural **design language**, not invent a generic sci-fi ship look.

---

## 1. Pipeline facts (from source)

### Architecture

| Fact | Evidence |
| --- | --- |
| Ships are **CSG-style mesh assemblies**, not hand models | `Gen/ShapeLib/Shape.lua` — verts/polys, `extrudePoly`, `bevel`, `stellate`, `greeble`, `mirror`, `finalize()` |
| Two families: **fighter** and **capital** | `Gen/Ship.lua` → `ShipFighter.Standard` / `ShipCapital.Sausage` |
| Style is a **favored shape/warp vocabulary**, not a colour tint | `ShapeLib/Style.lua` — favoredShapes, favoredWarps, scaffolding |
| Final mesh gets UV + AO | `Shape:finalize` → `UVMap`, `computeAO` |

### Fighter grammar (`ShipFighter.Standard`)

1. **Hull** — Prism (or rare ellipsoid) extruded forward with taper (`hullPoint`), short aft extrusion
2. **Wings** — Classic (extruded box → tip point → optional winglet) or TIE (flat panel + connector bar + boom)
3. **Wing mounts** — Prisms at hull sides (weapon/hardpoint housings), mirrored
4. **Surface** — Usually **bevel** (default); rare stellate / extrude / greeble
5. **Normalize** — Scale to fixed radius; bilateral symmetry via `mirror(true,false,false)`

### Capital grammar (`ShipCapital.Sausage`)

1. 1–3 **hull segments** (box or prism with multiple `extrudePoly` steps)
2. Segments **overlap** or chain along Z (creates length + negative space)
3. Optional **cockpit** placed via ray intersection on top
4. Optional **plate** detail
5. Non-uniform XYZ scale

### Materials / engines (screenshot evidence)

| Observation | Screenshots |
| --- | --- |
| Hulls read as **dark matte silhouettes** against bright nebulae | `ss_01`, `ss_03`, `lt_nebula_ship` |
| Engine glow is **orange or cyan**, high bloom | `ss_01`/`ss_02` orange; `ss_05`/`lt_asteroids` cyan |
| Colour is often **environment-tinted**, not a bright paint job | pink wash on hull in nebula shots |
| Identity comes from **silhouette + negative space**, not dense greeble | `ss_02` spine capital |

---

## 2. Comparison table

| Property | LT screenshot evidence | LT source evidence | EternalWar currently | Required change |
| --- | --- | --- | --- | --- |
| Base hull | Tapered prism / stepped wedge | Prism + `extrudePoly` taper | Stacked boxes via `ShapePrims.taper` | Real prism / tapered hull volumes |
| Negative space | Gaps between pods, wing mounts, segments | Wing mounts, TIE bars, sausage segments | Solid filled boxes | Spine + pods + struts; separate mounts |
| Wings | Flat panels, swept, TIE disks | `WingsStandard` / `WingsTie` | Two thin boxes | Extruded wing plates + optional boom |
| Role silhouette | Capital spine vs compact fighter | Fighter vs capital generators | Mild dim differences | Strong role-specific grammars |
| Style → shape | Favored warps/shapes | `Style.lua` | Mostly colour + symmetry float | Style drives hull language, density, exhaust |
| Asymmetry | Functional (modules, mounts) | Rare; mostly mirrored | Random offset | Semantic asymmetry by role |
| Materials | Dark matte + emissive engines | AO + lit materials | Vertex colour + mild PBR | Matte hull presets; style exhaust |
| Engine colour | Orange **or** cyan | (render/post) | Hard-coded `Color(0.35,0.7,1)` | Style/seed-driven exhaust |
| Colour philosophy | Faction neutrals + env tint | — | Bright faction blues dominate | Desaturated faction hulls |
| LOD | Fewer warps/details | Surface detail optional | Skip modules/wings | Map tiers 1–4 to LOD |

---

## 3. What NOT to conclude

- More polygons ≠ more LT-like. LT fighters are relatively low-poly prism assemblies.
- Random greeble is rare (`chance(0.05)`). Default is **bevel**.
- “Volumetric ship detail” is not the LT approach — modular extrusion is.

---

## 4. Comparison workflow

```
tools/visual_compare/reference/ships/   # real LT stills
tools/visual_compare/eternalwar/ships/  # EW gallery captures
tools/visual_compare/out/ships/         # side-by-side + silhouette
scenes/ship_gallery.tscn                # deterministic multi-role gallery
```

Loop: silhouette → proportion → structure → materials → lighting → fine detail.

---

## 5. Scores after hierarchical grammar pass

Studio gallery vs full-scene LT refs (env-shot bbox down-weighted in `ship_compare.py`):

| Pair | Score | Largest mismatch |
| --- | --- | --- |
| Fighter rear ↔ Patrol | **56** | Colour / coverage (scene vs studio) |
| Capital spine ↔ Hauler | **53** | Saturation (nebula vs matte hull) |
| Nebula mining ↔ Miner | **58** | Colour balance |
| Asteroid ship ↔ Trader | **64** | Colour / saturation |
| Fighter engines ↔ Military | **64** | Colour / saturation |

**Qualitative gains (gallery family sheet):**

- Patrol: flat prism + wings + side mounts (fighter language)
- Hauler: long spine + spaced cargo pods + amber engines (sausage negative space)
- Miner: forward boom/drill asymmetry + ore pods
- Exhaust: amber (mining/industrial/pirate) vs cyan (military) vs white (civilian/luxury)
- Hull colours desaturated matte — blue no longer universal

**Next largest gaps:** closer match to LT prism extrusion smoothness; richer wing tip / TIE variants; env-lit ship captures (not only studio).
