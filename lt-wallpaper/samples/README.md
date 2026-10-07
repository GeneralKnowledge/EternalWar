Sample exports from Linux (`./tools/wallpaper.sh`) are kept as cloud-agent artifacts:

- `/opt/cursor/artifacts/lt_wallpaper_ship.png`
- `/opt/cursor/artifacts/lt_wallpaper_nebula.png`

Regenerate locally:

```bash
./tools/wallpaper.sh seed=42 preset=ship width=1280 height=720 out=wallpaper/demo_ship.png nebulaRes=256
./tools/wallpaper.sh seed=14589938814258111262 preset=nebula width=1280 height=720 out=wallpaper/demo_nebula.png nebulaRes=256
```
