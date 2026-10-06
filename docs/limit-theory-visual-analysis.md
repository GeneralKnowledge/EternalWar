# Limit Theory Visual Analysis

Living visual-forensics document for EternalWar. Observations come from **official Limit Theory screenshots and wallpapers** and from the open second-generation source — not from inventing a generic “pretty space sky.”

**Goal:** answer *why LT’s space looks good*, document what EternalWar does differently, then close the gap through measured iteration.

This is **not** a clone brief. Reproduce the underlying principles in an independent Godot renderer.

---

## References studied

| Source | URL / path | Used for |
| --- | --- | --- |
| LT media wallpapers & screenshots | [ltheory.com/media](http://ltheory.com/media.html) | Composition, palette, bloom, silhouettes |
| Local LT stills | `/opt/cursor/artifacts/lt-refs/` (`wp_01`, `ss_01`, `ss_03`, `ss_05`, `ss_08`, …) | Side-by-side comparison |
| IndieDB / ModDB LT galleries | public LT screenshot sets | Additional framing / asteroid fields |
| [JoshParnell/ltheory](https://github.com/JoshParnell/ltheory) | `Gen/Starfield.lua`, `Gen/Nebula/*`, `Game/Entities/Nebula.lua`, `res/shader/fragment/gen/nebula.glsl` | Env-map vs starfield split, magnitude curve |
| [Limit-Theory-Redux/ltheory](https://github.com/Limit-Theory-Redux/ltheory) | render / celestial modules | Instancing & sky presentation patterns |
| [JoshParnell/ltheory-old](https://github.com/JoshParnell/ltheory-old) | older LTSL era | Historical visual language |

---

## 1. What the viewer sees first, second, third

Studying LT stills (especially `wp_01`, `ss_01`, `ss_03`, `ss_05`):

| Order | LT reference | Implication |
| --- | --- | --- |
| **1st** | Large luminous structure (nebula mass / galactic band / local star bloom) | Composition must place a **dominant light event** |
| **2nd** | Dark silhouette (planet crescent, ship, station, asteroid against the glow) | Objects need **contrast against structure**, not against empty navy |
| **3rd** | Sparse pinprick stars + rare bright gems | Stars are **supporting cast**, not the wallpaper |

If EternalWar’s first read is “thousands of equal glowing discs on indigo,” the hierarchy is wrong — regardless of shader quality.

---

## 2. Reference observations (stills)

### Wallpaper 01 (`wp_01.jpg`)
Broad luminous band cuts diagonally. **Opaque black dust lanes sit in front of the glow.** Crescent planet ~¼ frame; asteroids as dark cutouts. Corners are deep negative space. One palette family (indigo / violet / cyan-white). Stars subordinate; a few bright events on the band.

### Screenshot 01 (`ss_01.jpg`)
Cool indigo/violet volumetric haze. Blinding local star with bloom. Industrial ship silhouettes in deep shadow. Sparse pinpoints. Large dark frame edges. Asteroids as mid-ground accents, not filled volume.

### Screenshot 03 (`ss_03.jpg`)
Saturated **magenta** nebula with bright cores and charcoal voids. Ship stern dark modular silhouette. Asteroid rim-lit by nebula. Stars denser in darker pockets. Bottom-left void preserves readability.

### Screenshot 05 (`ss_05.jpg`)
Golden-ochre nebula with dark internal dust. Bright star + flare. Asteroids form a **diagonal belt**. Engines bloom; hull stays dark. Large near-black regions.

### Screenshot 08 (`ss_08.jpg`)
Warm peach nebula as soft volume; almost no star points. Asteroids as silhouettes with soft rim. Bloom on true light sources; corners vignette.

### Source: `Nebula.lua` + `gen/nebula.glsl`
TexCube env map via IFS / Kaliset-style iteration, colour LUTs, absorption, central star. Stars are a **separate additive mesh** (`Starfield.lua`). Brightness ~`Exp^2.5` — most dim; blackbody colours.

### Source: `Starfield.lua`
Cluster growth from seeds. Billboard quads far away. Magnitude hierarchy, not uniform Poisson dots.

---

## 3. Comparison table

| Visual characteristic | Limit Theory reference | EternalWar (pre-forensics) | Difference | Proposed / implemented change |
| --- | --- | --- | --- | --- |
| Galactic band | Strong diagonal/axis mass with irregular density, dark gaps, falloff | Soft shader stripe, easy to miss | Band not a compositional anchor | Seeded `galaxy_normal`, width, strength; longitudinal clumps + lanes in sky shader |
| Negative space | Large dark resting regions; ~15–35% near-black in some stills | Relatively uniform indigo fill | No intentional voids | Seeded void cones; density reduced away from masses |
| Nebula scale | Large mass first, then wisps/cavities, then fine texture | Soft additive planes, weak hierarchy | Looks like fog wash | Seeded masses (dir/scale/core/dark); multi-fbm + absorption lanes |
| Nebula contrast | Bright cores + charcoal voids in one palette | Mid brightness everywhere | Weak internal structure | Core glow + dark-lane absorption in sky/nebula shaders |
| Nebula colour | Mono mood per scene (magenta / gold / indigo) | Hue bias but layers uncoordinated | Rainbow soup risk | `SkyComposition.palette` drives sky, planes, ambient, fog, dust |
| Star density | Many subtle + few bright; clustered | Dense but flat hierarchy | Bokeh wallpaper feel | Four tiers: micro / field / notable / gem |
| Bright stars | Rare memorable events | Mostly similar discs | No compositional gems | Explicit gem list on masses/band |
| Star colour | Subtle blackbody | Temperature colour OK | Hierarchy more important than hue | Keep temperature; dim most via mag² curve |
| Local star | Dominant light event, integrates scene | Sphere + corona discs | Can feel pasted | Star colour → directional light; cinema/rim vs mass |
| Bloom | Strong on light sources; blacks stay black | Washed or too timid | Wrong threshold | Filmic + mid glow, HDR threshold ~1.05 |
| Exposure | Deep readable blacks + luminous cores | Variable | Crush or wash | Exposure ~1.0 filmic; contrast nudge 1.08 |
| Planet silhouette | Crescent/rim against luminous sky | Readable but often on empty navy | Weak authority | Cinema camera opposite primary mass |
| Station silhouette | Industrial modules, scale, negative space | Modular but soft | Weak sky contrast | Stronger massing + beacon emissive |
| Ship silhouette | Role grammar, engines as light events | Role grammar exists | Soft industrial density | Tightened proportions; engine FX near camera |
| Asteroid field | Belts/clusters with gaps | More isotropic scatter | Random cloud | Composition-driven yields; belt bias retained |
| Depth cues | Env map + dust lanes + parallax feel | Mostly single-distance planes | Flat | Multi-shell stars + layered nebula depths |
| Overall composition | Bright region + dark region + anchors | “Filled sky” | No graph | `SkyComposition` WHERE → shaders WHAT |

---

## 4. Visual principles (rules)

1. **Sky is a composition system**, not a background fill.
2. **Preserve large dark regions.** Beauty needs negative space.
3. **One palette family per system.**
4. **Multi-frequency:** low (masses/band), medium (wisps/clusters), high (stars/gems).
5. **Separate WHERE (seeded composition) from WHAT (shaders).**
6. **Star hierarchy:** thousands subtle → dozens notable → few exceptional.
7. **Objects read as silhouettes** against luminous structure.
8. **Bloom serves light sources**, not the whole frame.
9. **Asteroids are belts/clusters**, not isotropic scatter.
10. **Do not clone screenshots** — reproduce the *thinking*.

Architecture:

```
              SYSTEM SEED
                  │
                  ▼
        ┌──────────────────┐
        │ Sky Composition  │  ← WHERE + palette
        └────────┬─────────┘
       ┌─────────┼─────────┐
       ▼         ▼         ▼
    Sky shader  Stars    Nebula geometry
```

---

## 5. Acceptance checklist

Put LT stills next to EternalWar showcase screenshots:

### Sky
- [x] Convincing large-scale structure (band + masses)
- [x] Intentional negative space (void cones)
- [x] Galactic band irregular (clumps + gaps along longitude)
- [x] Nebulae multi-frequency (masses + multi-fbm + dark lanes)
- [x] Bright stars rare; ordinary stars subtle (4-tier hierarchy)
- [x] Background dark but readable

### Objects
- [x] Local star luminous; drives directional light colour
- [x] Planet silhouette against primary mass (cinema/showcase framing)
- [x] Atmosphere rim controlled
- [x] Ships / stations silhouette pass (massing + beacons)
- [x] Asteroid fields composition-driven belts

### Overall
- [x] LT principles, independent EternalWar look
- [x] Clear visual hierarchy from composition graph
- [x] Deterministic seeds; 81 headless tests; NativeBridge travel/transforms intact

### Honest remaining gaps
- No full TexCube / Kaliset env-map bake yet (billboard + sky approximation)
- Bloom/lens character softer than early LT promo stills
- Ship greeble density below ShapeLib surface detail

Iterate composition first; polish last.

---

## 6. Implementation mapping (this milestone)

| Piece | Path |
| --- | --- |
| Composition | `presentation/sky_composition.gd` |
| Sky shader | `shaders/deep_space_sky.gdshader` |
| Nebula shader | `shaders/nebula.gdshader` |
| Star populations | `presentation/generators/starfield_gen.gd` |
| Presenter wiring | `presentation/system_presenter.gd` |
| Showcase | `scenes/visual_showcase.tscn` (keys 1–6, `[` `]` seed, R regen) |
| Main cinema | opposite primary mass; `[` `]` / R / F5 |

References: [ltheory.com/media](http://ltheory.com/media.html); [JoshParnell/ltheory](https://github.com/JoshParnell/ltheory) `Nebula.lua`, `Starfield.lua`, `gen/nebula.glsl`.
