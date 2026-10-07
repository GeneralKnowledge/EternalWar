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
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def load_rgb(path: str, size: tuple[int, int] | None = None) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    if size is not None:
        im = im.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def luma(a: np.ndarray) -> np.ndarray:
    return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]


def structure_stats(a: np.ndarray) -> dict:
    """Image-space proxies for volumetric structure vs flat fog sheets.

    Higher flatness_score (0–1) ⇒ smoother / sheet-like.
    Volumetric LT gas tends to have: mid-frequency edges, dark cavities inside
    bright regions, and anisotropic filaments.
    """
    y = luma(a)
    h, w = y.shape
    gy, gx = np.gradient(y)
    edge = np.hypot(gx, gy)
    e99 = float(np.percentile(edge, 99)) + 1e-6
    edge_n = edge / e99

    # Multi-scale local contrast (block std)
    def block_std(arr: np.ndarray, bs: int) -> float:
        hh = (arr.shape[0] // bs) * bs
        ww = (arr.shape[1] // bs) * bs
        if hh < bs or ww < bs:
            return float(arr.std())
        blocks = arr[:hh, :ww].reshape(hh // bs, bs, ww // bs, bs)
        return float(blocks.std(axis=(1, 3)).mean())

    c8 = block_std(y, 8)
    c32 = block_std(y, 32)
    c64 = block_std(y, 64)
    # Flat fog: coarse contrast ≈ fine contrast (soft blob). Volume: coarse >> mid structure.
    contrast_ratio = c32 / max(c8, 1e-6)

    # Dark cavities inside bright lobes
    bright = y > np.percentile(y, 60)
    if bright.any():
        cavity_frac = float(((y < np.percentile(y, 35)) & bright).mean() / max(bright.mean(), 1e-6))
        # Actually cavities are dark pixels *near* bright — use morphological proximity via dilation
        bright_img = Image.fromarray((bright.astype(np.uint8) * 255), mode="L").filter(ImageFilter.MaxFilter(15))
        near_bright = np.asarray(bright_img) > 0
        cavity_frac = float(((y < 0.12) & near_bright).mean())
    else:
        cavity_frac = 0.0

    # Gradient anisotropy (filament preference): |cos 2θ| of edge orientation
    ang = np.arctan2(gy, gx)
    weight = edge_n
    aniso = float(np.abs(np.average(np.cos(2.0 * ang), weights=weight + 1e-6)))

    mid_edge = float(((edge_n > 0.12) & (edge_n < 0.7)).mean())
    soft_edge = float((edge_n < 0.08).mean())

    # Flatness: soft edges, low cavity, contrast_ratio near 1, low mid-edge
    flat = 0.0
    flat += 0.35 * min(1.0, soft_edge / 0.75)
    flat += 0.25 * (1.0 - min(1.0, cavity_frac / 0.08))
    flat += 0.20 * (1.0 - min(1.0, abs(contrast_ratio - 1.4) / 1.4))
    flat += 0.20 * (1.0 - min(1.0, mid_edge / 0.25))
    flat = float(np.clip(flat, 0.0, 1.0))

    return {
        "flatness_score": flat,
        "block_std_8": c8,
        "block_std_32": c32,
        "block_std_64": c64,
        "contrast_ratio_32_8": float(contrast_ratio),
        "cavity_near_bright": cavity_frac,
        "mid_edge_frac": mid_edge,
        "soft_edge_frac": soft_edge,
        "gradient_anisotropy": aniso,
        "edge_p90": float(np.percentile(edge, 90)),
    }


def stats(a: np.ndarray) -> dict:
    y = luma(a)
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    s = {
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
    s.update(structure_stats(a))
    return s


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
        ("Flatness (structure)", abs(lt_s["flatness_score"] - ew_s["flatness_score"]), "structure"),
        ("Cavity / dark lanes", abs(lt_s["cavity_near_bright"] - ew_s["cavity_near_bright"]), "structure"),
        ("Mid-frequency edges", abs(lt_s["mid_edge_frac"] - ew_s["mid_edge_frac"]), "structure"),
    ]
    diffs.sort(key=lambda x: -x[1])
    # Crude similarity: 100 - weighted penalty
    score = 100.0
    score -= min(30.0, abs(lt_s["dark_frac"] - ew_s["dark_frac"]) * 80.0)
    score -= min(20.0, abs(lt_s["mean_Y"] - ew_s["mean_Y"]) * 60.0)
    score -= min(15.0, abs(lt_s["bright_frac"] - ew_s["bright_frac"]) * 70.0)
    score -= min(12.0, abs(lt_s["mean_sat"] - ew_s["mean_sat"]) * 40.0)
    # Penalise EW being flatter than LT
    if ew_s["flatness_score"] > lt_s["flatness_score"]:
        score -= min(18.0, (ew_s["flatness_score"] - lt_s["flatness_score"]) * 40.0)
    score -= min(10.0, abs(lt_s["cavity_near_bright"] - ew_s["cavity_near_bright"]) * 80.0)
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
        "flatness": {
            "lt": lt_s["flatness_score"],
            "ew": ew_s["flatness_score"],
            "ew_flatter_than_lt": ew_s["flatness_score"] > lt_s["flatness_score"] + 0.05,
            "cavity_lt": lt_s["cavity_near_bright"],
            "cavity_ew": ew_s["cavity_near_bright"],
            "mid_edge_lt": lt_s["mid_edge_frac"],
            "mid_edge_ew": ew_s["mid_edge_frac"],
        },
    }
    Path(f"{out}_report.json").write_text(json.dumps(report, indent=2))
    print(f"score={score:.1f}/100")
    print(
        f"  flatness LT={lt_s['flatness_score']:.3f}  EW={ew_s['flatness_score']:.3f}"
        f"  cavity LT={lt_s['cavity_near_bright']:.3f} EW={ew_s['cavity_near_bright']:.3f}"
        f"  mid_edge LT={lt_s['mid_edge_frac']:.3f} EW={ew_s['mid_edge_frac']:.3f}"
    )
    if report["flatness"]["ew_flatter_than_lt"]:
        print("  ⚠ EW reads FLATTER than LT (structure deficit)")
    for i, r in enumerate(ranks[:6], 1):
        bar = "█" * max(1, int(min(20, r["delta"] * 40)))
        print(f"  {i}. {r['name']:<32s} {bar}  Δ={r['delta']:.4f}")


if __name__ == "__main__":
    main()
