# Visual compare — Limit Theory vs EternalWar

## Layout

```
reference/           Real LT environment screenshots
reference/ships/     Real LT ship screenshots
eternalwar/          EW environment captures (lt_compare.tscn)
eternalwar/ships/    EW ship gallery captures (ship_gallery.tscn)
out/                 Environment side-by-side / scores
out/ships/           Ship silhouette + side-by-side / scores
compare.py           Environment comparison
ship_compare.py      Ship silhouette / proportion comparison
```

## Environment capture

```bash
godot --path . --rendering-driver opengl3 --resolution 1280x720 \
  res://scenes/lt_compare.tscn -- --capture=/workspace/tools/visual_compare/eternalwar
```

## Ship gallery capture

```bash
godot --path . --rendering-driver opengl3 --resolution 1280x720 \
  res://scenes/ship_gallery.tscn -- --capture=/workspace/tools/visual_compare/eternalwar/ships
```

Interactive: `ship_gallery.tscn` — **1–8** roles, **V** view, **S** silhouette, **Q/E** seed, **A** capture all.

## Compare

```bash
# Environment
python3 tools/visual_compare/compare.py \
  --lt tools/visual_compare/reference/lt_nebula_ship.jpg \
  --ew tools/visual_compare/eternalwar/ew_nebula.png \
  --out tools/visual_compare/out/cmp_nebula

# Ships (silhouette-first)
python3 tools/visual_compare/ship_compare.py \
  --lt tools/visual_compare/reference/ships/lt_ship_fighter_rear.jpg \
  --ew tools/visual_compare/eternalwar/ships/ew_ship_patrol_s42_three_quarter.png \
  --out tools/visual_compare/out/ships/cmp_patrol
```

## Loop

1. Capture EW
2. Compare against the matching LT reference
3. Fix the largest ranked mismatch (silhouette before materials)
4. Repeat
