# LT Wallpaper Gallery

Thin web UI over the **native** Wallpaper App — no WebGL port.

Select a category → bake via `tools/wallpaper.sh` → image lands in the gallery.  
Rate limit: **1 bake per IP per minute**.

**Deploy:** see [`DEPLOY.md`](DEPLOY.md) (systemd VPS install or Docker).

## Categories

Dreams of Limit Theory — scenes from the real engine, not a port.

| UI | Native `preset=` |
|----|------------------|
| Sky | `sky` |
| Ship | `ship` |
| Solo ship | `solo` |
| Fleet | `fleet` (escorts) |
| Skirmish | `skirmish` (Attack AI + turrets) |
| Station | `station` |
| System | `system` (station + rocks + traffic) |
| Asteroids | `asteroids` |
| Planet | `planet` |

## Local run

Requires a built `ltheory` tree (see `../setup.sh`).

```bash
cp .env.example .env   # set LTHEORY_ROOT
./scripts/run.sh
# open http://localhost:8080
make health
```

## Small VPS (1 core / 1 GiB + swap)

Measured peaks (**lt64 + Xvfb** RSS):

| Bake | Peak RAM | Notes |
|------|----------|--------|
| draft · 720p | ~510 MiB | Default under `small` |
| good · 1080p | ~760 MiB | Use swap; slow |
| high · 1080p | ~920 MiB | Avoid on 1 GiB |

```bash
sudo ./scripts/install.sh
# or: LT_GALLERY_PROFILE=small ./scripts/run.sh
```

## API

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/health` | liveness + native tree |
| GET | `/api/meta` | categories, sizes, quality, profile |
| GET | `/api/status` | rate-limit / busy |
| GET | `/api/gallery` | optional `?category=` |
| GET | `/api/image/<id>` | PNG |
| POST | `/api/generate` | `{category, seed?, size, quality, count?}` — `count`>1 keeps one engine process for N plates (max 8) |
