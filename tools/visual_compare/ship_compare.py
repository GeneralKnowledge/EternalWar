#!/usr/bin/env python3
"""Ship silhouette / mass comparison for LT vs EternalWar.

Usage:
  python3 tools/visual_compare/ship_compare.py \\
      --lt tools/visual_compare/reference/ships/lt_ship_fighter_rear.jpg \\
      --ew tools/visual_compare/eternalwar/ships/ew_ship_patrol_s42_three_quarter.png \\
      --out tools/visual_compare/out/ships/cmp_patrol
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps


def load_rgb(path: str, size: tuple[int, int] | None = None) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    if size is not None:
        im = im.resize(size, Image.Resampling.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def luma(a: np.ndarray) -> np.ndarray:
    return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]


def ship_mask(a: np.ndarray) -> np.ndarray:
    """Foreground ship mask for either nebula (dark ship) or studio (lit ship) shots."""
    y = luma(a)
    h, w = y.shape
    # Corner mean ≈ background
    c = 0.08
    corners = np.concatenate(
        [
            y[: int(h * c), : int(w * c)].ravel(),
            y[: int(h * c), -int(w * c) :].ravel(),
            y[-int(h * c) :, : int(w * c)].ravel(),
            y[-int(h * c) :, -int(w * c) :].ravel(),
        ]
    )
    bg = float(np.median(corners))
    gy, gx = np.gradient(y)
    edge = np.hypot(gx, gy)
    edge_m = edge > np.percentile(edge, 88)
    if bg > 0.35:
        # Bright nebula / white silhouette board → ship is darker
        m = (y < bg * 0.55) | ((y < bg * 0.85) & edge_m)
    else:
        # Dark studio → ship is the lit mass
        m = (y > bg + 0.08) | edge_m
    m = m & (y < 0.92)  # drop blown engine cores from mass
    return m.astype(np.float32)


def bbox_frac(mask: np.ndarray) -> tuple[float, float, float, float]:
    ys, xs = np.where(mask > 0.5)
    if len(xs) == 0:
        return 0.0, 0.0, 0.0, 0.0
    h, w = mask.shape
    return (
        float(xs.min()) / w,
        float(ys.min()) / h,
        float(xs.max() - xs.min() + 1) / w,
        float(ys.max() - ys.min() + 1) / h,
    )


def aspect(mask: np.ndarray) -> float:
    _, _, bw, bh = bbox_frac(mask)
    if bh < 1e-6:
        return 0.0
    return bw / bh


def stats(a: np.ndarray) -> dict:
    y = luma(a)
    m = ship_mask(a)
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    bx, by, bw, bh = bbox_frac(m)
    return {
        "mean_Y": float(y.mean()),
        "dark_frac": float((y < 0.06).mean()),
        "mean_sat": float(sat.mean()),
        "mask_frac": float(m.mean()),
        "aspect": float(aspect(m)),
        "bbox": [bx, by, bw, bh],
        "mean_rgb": [float(x) for x in a.mean(axis=(0, 1))],
        "emissive_frac": float((y > 0.7).mean()),
    }


def score(lt_s: dict, ew_s: dict) -> tuple[float, list]:
    """Rank mismatches. Absolute bbox size is down-weighted when LT is a full scene
    (nebula/combat) vs EW studio gallery — compare aspect / colour / emissive first."""
    mismatches = []

    def add(name: str, delta: float, cat: str, weight: float = 1.0) -> None:
        mismatches.append(
            {"name": name, "delta": float(delta), "weighted": float(delta) * weight, "category": cat}
        )

    env_shot = lt_s["mask_frac"] > 0.25 or lt_s["mean_Y"] > 0.12
    cov_w = 0.25 if env_shot else 1.0
    box_w = 0.15 if env_shot else 0.8

    add("Silhouette coverage", abs(lt_s["mask_frac"] - ew_s["mask_frac"]), "silhouette", cov_w)
    add("Aspect ratio", min(abs(lt_s["aspect"] - ew_s["aspect"]), 2.0) * 0.35, "proportion", 1.2)
    add("BBox width", abs(lt_s["bbox"][2] - ew_s["bbox"][2]), "proportion", box_w)
    add("BBox height", abs(lt_s["bbox"][3] - ew_s["bbox"][3]), "proportion", box_w)
    add(
        "Colour balance",
        float(np.linalg.norm(np.array(lt_s["mean_rgb"]) - np.array(ew_s["mean_rgb"]))),
        "colour",
        0.9,
    )
    add("Saturation", abs(lt_s["mean_sat"] - ew_s["mean_sat"]), "colour", 0.8)
    add("Emissive / engine", abs(lt_s["emissive_frac"] - ew_s["emissive_frac"]), "engine", 1.0)
    add("Mean luminance", abs(lt_s["mean_Y"] - ew_s["mean_Y"]), "lighting", 0.5 if env_shot else 0.9)

    mismatches.sort(key=lambda d: -d["weighted"])
    pen = sum(min(d["weighted"], 0.45) for d in mismatches[:5])
    sc = max(0.0, 100.0 - pen * 70.0)
    return sc, mismatches


def side_by_side(lt: np.ndarray, ew: np.ndarray, title_lt: str, title_ew: str, score_v: float) -> Image.Image:
    h, w, _ = lt.shape
    canvas = Image.new("RGB", (w * 2 + 24, h + 40), (18, 18, 22))
    canvas.paste(Image.fromarray((lt * 255).astype(np.uint8)), (8, 32))
    canvas.paste(Image.fromarray((ew * 255).astype(np.uint8)), (w + 16, 32))
    d = ImageDraw.Draw(canvas)
    d.text((8, 8), f"Limit Theory | {title_lt}", fill=(230, 230, 235))
    d.text((w + 16, 8), f"EternalWar | {title_ew} | score {score_v:.0f}/100", fill=(230, 230, 235))
    return canvas


def silhouette_panel(lt: np.ndarray, ew: np.ndarray) -> Image.Image:
    ml = ship_mask(lt)
    me = ship_mask(ew)
    h, w = ml.shape
    panel = np.zeros((h, w * 3, 3), dtype=np.float32)
    panel[:, :w, :] = np.stack([ml, ml, ml], axis=2)
    panel[:, w : w * 2, :] = np.stack([me, me, me], axis=2)
    diff = np.abs(ml - me)
    panel[:, w * 2 :, 0] = diff
    panel[:, w * 2 :, 1] = diff * 0.3
    panel[:, w * 2 :, 2] = diff * 0.3
    im = Image.fromarray((panel * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    d.text((8, 8), "LT mask", fill=(255, 255, 0))
    d.text((w + 8, 8), "EW mask", fill=(255, 255, 0))
    d.text((w * 2 + 8, 8), "Diff", fill=(255, 255, 0))
    return im


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lt", required=True)
    ap.add_argument("--ew", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    lt = load_rgb(args.lt, (640, 360))
    ew = load_rgb(args.ew, (640, 360))
    lt_s = stats(lt)
    ew_s = stats(ew)
    sc, ranked = score(lt_s, ew_s)

    side_by_side(lt, ew, Path(args.lt).name, Path(args.ew).name, sc).save(f"{args.out}_sidebyside.png")
    silhouette_panel(lt, ew).save(f"{args.out}_silhouette.png")
    report = {
        "lt": args.lt,
        "ew": args.ew,
        "score": sc,
        "lt_stats": lt_s,
        "ew_stats": ew_s,
        "ranked_mismatches": ranked,
    }
    Path(f"{args.out}_report.json").write_text(json.dumps(report, indent=2))
    print(f"score={sc:.1f}/100")
    for i, m in enumerate(ranked[:6], 1):
        bar = "█" * max(1, int(m["delta"] * 40))
        print(f"  {i}. {m['name']:<22} {bar}  Δ={m['delta']:.4f}")


if __name__ == "__main__":
    main()
