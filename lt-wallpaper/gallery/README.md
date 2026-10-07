# LT Wallpaper Gallery

Thin web UI over the **native** Wallpaper App — no WebGL port.

Select a category → bake via `tools/wallpaper.sh` → image lands in the gallery.  
Rate limit: **1 bake per IP per minute**.

## Categories

| UI | Native `preset=` |
|----|------------------|
| Sky | `sky` |
| Ship | `ship` (fighter + rocks) |
| Solo ship | `solo` (fighter only) |
| Asteroids | `asteroids` |
| Planet | `planet` |

## Run

Requires a built `ltheory` tree (see `../setup.sh`).

```bash
# optional: export LTHEORY_ROOT=/path/to/ltheory
cd lt-wallpaper/gallery
python3 server.py --port 8787
# open http://localhost:8787
```

Gallery files live in `data/` (manifest + PNGs). Seed batch copies may be present from bring-up.

## Small VPS (1 core / 1 GiB)

Measured peaks (**lt64 + Xvfb** RSS) on Linux:

| Bake | Wall (this host*) | Peak RAM |
|------|-------------------|----------|
| draft · 720p · nebulaRes 256 | ~7–8 s | ~510 MiB |
| good · 1080p · 512 | ~20 s | ~760 MiB |
| high · 1080p · 1024 | ~70 s | ~920 MiB |

\*Times assume a decent GL path. On a **software-GL** 1‑core VPS expect **several× slower** (often 30s–3+ min for draft).

**Verdict for 1 GiB:**

- Idle gallery server: fine (tens of MiB).
- **draft / 720p**: workable if the OS stays lean; leave ~400 MiB free before bake.
- **good / 1080p**: risky — often OOMs once kernel + Python are counted.
- **high / 1440p**: do not run.

Auto profile: if `MemTotal ≤ 1536 MiB`, server selects `small` (only 720p; draft/good; default draft). Override with:

```bash
LT_GALLERY_PROFILE=small python3 server.py --port 8787   # force caps
LT_GALLERY_PROFILE=standard python3 server.py --port 8787
```

Keep the **1 bake / minute** limit — on one core a bake already saturates CPU for the whole duration.

## API

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/meta` | categories, sizes, quality |
| GET | `/api/status` | rate-limit / busy |
| GET | `/api/gallery` | optional `?category=` |
| GET | `/api/image/<id>` | PNG |
| POST | `/api/generate` | `{category, seed?, size, quality}` |
