#!/usr/bin/env python3
"""Side-by-side / difference / luminance comparison for LT vs EternalWar screenshots.

Usage:
  python3 tools/visual_compare/compare.py \\
      --lt tools/visual_compare/reference/lt_nebula_ship.jpg \\
      --ew tools/visual_compare/eternalwar/ew_nebula_ship.png \\
      --out tools/visual_compare/out/cmp_nebula_ship

Writes:
  *_sidebyside.png  *_diff.png  *_luma.png  *_report.json
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def load_rgb(path: str, size: tuple[int, int] | None = None) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    if size is not None:
        im = im.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def luma(a: np.ndarray) -> np.ndarray:
    return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]


def stats(a: np.ndarray) -> dict:
    y = luma(a)
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    return {
        "mean_Y": float(y.mean()),
        "p10_Y": float(np.percentile(y, 10)),
        "p50_Y": float(np.percentile(y, 50)),
        "p90_Y": float(np.percentile(y, 90)),
        "dark_frac": float((y < 0.06).mean()),
        "bright_frac": float((y > 0.55).mean()),
        "mid_frac": float(((y >= 0.06) & (y <= 0.55)).mean()),
        "mean_sat": float(sat.mean()),
        "mean_rgb": [float(x) for x in a.mean(axis=(0, 1))],
    }


def rank_mismatches(lt_s: dict, ew_s: dict) -> list[dict]:
    diffs = [
        ("Background darkness (dark_frac)", abs(lt_s["dark_frac"] - ew_s["dark_frac"]), "composition/luminance"),
        ("Bright-area coverage", abs(lt_s["bright_frac"] - ew_s["bright_frac"]), "luminance"),
        ("Mean luminance", abs(lt_s["mean_Y"] - ew_s["mean_Y"]), "luminance"),
        ("Highlight level (p90_Y)", abs(lt_s["p90_Y"] - ew_s["p90_Y"]), "luminance"),
        ("Saturation", abs(lt_s["mean_sat"] - ew_s["mean_sat"]), "colour"),
        (
            "Colour balance",
            float(np.linalg.norm(np.array(lt_s["mean_rgb"]) - np.array(ew_s["mean_rgb"]))),
            "colour",
        ),
    ]
    diffs.sort(key=lambda x: -x[1])
    # Crude similarity: 100 - weighted penalty
    score = 100.0
    score -= min(35.0, abs(lt_s["dark_frac"] - ew_s["dark_frac"]) * 80.0)
    score -= min(25.0, abs(lt_s["mean_Y"] - ew_s["mean_Y"]) * 60.0)
    score -= min(20.0, abs(lt_s["bright_frac"] - ew_s["bright_frac"]) * 70.0)
    score -= min(15.0, abs(lt_s["mean_sat"] - ew_s["mean_sat"]) * 40.0)
    return [{"name": n, "delta": d, "category": c} for n, d, c in diffs], max(0.0, min(100.0, score))


def to_img(a: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lt", required=True)
    ap.add_argument("--ew", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=960)
    args = ap.parse_args()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    lt0 = Image.open(args.lt).convert("RGB")
    aspect = lt0.size[1] / max(lt0.size[0], 1)
    w = args.width
    h = max(1, int(w * aspect))
    size = (w, h)

    lt = load_rgb(args.lt, size)
    ew = load_rgb(args.ew, size)
    lt_s = stats(lt)
    ew_s = stats(ew)
    ranks, score = rank_mismatches(lt_s, ew_s)

    # Side-by-side with labels
    pad = 36
    canvas = Image.new("RGB", (w * 2 + 24, h + pad + 8), (12, 12, 14))
    canvas.paste(to_img(lt), (8, pad))
    canvas.paste(to_img(ew), (w + 16, pad))
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 8), f"Limit Theory  |  {os.path.basename(args.lt)}", fill=(230, 230, 240))
    draw.text((w + 20, 8), f"EternalWar  |  {os.path.basename(args.ew)}  |  score {score:.0f}/100", fill=(230, 230, 240))
    canvas.save(f"{out}_sidebyside.png")

    # Absolute difference
    diff = np.abs(lt - ew)
    to_img(np.clip(diff * 2.5, 0, 1)).save(f"{out}_diff.png")

    # Luminance triad
    yl, ye = luma(lt), luma(ew)
    yd = np.abs(yl - ye)
    luma_panel = np.zeros((h, w * 3 + 16, 3), dtype=np.float32)
    for i, ch in enumerate((yl, ye, yd)):
        x0 = i * (w + 8)
        luma_panel[:, x0 : x0 + w, 0] = ch
        luma_panel[:, x0 : x0 + w, 1] = ch
        luma_panel[:, x0 : x0 + w, 2] = ch
    to_img(luma_panel).save(f"{out}_luma.png")

    report = {
        "lt": args.lt,
        "ew": args.ew,
        "score": score,
        "lt_stats": lt_s,
        "ew_stats": ew_s,
        "ranked_mismatches": ranks,
    }
    Path(f"{out}_report.json").write_text(json.dumps(report, indent=2))
    print(f"score={score:.1f}/100")
    for i, r in enumerate(ranks[:5], 1):
        bar = "█" * max(1, int(min(20, r["delta"] * 40)))
        print(f"  {i}. {r['name']:<32s} {bar}  Δ={r['delta']:.4f}")


if __name__ == "__main__":
    main()
