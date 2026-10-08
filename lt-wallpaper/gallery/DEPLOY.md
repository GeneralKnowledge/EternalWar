# Deploy LT Wallpaper Gallery

Thin UI over the **native** `wallpaper.sh` bake. Two paths:

| Path | Best for |
|------|----------|
| **systemd install** (`scripts/install.sh`) | Small VPS (1–2 GiB + swap) |
| **Docker** (`Dockerfile` / Compose) | Build on a bigger machine, run anywhere |

## Quick VPS (recommended for 1 GiB + 2 GiB swap)

On Ubuntu/Debian:

```bash
# from a checkout of this repo
cd lt-wallpaper/gallery
sudo ./scripts/install-deps.sh   # if you only want packages
sudo ./scripts/install.sh        # deps + build ltheory + systemd
```

Then:

```bash
curl -sS http://127.0.0.1:8080/api/health
sudo systemctl status lt-wallpaperd lt-wallpaper-gallery
```

The gallery binds **127.0.0.1:8080** by default — point a tunnel or reverse proxy at that. Optional nginx sample: `deploy/nginx.example.conf`.

A **warm daemon** (`lt-wallpaperd`) keeps one `lt` process loaded so bakes skip cold start. Gallery uses it when `daemon.ready` (`LT_WALLPAPER_DAEMON=auto`).

### What install.sh does

1. Installs build + Xvfb/Mesa packages  
2. Creates system user `ltwallpaper`  
3. Rsyncs `lt-wallpaper/` → `/opt/lt-wallpaper`  
4. Runs `setup.sh` to clone/build Josh’s `ltheory`  
5. Writes `gallery/.env` with `LT_GALLERY_PROFILE=small` when MemTotal ≤ 1.5 GiB  
6. Enables `lt-wallpaperd.service` + `lt-wallpaper-gallery.service`  
7. Stores PNGs in `/var/lib/lt-wallpaper/gallery`, spool in `/var/lib/lt-wallpaper/spool`

### Ops

```bash
sudo systemctl restart lt-wallpaperd lt-wallpaper-gallery
sudo journalctl -u lt-wallpaperd -u lt-wallpaper-gallery -f
sudo edit /opt/lt-wallpaper/gallery/.env   # then restart
```

### Seed the gallery

Bake a batch of plates without the UI (no per-IP rate limit):

```bash
# plan only
sudo -u ltwallpaper /opt/lt-wallpaper/gallery/scripts/fill-gallery.sh -n 20 --dry-run

# ~20 light presets @ draft/720p — expect many minutes each on 1 GiB
sudo -u ltwallpaper /opt/lt-wallpaper/gallery/scripts/fill-gallery.sh -n 20 --mix safe

# leave running in tmux/screen; keep lt-wallpaperd up; avoid UI Generate
```

Images land in `/var/lib/lt-wallpaper/gallery` and show up on refresh.

## Docker

**Build** on ≥4 GiB RAM (LibPHX compile will struggle on 1 GiB):

```bash
cd lt-wallpaper/gallery
docker compose build
docker compose up -d
curl -sS http://127.0.0.1:8080/api/health
```

Runtime env (Compose / `-e`):

- `LT_GALLERY_PROFILE=small` — safe on 1 GiB + swap  
- Volume `gallery-data` → persistent manifest/PNGs  

## Environment

See `.env.example`. Important knobs:

| Var | Purpose |
|-----|---------|
| `LTHEORY_ROOT` | Built checkout with `tools/wallpaper.sh` |
| `LT_GALLERY_DATA` | Gallery disk root |
| `LT_GALLERY_PROFILE` | `small` / `standard` / `full` |
| `LT_GALLERY_RATE_SEC` | Per-IP bake cooldown (default 60) |
| `LT_GALLERY_HOST` / `PORT` | Bind address |
| `LT_WALLPAPER_DAEMON` | `auto` / `on` / `off` — use warm daemon |
| `LT_WALLPAPER_SPOOL` | Job spool shared with `lt-wallpaperd` |
| `LT_WALLPAPER_IR_SAMPLES` | GGX IR samples (default `64`; upstream game used `256`) |
| `LT_WALLPAPER_TIMING` | `1` to log nebula/plate timings in the engine |

## Health

`GET /api/health` → `{ ok, busy, profile, daemon, ltheory }`  
`daemon.ready: true` when the warm process is idle.  
`ok: false` if the native binary tree is missing.

## Expectations on 1 GiB + 2 GiB swap

- Prefer **draft · 720p** (default under `small`)  
- **good** may finish via swap but will be slow  
- One bake at a time; 1/minute rate limit matches the hardware  
