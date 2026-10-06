# Visual compare — Limit Theory vs EternalWar

## Layout

```
reference/     Real LT screenshots (authority)
eternalwar/    Deterministic EW captures from scenes/lt_compare.tscn
out/           Side-by-side, difference, luminance, JSON scores
compare.py     Comparison tool
```

## Capture EternalWar

```bash
godot --path . --rendering-driver opengl3 --resolution 1280x720 \
  res://scenes/lt_compare.tscn -- --capture=/workspace/tools/visual_compare/eternalwar
```

Or interactive: open `lt_compare.tscn`, press **A** to capture all, **C** for current.

## Compare

```bash
python3 tools/visual_compare/compare.py \
  --lt tools/visual_compare/reference/lt_nebula_ship.jpg \
  --ew tools/visual_compare/eternalwar/ew_nebula.png \
  --out tools/visual_compare/out/cmp_nebula
```

Outputs: `*_sidebyside.png`, `*_diff.png`, `*_luma.png`, `*_report.json` with ranked mismatches and a crude score.

## Loop

1. Capture EW
2. Compare against the matching LT reference
3. Fix the largest ranked mismatch
4. Repeat
