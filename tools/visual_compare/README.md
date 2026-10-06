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

## Fighter diagnostic gallery

Canonical `LT_FIGHTER_REFERENCE` (seed 42, PATROL, military):

```bash
godot --path . --rendering-driver opengl3 --resolution 1280x720 \
  res://scenes/lt_fighter_gallery.tscn -- \
  --capture=/workspace/tools/visual_compare/eternalwar/fighter
```

Modes: silhouette / clay / material / lit / compare / ortho. Keys **1–6**, **V** view, **F** 20-seed family.

```
eternalwar/fighter/   EW fighter diagnostic captures
```

## Compare

```bash
# Environment
python3 tools/visual_compare/compare.py \
  --lt tools/visual_compare/reference/lt_nebula_ship.jpg \
  --ew tools/visual_compare/eternalwar/ew_nebula.png \
  --out tools/visual_compare/out/cmp_nebula

# Ships (silhouette IoU first, then mass / luminance / colour)
python3 tools/visual_compare/ship_compare.py \
  --lt tools/visual_compare/reference/ships/lt_ship_fighter_rear.jpg \
  --ew tools/visual_compare/eternalwar/fighter/ew_fighter_s42_silhouette_three_quarter_front.png \
  --out tools/visual_compare/out/ships/cmp_fighter_sil

python3 tools/visual_compare/ship_compare.py \
  --lt tools/visual_compare/reference/ships/lt_ship_fighter_rear.jpg \
  --ew tools/visual_compare/eternalwar/fighter/ew_fighter_s42_clay_three_quarter_front.png \
  --out tools/visual_compare/out/ships/cmp_fighter_clay

python3 tools/visual_compare/ship_compare.py \
  --lt tools/visual_compare/reference/ships/lt_ship_fighter_rear.jpg \
  --ew tools/visual_compare/eternalwar/fighter/ew_fighter_s42_lit_three_quarter_front.png \
  --out tools/visual_compare/out/ships/cmp_fighter_lit
```

Outputs: `*_sidebyside.png`, `*_silhouette.png` (raw + normalized IoU / edge overlap), `*_luminance.png`, `*_report.json`.

## Loop

1. Capture EW fighter gallery
2. Compare silhouette IoU against LT fighter reference
3. If silhouette poor → fix GeometryKernel / stations (not shaders)
4. If clay wrong → fix geometry; if lit wrong → materials/lighting
5. Repeat
