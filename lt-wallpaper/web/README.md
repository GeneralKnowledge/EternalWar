# LT Sky — web wallpaper prototype

Browser toy that runs Josh Parnell’s **direction-space IFS nebula** (`gen/nebula.glsl` `magic()` + absorption march) in **WebGL2**, with:

- Midpoint-displacement **ColorLUT** 1D textures (`Gen.ColorLUT`)
- Native march scale (`kScale=0.040`, up to 128 samples)
- LT **tonemap** (gamma → vignette → expmap → bezier grading)
- Clustered **starfield** point sprites (`Gen.Starfield` + `starbg` falloff)

Not a port of the full game. Not pixel-identical to native `preset=sky` (RNG streams differ), but the same visual grammar.

## Run

Serve this folder over HTTP (modules require it):

```bash
cd lt-wallpaper/web
python3 -m http.server 8765
# open http://localhost:8765
```

## Controls

| UI | Action |
|----|--------|
| Seed | Decimal string → deterministic color / roughness / star dir / LUTs |
| Quality | Draft / Good / High (samples × iterations) |
| Render | Re-derive params from seed and redraw |
| Download PNG | High-quality offscreen export at chosen size |
| Drag canvas | Orbit look direction |

## Files

- `js/shaders.js` — GLSL port of Kaliset IFS + absorption
- `js/rng.js` — seeded param derivation (HSL nebula color like `Nebula1.lua`)
- `js/app.js` — WebGL2 bootstrap, UI, PNG export

## Pipeline

1. Midpoint-displacement ColorLUT → 256×1 textures  
2. Direction-space IFS absorption (`kScale=0.040`, up to 128 samples) → HDR target  
3. Clustered starfield point sprites (additive)  
4. Threshold bloom + unsharp  
5. LT tonemap (gamma → vignette → expmap → bezier grading)

## Next

- Match native uint64 seed stream more tightly  
- Progressive refinement / worker for 4K exports  
- Optional cubemap bake preview (closer to native env path)
