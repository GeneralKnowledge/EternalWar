# Web — what’s realistic

## Full game in the browser

**Not worth it.** Josh’s stack is C++ LibPHX + LuaJIT + OpenGL compat. No WASM LuaJIT path; a faithful client port is a rewrite.

## Right approach: gallery over native bake

Ship a thin HTTP UI that shells out to the **already-working** Wallpaper App:

→ [`gallery/`](gallery/) — selectable categories, 1 bake / minute / IP, persistent gallery of PNGs.

```bash
cd lt-wallpaper/gallery
python3 server.py --port 8787
```

That reuses the real IFS / ShapeLib / tonemap path. No second renderer.

## Abandoned experiment

[`web/`](web/) was a WebGL2 sky toy. It diverged from native look and isn’t the product path — keep only as historical reference.
