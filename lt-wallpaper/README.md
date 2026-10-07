# Limit Theory Wallpaper Generator

Seeded space wallpapers from **Josh Parnell’s** [`ltheory`](https://github.com/JoshParnell/ltheory) (Unlicense) — real IFS nebula bake, ShapeLib ships, LT post stack.

This folder is a **Linux-ready overlay** on a pinned upstream checkout. EternalWar’s Godot “look like LT” ladder is parked; the look lives here.

## Samples (Linux export)

Generated on Linux during bring-up (see agent artifacts / regenerate via `tools/wallpaper.sh`):

- ship — `seed=42`, 1280×720
- nebula — good seed `14589938814258111262`, 1280×720

See [`samples/README.md`](samples/README.md).

## Quick start (Linux)

```bash
# deps
sudo apt-get install -y build-essential cmake git git-lfs \
  libglew-dev libsdl2-dev libfreetype-dev libluajit-5.1-dev \
  libgl1-mesa-dev libstdc++-14-dev xvfb lua-filesystem

git lfs install

# clone upstream + apply this overlay + build
./lt-wallpaper/setup.sh

# generate
cd lt-wallpaper/ltheory
./tools/wallpaper.sh seed=42 preset=ship width=1920 height=1080 out=wallpaper/out.png
```

See [`overlay/WALLPAPER.md`](overlay/WALLPAPER.md) for flags and details.

## What the overlay changes

- `script/App/Wallpaper.lua` — seed / size / preset / PNG export App
- `tools/wallpaper.sh` — Linux launcher (Xvfb + `LD_LIBRARY_PATH`)
- Linux build: SDL minor mismatch allowed, RelWithDebInfo default names, Bullet `LinearMath` + `lfs.so` vendored
- Soft-load LuaJIT debug modules (distro LuaJIT ≠ beta3)

Pinned upstream: `JoshParnell/ltheory` @ `21d450406b2a742b2773692198e7a908a9978ec4` (+ `libphx` submodule).
