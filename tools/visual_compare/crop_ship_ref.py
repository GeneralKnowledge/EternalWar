#!/usr/bin/env python3
"""Crop a fighter-only plate from an LT full-scene screenshot.

Uses a sliding-window score (edge × contrast × bright/dark mix × lower-center prior)
then letterboxes onto a studio plate matching EW gallery framing.

Usage:
  python3 tools/visual_compare/crop_ship_ref.py \\
      --src tools/visual_compare/reference/ships/lt_ship_fighter_engines.jpg \\
      --out tools/visual_compare/reference/ships/cropped/lt_fighter_engines_crop.png
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def luma(a: np.ndarray) -> np.ndarray:
    return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]


def best_window(y: np.ndarray) -> tuple[int, int, int, int]:
    h, w = y.shape
    gy, gx = np.gradient(y)
    edge = np.hypot(gx, gy)
    best: tuple | None = None
    for ww in (int(w * 0.38), int(w * 0.45), int(w * 0.52)):
        for hh in (int(h * 0.38), int(h * 0.45), int(h * 0.55)):
            step = max(6, min(ww, hh) // 10)
            for yi in range(int(h * 0.2), h - hh, step):
                for xi in range(int(w * 0.08), w - ww, step):
                    pe = edge[yi : yi + hh, xi : xi + ww]
                    py = y[yi : yi + hh, xi : xi + ww]
                    bright = float((py > 0.5).mean())
                    dark = float((py < 0.18).mean())
                    sc = float(pe.mean()) * (0.15 + float(py.std())) * (0.2 + min(bright, 0.25)) * (
                        0.2 + min(dark, 0.35)
                    )
                    sc *= float(
                        np.exp(
                            -(((xi + ww / 2) - w * 0.5) / (w * 0.45)) ** 2
                            - (((yi + hh / 2) - h * 0.62) / (h * 0.38)) ** 2
                        )
                    )
                    if best is None or sc > best[0]:
                        best = (sc, xi, yi, xi + ww, yi + hh)
    assert best is not None
    return int(best[1]), int(best[2]), int(best[3]), int(best[4])


def crop_to_studio(src: str, out: str, size: tuple[int, int] = (960, 540), bg=(10, 12, 16)) -> dict:
    im = Image.open(src).convert("RGB")
    a = np.asarray(im, dtype=np.float32) / 255.0
    y = luma(a)
    x0, y0, x1, y1 = best_window(y)
    pad = 40
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(im.size[0] - 1, x1 + pad)
    y1 = min(im.size[1] - 1, y1 + pad)
    crop = im.crop((x0, y0, x1, y1))
    cw, ch = crop.size
    tw, th = size
    scale = min(tw / cw, th / ch) * 0.88
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    canvas = Image.new("RGB", size, bg)
    canvas.paste(crop.resize((nw, nh), Image.Resampling.LANCZOS), ((tw - nw) // 2, (th - nh) // 2))
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    dbg = im.copy()
    d = ImageDraw.Draw(dbg)
    d.rectangle([x0, y0, x1, y1], outline=(0, 255, 80), width=4)
    dbg_path = str(Path(out).with_name(Path(out).stem + "_bbox.jpg"))
    dbg.save(dbg_path, quality=88)
    meta = {
        "src": src,
        "out": out,
        "bbox": [x0, y0, x1, y1],
        "bbox_frac": [(x1 - x0 + 1) / im.size[0], (y1 - y0 + 1) / im.size[1]],
        "debug_bbox": dbg_path,
    }
    print(f"crop {Path(src).name} → {out}  bbox_frac={meta['bbox_frac']}")
    return meta


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=960)
    ap.add_argument("--height", type=int, default=540)
    args = ap.parse_args()
    crop_to_studio(args.src, args.out, (args.width, args.height))


if __name__ == "__main__":
    main()
