#!/usr/bin/env python3
"""Compose a nebula mood contact sheet + LT reference row.

Usage:
  python3 tools/visual_compare/make_nebula_sheet.py \\
      --ew-dir tools/visual_compare/eternalwar/nebula_sheet \\
      --out tools/visual_compare/out/nebula_mood_sheet.png
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

MOODS = [
    "amber_gold",
    "cyan_teal",
    "indigo_violet",
    "magenta_rose",
    "crimson",
    "cold_white",
]

LT_REFS = [
    ("lt_nebula_cockpit.jpg", "LT cockpit (warm)"),
    ("lt_nebula_ship.jpg", "LT ship (magenta)"),
    ("lt_nebula_planet.jpg", "LT planet (cool)"),
]


def load(path: Path, size: tuple[int, int]) -> Image.Image:
    return Image.open(path).convert("RGB").resize(size, Image.Resampling.LANCZOS)


def gas_stats(im: Image.Image) -> dict:
    a = np.asarray(im, dtype=np.float32) / 255.0
    y = 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]
    m = y > 0.12
    rgb = a[m].mean(0) if m.any() else a.mean((0, 1))
    return {
        "gas_rgb": [float(x) for x in rgb],
        "B-R": float(rgb[2] - rgb[0]),
        "R-G": float(rgb[0] - rgb[1]),
        "mean_Y": float(y.mean()),
    }


def label_font(size: int = 18):
    for name in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ):
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ew-dir", default="tools/visual_compare/eternalwar/nebula_sheet")
    ap.add_argument("--lt-dir", default="tools/visual_compare/reference")
    ap.add_argument("--out", default="tools/visual_compare/out/nebula_mood_sheet.png")
    ap.add_argument("--cell-w", type=int, default=420)
    ap.add_argument("--cell-h", type=int, default=236)
    args = ap.parse_args()

    ew_dir = Path(args.ew_dir)
    lt_dir = Path(args.lt_dir)
    cell = (args.cell_w, args.cell_h)
    pad = 10
    label_h = 28
    cols = 3
    rows_ew = (len(MOODS) + cols - 1) // cols
    rows_lt = 1
    rows = rows_ew + rows_lt + 1  # + header spacer row conceptually
    W = cols * cell[0] + (cols + 1) * pad
    H = (rows_ew + rows_lt) * (cell[1] + label_h) + (rows_ew + rows_lt + 1) * pad + 36

    canvas = Image.new("RGB", (W, H), (8, 10, 14))
    draw = ImageDraw.Draw(canvas)
    font = label_font(16)
    font_h = label_font(20)
    draw.text((pad, 8), "EternalWar nebula moods  vs  Limit Theory refs", fill=(230, 235, 245), font=font_h)

    report: dict = {"moods": {}, "lt": {}}
    y0 = 40
    for i, mood in enumerate(MOODS):
        r, c = divmod(i, cols)
        x = pad + c * (cell[0] + pad)
        y = y0 + r * (cell[1] + label_h + pad)
        path = ew_dir / f"ew_nebula_{mood}.png"
        if not path.exists():
            draw.rectangle([x, y, x + cell[0], y + cell[1]], fill=(30, 30, 40))
            draw.text((x + 8, y + 8), f"MISSING {mood}", fill=(255, 80, 80), font=font)
            continue
        im = load(path, cell)
        canvas.paste(im, (x, y))
        st = gas_stats(im)
        report["moods"][mood] = st
        br = st["B-R"]
        tag = "cool/blue" if br > 0.08 else ("warm" if br < -0.05 else "balanced")
        draw.text(
            (x, y + cell[1] + 4),
            f"{mood}  B-R={br:+.2f} ({tag})",
            fill=(200, 210, 220),
            font=font,
        )

    y_lt = y0 + rows_ew * (cell[1] + label_h + pad) + 8
    draw.text((pad, y_lt - 22), "Limit Theory references", fill=(230, 200, 160), font=font_h)
    for i, (name, title) in enumerate(LT_REFS):
        x = pad + i * (cell[0] + pad)
        path = lt_dir / name
        if not path.exists():
            continue
        im = load(path, cell)
        canvas.paste(im, (x, y_lt))
        st = gas_stats(im)
        report["lt"][name] = st
        draw.text(
            (x, y_lt + cell[1] + 4),
            f"{title}  B-R={st['B-R']:+.2f}",
            fill=(220, 200, 170),
            font=font,
        )

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    meta = out.with_name(out.stem + "_report.json")
    meta.write_text(json.dumps(report, indent=2))
    print(f"wrote {out}")
    print(f"wrote {meta}")
    cool = sum(1 for m, s in report["moods"].items() if s["B-R"] > 0.08)
    warm = sum(1 for m, s in report["moods"].items() if s["B-R"] < -0.05)
    print(f"moods: {len(report['moods'])}  cool/blue={cool}  warm={warm}")


if __name__ == "__main__":
    main()
