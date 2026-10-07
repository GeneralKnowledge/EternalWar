# LT Sky — web wallpaper prototype

Browser toy that runs Josh Parnell’s **direction-space IFS nebula** (`gen/nebula.glsl` `magic()` + absorption march) in **WebGL2**, plus a procedural starfield.

Not a port of the full game. Not pixel-identical to native `preset=sky` (different RNG / LUT construction), but the same visual grammar.

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

## Next

- Closer ColorLUT (midpoint-displacement 1D textures)
- Match native seeds more tightly
- Optional worker / progressive refinement for 4K
