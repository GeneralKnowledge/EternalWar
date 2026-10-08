# Limit Theory Wallpaper Generator (Linux)

Thin App on Josh Parnell’s [`ltheory`](https://github.com/JoshParnell/ltheory) (Unlicense): real IFS nebula bake, ShapeLib ships, LT post stack — export a seeded PNG.

## Linux dependencies

```bash
sudo apt-get install -y \
  build-essential cmake git git-lfs \
  libglew-dev libsdl2-dev libfreetype-dev libluajit-5.1-dev \
  libgl1-mesa-dev libstdc++-14-dev xvfb lua-filesystem
git lfs install
```

Vendored under `libphx/ext/lib/linux64/`: Bullet 2.87, FMOD, lz4.  
`libLinearMath.so.2.87` is included (upstream tree was missing it).

## Build

```bash
git clone --recursive https://github.com/JoshParnell/ltheory.git
# apply wallpaper overlay / checkout this fork branch, then:
python3 configure.py
python3 configure.py build
```

Binary: `bin/lt64r` (Release) or `bin/lt64` (RelWithDebInfo).

## Generate

```bash
# Headless-friendly wrapper (uses Xvfb when DISPLAY is unset)
./tools/wallpaper.sh seed=42 preset=ship width=1920 height=1080 out=wallpaper/demo.png

# Batch — one engine launch, cycle plates, then quit
./tools/wallpaper.sh count=8 preset=fleet outdir=wallpaper/batch
./tools/wallpaper.sh count=6 presets=fleet,skirmish,station,system outdir=wallpaper/dreams

# Best-of — N candidates, keep the highest-scoring plate
./tools/wallpaper.sh best=6 preset=capital out=wallpaper/best_capital.png
./tools/wallpaper.sh best=6 preset=armada out=wallpaper/best_armada.png

# Or directly:
LD_LIBRARY_PATH=libphx/ext/lib/linux64 ./bin/lt64r Wallpaper \
  seed=42 preset=nebula width=2560 height=1440 out=wallpaper/nebula.png
```

### Flags

| Flag | Meaning |
|------|---------|
| `seed=` | System seed (decimal string); batch advances from it |
| `width=` / `height=` | Resolution (default 1920×1080) |
| `out=` | PNG path (`count=1`) or stem template (`count>1` → `stem_001.png`) |
| `outdir=` | Directory for batch PNGs (preferred when `count>1`) |
| `preset=` | `sky` · `ship` · `solo` · `fleet` · `skirmish` · `capital` · `armada` · `station` · `system` · `vista` · `mining` · `aftermath` · `asteroids` · `planet` · `belt` |
| `presets=` | Comma list to cycle across the batch (e.g. `fleet,skirmish,station`) |
| `count=` | Captures before quit; process stays loaded (default 1) |
| `best=` | *(wrapper)* Bake N candidates in one launch; keep the highest-scoring PNG |
| `daemon=1` `spool=DIR` | Stay loaded; pull jobs from `DIR/job.req` |
| `frames=` | Settle frames before capture (default depends on preset) |
| `interactive=1` | Keep window; **F12** capture, **R** regen, **Esc** quit |
| `nebulaRes=` | Override nebula bake resolution |
| `nebulaStyle=` | `ifs` (Nebula1) · `lt` (Nebula2) · `auto` |
| `hull=` | Capital: `sausage` · `triangle` · `top` · `auto` |
| `fighter=` | `standard` · `surreal` · `auto` |
| `thrusters=` | Engine glow on ships (`1` default, `0` off) |
| `superSample=` | `1` / `2` / `4` export supersample (default `2`) |
| `seed=good` | Pick from Josh’s curated goodSeeds |

## Warm daemon

Keeps one `lt` process loaded across bakes (skips GL/script bootstrap each time).

```bash
# Terminal A — supervise the engine
./tools/wallpaperd.py --spool ./wallpaper/spool serve --width 1920 --height 1080

# Terminal B — submit jobs (falls back to cold wallpaper.sh with --cold)
./tools/wallpaperd.py --spool ./wallpaper/spool bake --cold \
  preset=armada best=4 out=wallpaper/out.png
./tools/wallpaperd.py status
```

Spool protocol: `daemon.ready` while idle → client writes `job.req` → daemon writes `job.done` → idle again. Touch `shutdown` to stop.

Gallery uses the daemon automatically when ready (`LT_WALLPAPER_DAEMON=auto`). systemd unit: `lt-wallpaperd.service`.

## Notes

- Nebula bake uses `Config.gen.nebulaRes` (default 1024) — first frame can take several seconds.
- SDL 2.x minor/patch mismatch vs vendored headers is allowed on Linux (major must match).
- This is **not** Limit Theory Redux; it is Josh’s C/Lua tree plus a wallpaper App.
