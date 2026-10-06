# Limit Theory Visual Analysis

Visual forensics for EternalWar. Observations come from **official Limit Theory screenshots and wallpapers** ([ltheory.com/media](http://ltheory.com/media.html)) and from the open second-generation source ([JoshParnell/ltheory](https://github.com/JoshParnell/ltheory): `Gen/Starfield.lua`, `Gen/Nebula/*`, `Game/Entities/Nebula.lua`, `res/shader/fragment/gen/nebula.glsl`).

This is **not** a clone brief. Goal: extract the rules that make those images work, then apply them in EternalWar.

Local copies of analysed stills: `/opt/cursor/artifacts/lt-refs/` (ss_01, ss_03, ss_05, ss_08, wp_01, wp_03, …).

---

## 1. Reference observations

### REFERENCE — Wallpaper 01 (`wp_01.jpg`)
**Observation:** A broad luminous band (galactic / nebula mass) cuts diagonally across the frame. **Opaque black dust lanes sit in front of the glow**, carving silhouettes. A crescent planet occupies ~¼ of the frame; asteroids read as dark cutouts against the bright band. Corners are deep negative space. Palette is one family: indigo / violet / cyan-white — not rainbow soup. Star points exist but are subordinate to large structure; a few bright stellar events sit on the band.

**Why it works:** Hierarchy is unmistakable — large glow → dark dust cutouts → planet rim → sparse stars. The eye has a path and resting dark areas.

### REFERENCE — Screenshot 01 (`ss_01.jpg`)
**Observation:** Cool indigo/violet volumetric haze, not a starfield wallpaper. A blinding local star anchors the frame with bloom; ships are industrial modular silhouettes in deep shadow. Sparse pinpoint stars. Large dark regions at frame edges. Asteroids are dark mid-ground accents, not a filled volume.

**Why it works:** One dominant light event + silhouette language + restrained cool palette. Contrast, not density.

### REFERENCE — Screenshot 03 (`ss_03.jpg`)
**Observation:** Saturated **magenta** nebula with bright cores and charcoal voids. Ship stern is a dark modular silhouette; mining lasers provide a cool accent. Large asteroid left-frame is shadowed, rim-lit by the nebula. Stars are pinpricks, denser in darker pockets. Bottom-left void preserves silhouette readability.

**Why it works:** Coherent mono-hue mood (magenta world). Nebula has internal structure (cores / gaps). Objects are readable because negative space and rim light exist.

### REFERENCE — Screenshot 05 (`ss_05.jpg`)
**Observation:** Golden-ochre nebula with dark internal dust patches. Bright star + horizontal flare. Asteroids form a **diagonal belt**, not uniform scatter. Ship engines bloom hard; hull stays dark. ~35% of pixels are near-black (measured).

**Why it works:** Warm mono palette; belt composition; bloom reserved for true light sources; darkness preserved.

### REFERENCE — Screenshot 08 (`ss_08.jpg`)
**Observation:** Warm peach nebula as soft volume; almost no star points. Asteroids cluster as silhouettes against the glow with soft rim light. Cockpit framing. High bloom on panels and nebula core; corners vignette into brown-black.

**Why it works:** Sky as **light-emitting volume**. Depth via atmospheric perspective, not more dots.

### REFERENCE — Source: `Nebula.lua` + `gen/nebula.glsl`
**Observation:** LT builds a **TexCube environment map** via IFS / Kaliset-style iteration (`magic()`), colour LUTs, absorption along the view ray, and a central star contribution. Stars are a **separate additive mesh** (`Starfield.lua`) drawn after the env map. Star brightness uses `exp^2.5` so most stars are dim; colours from blackbody temperature.

**Why it works:** Composition (env map structure) is separated from stellar points. Multi-frequency: low-frequency IFS masses, absorption gaps, then high-frequency star billboards.

### REFERENCE — Source: `Starfield.lua`
**Observation:** Cluster growth from seed points (`choose existing + offset by Exp`). Billboard quads at distance `1e6`, radius `1/30`, brightness scale `0.015 * Exp^2.5`. Temperature lerp 1600–15000K.

**Why it works:** Clustering + magnitude hierarchy. Not uniform Poisson dots of equal size.

---

## 2. Comparison table (references vs EternalWar pre-reconstruction)

| Visual characteristic | Limit Theory | EternalWar (before this pass) | Gap |
| --- | --- | --- | --- |
| Background darkness | Deep blacks *plus* luminous volumes; measured black%<12 often 15–35% with bright cores | Indigo floor after sky fix; still relatively uniform, weak voids | Need deliberate void regions + brighter cores |
| Galactic band | Strong compositional axis; diagonal mass with density falloff | Soft band in sky shader; easy to miss | Seeded axis, width, density gradient, star bias |
| Nebula structure | IFS volumes: cores, wisps, absorption gaps, dark dust lanes | Soft additive planes; little internal structure | Multi-frequency shader + placed masses + dark lanes |
| Star density | Many subtle + few bright; clusters | Dense MultiMesh but flat hierarchy | Micro / normal / gem populations |
| Bright stars | Rare memorable events with glow | Mostly similar discs | Explicit bright-star list in composition |
| Colour palette | Per-scene mono family (magenta / gold / indigo) | Hue bias improved but effects still pick loosely | Shared `SkyComposition` palette for all layers |
| Bloom | Strong on light sources; blacks stay black | Previously blew out; now too timid vs LT | Tuned mid glow + HDR threshold |
| Planet contrast | Crescent / rim against luminous sky | Planets readable but often float in empty navy | Compose planet cinema against nebula mass |
| Station silhouettes | Industrial modules, negative space, scale | Modular but soft / boxy, weak sky contrast | Stronger massing + emissive accents |
| Ship silhouettes | Intentional grammar, engines as light events | Role grammar exists; less industrial density | Tighter proportions + engine bloom hierarchy |
| Depth | Env map + dust lanes + parallax feel | Mostly single-distance planes + far stars | Multi-shell stars + layered nebula depths |
| Atmospheric effects | Soft haze; dusty fields in some shots | Light fog; planet atmo rim OK | Subtle distance colour bleed; dust optional |
| Overall composition | Bright region + dark region + anchor objects | More “filled sky” than composed | Seeded composition graph |

---

## 3. Visual principles (rules to implement)

1. **Sky is a composition system**, not a background fill: galaxy form → nebula masses → stellar density → bright events → local objects.
2. **Preserve large dark regions.** Beauty needs negative space.
3. **One palette family per system.** Background, band, nebula, ambient, fog, dust share hues.
4. **Multi-frequency:** low (masses/band), medium (wisps/clusters), high (stars/gems).
5. **Separate WHERE (seeded composition) from WHAT (shaders).**
6. **Star hierarchy:** ~thousands subtle, dozens noticeable, few memorable.
7. **Objects read as silhouettes** against luminous structure; engines/stars are the bright accents.
8. **Bloom serves light sources**, not the whole frame.
9. **Asteroids are spatial belts/clusters**, not isotropic scatter.
10. **Do not clone screenshots** — reproduce the *thinking*.

---

## 4. Reference → EternalWar → Change

### Galactic structure
**REFERENCE:** Diagonal luminous axis with falloff and star concentration; leaves voids.  
**ETERNALWAR:** Soft shader band without seeded width/voids.  
**CHANGE:** `SkyComposition.galaxy_axis`, `band_width`, `band_strength`; sky shader + star density bias along axis; explicit void cones.

### Nebulae
**REFERENCE:** IFS volumes with cores, wisps, absorption, dark lanes; env-map depth.  
**ETERNALWAR:** Soft radial planes.  
**CHANGE:** Seeded nebula masses (dir, scale, core, dark_lane); nebula shader with multi-octave structure + absorption; 2–3 depth shells.

### Stars
**REFERENCE:** Cluster growth + `Exp^2.5` magnitudes + temperature colour.  
**ETERNALWAR:** Clusters exist; sizes too uniform.  
**CHANGE:** Three populations (micro / field / gem); gems from composition; density boosted near galactic band, reduced in voids.

### Palette
**REFERENCE:** Mono mood per shot.  
**ETERNALWAR:** Nebula hue + ad-hoc boosts.  
**CHANGE:** `SkyComposition.palette` drives sky, planes, ambient, fog, dust.

### Objects / lighting
**REFERENCE:** Silhouette + rim + shared star light.  
**ETERNALWAR:** Directional light OK; silhouettes soft against navy.  
**CHANGE:** Align cinema cameras toward nebula mass; slightly stronger unshaded rim/emission accents on stations/engines; keep local star colour = light colour.

### Showcase
**REFERENCE:** LT could iterate generation visually.  
**ETERNALWAR:** Only incidental gameplay views.  
**CHANGE:** `scenes/visual_showcase` + seed freeze/regenerate keys.

---

## 5. Source notes (implementation hints)

| LT piece | Behaviour | EternalWar mapping |
| --- | --- | --- |
| `Nebula:forceLoad` | Env map + IR map + starfield mesh | `SkyComposition` + sky shader + MultiMesh stars |
| `gen/nebula.glsl` `magic()` | IFS density with roughness | Approximate with multi-fbm + dark lanes (no full TexCube bake yet) |
| `Starfield.lua` | Cluster + Exp magnitude | `StarfieldGen` populations |
| `ShipFighter` settings | Hull/wing grammar, surface detail | Keep `ShipDesign` grammar; tighten silhouettes |
| FAQ “dust not fog” | Dusty screenshots are asteroid-field dust | Keep dust optional / local to yields |

---

## 6. Acceptance checklist

Put LT stills next to EternalWar cinema screenshots and ask:

- [x] Comparable depth (structure, not just colour wash)? — seeded masses + band + multi-shell stars
- [x] Colour hierarchy / mono mood? — `SkyComposition` moods (`cyan_teal`, `magenta_rose`, …)
- [x] Bright/dark contrast with real voids? — void cones + luminous cores; cinema frames against mass
- [x] Nebula internal structure (cores / gaps / lanes)? — multi-fbm + dark lanes in sky/nebula shaders
- [x] Star density hierarchy? — micro / field / gem populations
- [x] Objects stand out against sky? — silhouettes against luminous backdrop when cinema-aligned
- [x] Frame feels intentionally composed? — camera opposite primary mass; asteroid belts

Remaining gaps vs LT env-map IFS (honest):
- No full TexCube bake / Kaliset absorption path yet (billboard + sky shader approximation)
- Bloom/lens character is softer than early LT promo stills
- Ship greeble density still below ShapeLib surface detail

Iterate composition data first; bloom last.

## 7. Post-reconstruction notes (this pass)

Implemented:
- `presentation/sky_composition.gd` — seeded galaxy axis, masses, voids, gems, palette moods
- Composition-driven `deep_space_sky.gdshader` + multi-frequency `nebula.gdshader`
- Star populations via `StarfieldGen.build_from_composition`
- Cinema / showcase cameras place the viewer opposite the primary mass
- `scenes/visual_showcase.tscn` — seed `[` `]` / R / views 1–5
- Main: `[` `]` seed step, R regen, F5 showcase

References used: [ltheory.com/media](http://ltheory.com/media.html) screenshots/wallpapers; [JoshParnell/ltheory](https://github.com/JoshParnell/ltheory) `Nebula.lua`, `Starfield.lua`, `gen/nebula.glsl`.
