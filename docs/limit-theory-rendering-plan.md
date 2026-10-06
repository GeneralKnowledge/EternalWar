# Limit Theory Rendering Plan (EternalWar)

Derived from `docs/limit-theory-rendering-forensics.md` and measured screenshot stats.

---

## Background

**Use a direction-space nebula (virtual / baked cubemap), not world-space fog volumes as the primary colour source.**

| Layer | Representation | Owner |
| --- | --- | --- |
| Far sky / nebula | Sky shader sampling IFS-style density along `EYEDIR` (LT `generate(dir)` principle); optional bake to cubemap later | GPU sky |
| Galactic structure | Soft band + IFS modulation from `SkyComposition` | GPU sky |
| Negative space | Explicit void cones + absorption darkness | `SkyComposition` + sky |
| Stars | MultiMesh billboards, Exp^2.5 magnitudes, far distance | Presentation + optional Rust pack |
| Local star | Mesh + corona + DirectionalLight | Presentation |
| Objects | Existing procedural meshes; silhouette against sky | Presentation |
| Post | Filmic/expmap tonemap, stronger bloom on peaks, light vignette | Environment |

World-space `nebula_volume` raymarch becomes **optional accent / near wisps**, not the authority for frame colour.

---

## Galaxy

Seeded galactic normal + band width/strength from `SkyComposition` (keep). Band should modulate IFS density, not paint a bright stripe.

## Nebula

1. **Primary:** Kaliset-inspired `magic(dir)` + short absorption loop in `deep_space_sky.gdshader`, driven by composition palette + seed.
2. **Secondary:** Thin depth-offset wisps only where composition places masses.
3. **Future (if still short of LT):** bake TexCube once per system seed (Viewport or native), sample as skybox — closest to LT `Nebula.lua`.

## Stars

Match `Starfield.lua` intent:

- cluster growth (already)
- `brightness ∝ Exp^2.5` with low baseline
- blackbody colours
- far shell; micro behind nebula
- rare gems

## Local stars

Keep temperature colour → light. Bloom must catch the star disk. Scene ambient stays low so silhouettes read.

## Objects

Do not redesign ships this pass. Prioritise lighting/exposure so silhouettes match LT composition language.

## Post-processing

| Effect | Plan |
| --- | --- |
| Tonemap | Filmic or custom closer to `1-exp(-k*c^p)` |
| Bloom | Raise intensity/radius character; keep HDR threshold so blacks survive |
| Vignette | Mild, pre-tonemap if possible |
| Fog | Aerial only — never nebula |

## Native (Rust) — when justified

| Candidate | Why | Priority |
| --- | --- | --- |
| Star SoA pack / instance fill | Already started on kernel branch; hot path | Medium |
| Cubemap bake density field | Heavy IFS sample grid | High *if* we bake TexCube |
| Asteroid/instance buffers | Already planned | Low this pass |

Do **not** move shaders to Rust. Do **not** rewrite simulation.

## GDScript remains

- `SkyComposition` semantics
- Presenter wiring
- Showcase / compare capture
- Simulation

## GPU

- Sky IFS
- Star billboard shader
- Bloom/tonemap (Godot Environment)
- Optional volume accents

---

## Iteration order (largest mismatch first)

1. Background luminance / dark fraction vs LT refs  
2. Nebula representation (IFS sky vs fog volumes)  
3. Star magnitude hierarchy / density  
4. Bloom + tonemap character  
5. Colour mood / saturation  
6. Object lighting  
7. Fine detail  

## Definition of progress

A compare.py score climbing on the five reference situations, with dark_frac and mean_Y within a small band of LT stats — not “more pretty effects.”
