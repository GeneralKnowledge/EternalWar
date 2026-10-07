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

## API

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/meta` | categories, sizes, quality |
| GET | `/api/status` | rate-limit / busy |
| GET | `/api/gallery` | optional `?category=` |
| GET | `/api/image/<id>` | PNG |
| POST | `/api/generate` | `{category, seed?, size, quality}` |
