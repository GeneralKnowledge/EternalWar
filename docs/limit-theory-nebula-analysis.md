# Limit Theory Nebula Analysis — Volumetric Depth

Why LT nebulae read as **gas occupying space**, and why EternalWar’s still read as **coloured fog**.

References: `/opt/cursor/artifacts/lt-refs/` (`wp_01`, `ss_01`, `ss_03`, `ss_05`, `ss_08`); [ltheory.com/media](http://ltheory.com/media.html); source notes in `JoshParnell/ltheory` (`Nebula.lua`, `gen/nebula.glsl` IFS env map).

This is **not** a clone brief. Extract rendering principles only.

---

## 1. What LT nebulae do (viewer order)

| Order | What you see | Why it feels volumetric |
| --- | --- | --- |
| 1st | Large luminous mass with irregular boundary | Occupies a region of sky, not the whole frame |
| 2nd | Dark cavities / dust lanes cutting through glow | Internal negative space proves thickness |
| 3rd | Filaments / wisps at different brightness | Multi-scale structure, not one noise field |
| 4th | Stars dimmed or missing behind dense gas | Occlusion → same space as the stars |
| 5th | Objects silhouetted against bright cores | Gas is a backdrop *volume*, not a wallpaper |

From `wp_01`: dark gas sits **in front of** the planet limb while brighter structure continues behind — classic depth stacking.  
From `ss_03`: magenta mass with charcoal voids; asteroid silhouettes; stars denser in cavities than in cores.

LT source hint: env-map IFS density + absorption along the view ray, **separate** from starfield mesh. Composition (WHERE) ≠ star points (HOW).

---

## 2. Comparison table

| Property | Limit Theory reference | EternalWar (pre-volume) | Required change |
| --- | --- | --- | --- |
| Depth | Gas occupies a range of distances; layers parallax | Single billboard shell per mass; `depth` only moves the plane | Bounded volumes with `depth_near`…`depth_far`; raymarch world density |
| Density variation | Dense cores + thin wisps in one mass | Soft UV lobe; fairly even mid-tone | Hierarchical 3D density: large × mid × filament × cavity × core |
| Internal structure | Filaments, clumps, irregular edges | 2D FBM on plane UV | `density(world_pos)` multi-scale, elongated (not sphere blob) |
| Dark cavities | Charcoal holes / dust lanes inside glow | Dark lanes only as 2D UV mask | 3D cavity mask; absorption, not just tint |
| Layering | Foreground dark gas / mid glow / far haze | One plane (+ sky shader wash) | Hybrid: major masses raymarched; thin near wisps; faint sky hint |
| Occlusion | Dense gas hides distant stars | Additive blend never occludes | Mix + optical depth; far stars behind volume |
| Parallax | Camera motion shifts layers | Plane slides as one sheet | Real depth extent → relative motion |
| Colour | Mono mood; bright cores, muted dense interiors | Broad colour wash from sky + planes | Volume owns colour; sky/fog demoted |
| Bright cores | Emission peaks ≠ density peaks | `more density ≈ more brightness` | Thin wisps emit; dense interiors absorb |
| Relationship to stars | Stars in front / inside / behind gas | All stars on far shells vs flat planes | Interleave MultiMesh star distances with volume ranges |

---

## 3. Diagnosis of the current renderer

| Piece | Role today | Why it reads flat |
| --- | --- | --- |
| `SkyComposition.masses` | dir, scale, core, dark, depth, shell | Semantic depth unused as a **range** |
| `nebula.gdshader` | 2D FBM on plane UV | `density = noise(UV)` — no world Z |
| `_build_nebula_layers` | One `PlaneMesh` per mass, look-at origin | Billboard sheet; no thickness |
| `deep_space_sky.gdshader` | Directional mass lobes on sky dome | Full-sky colour fog competing with planes |
| Environment fog | Tiny aerial cue | Must not become the nebula |
| Star MultiMesh | micro/field/notable/gems | Distances don’t systematically pierce volumes |
| Blend mode | Additive | Cannot darken / occlude background stars |

**Root cause:** composition describes masses; rendering evaluates **2D directional noise**, so the eye never gets occlusion, parallax, or cavities-with-thickness.

---

## 4. Target architecture (kept)

```
Simulation
    ↓
SkyComposition  (WHERE / WHAT KIND — deterministic)
    ↓
semantic masses: center, radius, depth_near/far, density,
                 core, cavity, filament, emission, colours, seed
    ↓
visual nebula renderer
    ├── major masses → bounded raymarch (world density)
    ├── minor wisps  → thin depth-offset layers (cheap)
    └── far hint     → subdued sky-shader structure
    ↓
GPU + MultiMesh stars interleaved by depth
```

Hybrid is intentional: raymarch only major masses; do not full-screen 128-step the universe.

---

## 5. Acceptance (volume test)

Put the camera in front of a large mass. Dolly / orbit / pass near dense gas.

| Pass if | Fail if |
| --- | --- |
| “There is a huge cloud of gas over there.” | “Coloured noise behind the ship.” |
| Stars wink through thin gas, vanish in dense | Starfield equally sharp everywhere |
| Cavities stay dark | Whole sky becomes low-opacity wash |
| Parallax between near wisps and far core | Identical sheet under camera motion |

### Metric gates (hybrid restore)

| Metric | Gate | Latest EW (`ew_nebula.png`) |
| --- | --- | --- |
| mid_edge_frac | ≥ 0.25 stretch toward LT planet 0.33 | **0.199** |
| cavity_near_bright | ≤ 0.14 | **0.102** |
| mean_Y | ≥ 0.14 | **0.147** |
| flatness_score | not flatter than LT (+0.05 slack) | **0.356** (`ew_flatter_than_lt=false`) |
| gradient_anisotropy | > 0.15 (stretch) | 0.020 (still short) |

Planet compare score ≈ **85/100**. Remaining gap is mid-frequency edge density / anisotropy vs LT planet stills — chase with filament ridges, not higher cavity or overall density.

### Mood sheet (palette coverage)

Capture with `lt_compare.tscn --nebula-sheet`. Latest sheet (`out/nebula_mood_sheet.png`):

| Mood | Gas B−R | Family |
| --- | --- | --- |
| amber_gold | −0.29 | warm (LT cockpit) |
| magenta_rose | −0.08 | warm (LT ship gas) |
| crimson | −0.29 | warm |
| cyan_teal | +0.23 | cool |
| indigo_violet | +0.21 | cool |
| cold_white | +0.10 | cool |

System hue picks now reserve ~18% amber–gold so random seeds are not cyan-locked.

---

## 6. Implementation notes (LT-aligned path)

**Stop reinventing volumes.** LT’s nebula is a **direction-space IFS bake** (`gen/nebula.glsl` → TexCube), not world fog.

| LT | EternalWar now |
| --- | --- |
| `magic()` Kaliset IFS (30 iters) | `deep_space_sky.gdshader` `magic()` (18 live iters) |
| ~128 absorption samples `p = dir*kScale*i/N` | 40 / 28 samples, **same march path** |
| `ColorLUT` 1D textures | Seeded LUT knots + mild mood tint |
| TexCube env map at runtime | Godot Sky QUALITY radiance bake from `generate(dir)` |
| Separate starfield mesh | MultiMesh star layers (no sparkle lattice in sky) |

### Why it looked like a giant painted sphere
Earlier EW sky added **directional mass lobes, void paints, galaxy-band wash, and a `floor(dir)` sparkle grid** on top of IFS. Those read as soft blobs / tiles on a dome. On Compatibility, REALTIME radiance also showed **cubemap face seams**. LT structure comes only from IFS absorption along the ray — remove dome paints; bake QUALITY radiance; keep cavity emission additive so mediump cannot crush to black.

- World-space `nebula_volume` / billboard wisps stay **off**
- Soft lobe/void/band **paints removed** from `generate()`
- Future closer match: bake TexCube once per seed like `Nebula1.lua` (1024 + mips)
