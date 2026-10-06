# Limit Theory Rendering Forensics

Direct study of **JoshParnell/ltheory** + **JoshParnell/libphx** against official LT screenshots (`tools/visual_compare/reference/`).

Goal: extract what the screenshots and source actually do — not invent another generic space look.

---

## 1. Pipeline facts (from source)

### Nebula / sky background

| Fact | Evidence |
| --- | --- |
| Nebula is a **baked TexCube env map**, not a live world-space volume | `Game/Entities/Nebula.lua` → `Gen.Generator.Get('Nebula')` → `envMap`, then `genIRMap(256)` |
| Density is **Kaliset IFS** (`magic()`) + absorption along the view ray | `res/shader/fragment/gen/nebula.glsl` — 30 iters, 128 samples, LUT colouring |
| Rendered as **farplane skybox** (depth write off) | `Nebula:render` `BlendMode.Disabled` + `Cache.Shader('farplane', 'skybox')` |
| Stars drawn **after**, additive, sampling env/IR | `BlendMode.Additive` + `starbg` + `stars:draw()` |

### Stars

| Fact | Evidence |
| --- | --- |
| Separate mesh of billboard quads at distance `1e6` | `Gen/Starfield.lua` |
| Cluster growth: choose existing + offset by `Exp` | same |
| Brightness `0.015 * Exp^2.5` — most faint | same |
| Blackbody colour 1600–15000K | `Color.FromTemperature` |
| Soft disc falloff in `starbg.glsl` | `exp(-9*sqrt(r))` + `exp(-(30r)^2)` |

### Post-processing (`phx/util/Renderer.lua`)

| Effect | Default | Notes |
| --- | --- | --- |
| Bloom | on, radius **48** | downsample → blur → composite ×3 |
| Tonemap | on | `1 - exp(-k * pow(c, 1.25 + c))` with `k=2.3` (`filter/tonemap.glsl`) |
| Vignette | on, strength 0.25 | applied **before** tonemap so HDR leaks into edges |
| Sharpen | on | |
| Aberration / radial blur | off by default | |

### Measured LT screenshot stats

| Reference | meanY | dark% | bright% | sat |
| --- | --- | --- | --- | --- |
| `lt_nebula_planet` | 0.175 | 37.9 | 7.5 | 0.53 |
| `lt_nebula_ship` | 0.210 | 27.2 | 8.3 | 0.56 |
| `lt_asteroids` | 0.151 | 39.8 | 7.0 | 0.45 |
| `lt_star_system` | 0.309 | 2.8 | 10.4 | 0.42 |
| `lt_nebula_cockpit` | 0.296 | 18.6 | 16.1 | 0.30 |

**Pattern:** nebula/asteroid frames keep **~27–40% near-black** and **~7–10% bright**. Not a full-frame colour wash.

---

## 2. Comparison table

| Visual property | LT screenshot evidence | LT source-code evidence | EternalWar currently | Required change |
| --- | --- | --- | --- | --- |
| Nebula representation | Soft volumetric *look*, irregular cavities | **TexCube bake** via IFS + absorption | World-space raymarch spheres + UV wisps + sky lobes | Prefer **direction-space IFS sky / cubemap**; volumes secondary |
| Nebula depth | Feels deep | Ray samples in *direction* during bake, then skybox | Live 3D raymarch along camera rays through spheres | Match bake model: `density(dir)` / IFS along view ray |
| Negative space | Large dark regions | Absorption + opacity; not full-sky fill | Sky + volumes often fill too much mid-tone | Enforce dark floor; reduce mid wash |
| Stars | Many tiny, few gems | `Exp^2.5`, brightness 0.015, far mesh | 4-tier MultiMesh — hierarchy OK, scale/brightness off | Match Exp curve + lower baseline brightness |
| Star/nebula interaction | Stars tinted/suppressed by gas | `starbg` mixes envMap into star colour | Additive stars; volume absorption partial | Sample sky/env tint; keep far stars behind |
| Local star | Dominant bloom event | Central star term in `generate(dir)` + scene lights | Sphere + corona + DirectionalLight | Keep; align bloom/exposure with LT post |
| Bloom | Strong on lights, blacks stay | radius 48, HDR composite | Glow intensity ~0.38–0.42, timid vs LT | Increase bloom character carefully |
| Tonemap / grade | Film look, vignette | expmap + bezier grade + vignette-before-tonemap | Filmic + mild contrast | Closer expmap; subtle vignette |
| Fog | Not the nebula | Fog separate / often 0 in starbg | Environment fog used lightly | Keep fog aerial-only |
| Objects | Dark silhouettes vs luminous sky | PBR/deferred materials + env lighting | Unshaded/simple materials | Prefer silhouette + env tint first |

---

## 3. What NOT to conclude

- “Volumetric” in the modern raymarch-sphere sense is **not** how LT produced the look. The look comes from **IFS cubemap + absorption + separate stars + aggressive bloom/tonemap**.
- More FBM octaves on planes will not close the gap.
- Copying LT GLSL verbatim is out of scope; reproducing the **principles** is in scope.

---

## 4. Comparison workflow

```
tools/visual_compare/
  reference/          # real LT stills
  eternalwar/         # EW captures from lt_compare showcase
  out/                # side-by-side, diff, luma, JSON scores
  compare.py
```

Showcase: `scenes/lt_compare.tscn` — deterministic cameras for EMPTY / NEBULA / STAR / SHIP / STATION / ASTEROIDS.

Loop: capture → `compare.py` → fix largest ranked mismatch → repeat.

---

## 5. Baseline scores (this pass — IFS sky + Exp^2.5 stars + bloom)

After switching primary nebula to direction-space IFS (LT `generate(dir)` principle) and retuning stars/bloom:

| Pair | Score | Largest mismatch |
| --- | --- | --- |
| LT nebula_ship ↔ EW nebula | **70/100** | Colour balance, dark_frac |
| LT asteroids ↔ EW asteroids | **63/100** | Colour balance, dark_frac |
| LT star_system ↔ EW star | **85/100** | Highlight p90 (bloom/corona) |
| LT nebula_planet ↔ EW nebula | **58/100** | dark_frac still high vs LT |

Earlier bug (Environment glow property abort) produced flat grey captures at ~40–53; fixed before scoring.

**Next largest gaps:** raise mid-luminance nebula structure without washing voids; closer mono mood colour; optional TexCube bake for LT-parity IFS quality.
