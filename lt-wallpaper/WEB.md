# Web port — what’s realistic

## Full game in the browser

**Not a near-term project.** Josh’s stack is C++ LibPHX + **LuaJIT** + OpenGL compatibility + Bullet + FMOD. Hard blockers:

| Piece | Web problem |
|-------|-------------|
| LuaJIT | No WASM target; need Lua 5.1 / LuaJIT-less rewrite of hot paths |
| OpenGL compat profile | WebGL2 is a different subset; many shaders/paths need rework |
| FMOD / SDL / desktop IO | Replace with WebAudio / browser input / virtual FS |
| Bake cost | Nebula TexCube at 1024 is heavy for main-thread browsers |

Limit Theory Redux (Rust + mlua/LuaJIT) has the same LuaJIT / native-window issues. Nobody has shipped a WASM port.

## What *would* be sick (and feasible)

**Web wallpaper generator** — not the whole game:

1. Port `gen/nebula.glsl` IFS + absorption to a **WebGL2 / WebGPU** fragment shader (or bake offline → cubemap CDN).
2. Starfield as a GPU particle / instanced point cloud (`Starfield.lua` curve).
3. Seed scrubber + resolution + download PNG in the browser.
4. Optional later: ShapeLib fighter as a small WASM mesh bake, or precomputed GLBs.

That reuses the *look* without dragging physics, economy, or LuaJIT into Chrome.

## Suggested sequence

1. Keep native Wallpaper App (Win/Linux) as the source of truth for seeds/presets.
2. Prototype sky-only shader in a static web page (no engine).
3. Match seeds against native `preset=sky` exports.
4. Only then consider WASM for ShapeLib / heavier bakes.

Unlicense on Josh’s original materials helps for a public web toy.
