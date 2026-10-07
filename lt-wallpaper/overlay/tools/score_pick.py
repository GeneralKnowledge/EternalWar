#!/usr/bin/env python3
"""Pick the best LT wallpaper plate from a directory of candidate PNGs.

Scores for silhouette presence (center contrast / chroma) and penalizes
blown highlights and near-empty / near-white frames.
"""

from __future__ import annotations

import argparse
import shutil
import struct
import zlib
from pathlib import Path


def _read_png_rgba(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"not a PNG: {path}"
    pos = 8
    width = height = None
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
            if bit_depth != 8 or color_type not in (2, 6):
                raise ValueError(f"unsupported PNG format in {path}")
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    assert width and height
    raw = zlib.decompress(bytes(idat))
    bpp = 4 if color_type == 6 else 3
    stride = width * bpp
    rows = []
    i = 0
    prev = bytearray(stride)
    for _y in range(height):
        filt = raw[i]
        i += 1
        row = bytearray(raw[i : i + stride])
        i += stride
        if filt == 0:
            pass
        elif filt == 1:  # Sub
            for x in range(bpp, stride):
                row[x] = (row[x] + row[x - bpp]) & 255
        elif filt == 2:  # Up
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif filt == 3:  # Average
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif filt == 4:  # Paeth
            for x in range(stride):
                a = row[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                row[x] = (row[x] + pr) & 255
        else:
            raise ValueError(f"unsupported filter {filt} in {path}")
        prev = row
        if bpp == 3:
            rgba = bytearray(width * 4)
            for x in range(width):
                rgba[x * 4] = row[x * 3]
                rgba[x * 4 + 1] = row[x * 3 + 1]
                rgba[x * 4 + 2] = row[x * 3 + 2]
                rgba[x * 4 + 3] = 255
            rows.append(bytes(rgba))
        else:
            rows.append(bytes(row))
    return width, height, b"".join(rows)


def score_png(path: Path) -> dict[str, float]:
    w, h, rgba = _read_png_rgba(path)
    n = w * h
    # Sample every 2nd pixel for speed on 1080p+
    step = 2 if n > 400_000 else 1
    sat = 0
    mean = 0.0
    chroma = 0.0
    count = 0
    # Center crop stats
    x0, x1 = int(w * 0.25), int(w * 0.75)
    y0, y1 = int(h * 0.2), int(h * 0.8)
    c_vals: list[float] = []
    for y in range(0, h, step):
        row = y * w * 4
        for x in range(0, w, step):
            i = row + x * 4
            r, g, b = rgba[i], rgba[i + 1], rgba[i + 2]
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            mean += lum
            chroma += max(r, g, b) - min(r, g, b)
            if r > 245 and g > 245 and b > 245:
                sat += 1
            count += 1
            if x0 <= x < x1 and y0 <= y < y1:
                c_vals.append(lum)
    mean /= max(count, 1)
    chroma /= max(count, 1)
    sat_pct = 100.0 * sat / max(count, 1)
    if c_vals:
        c_mean = sum(c_vals) / len(c_vals)
        c_var = sum((v - c_mean) ** 2 for v in c_vals) / len(c_vals)
        center_std = c_var**0.5
    else:
        center_std = 0.0

    # Prefer structure in the subject zone; punish blowouts and mud.
    score = (
        center_std * 2.2
        + chroma * 0.35
        - sat_pct * 2.5
        - abs(mean - 105.0) * 0.12
    )
    if sat_pct > 28:
        score -= (sat_pct - 28) * 3.0
    if mean < 20 or mean > 220:
        score -= 40
    return {
        "score": score,
        "mean": mean,
        "chroma": chroma,
        "satPct": sat_pct,
        "centerStd": center_std,
    }


def pick_best(candidates: list[Path]) -> tuple[Path, dict[str, float]]:
    best_path = candidates[0]
    best_stats = score_png(best_path)
    for path in candidates[1:]:
        stats = score_png(path)
        if stats["score"] > best_stats["score"]:
            best_path, best_stats = path, stats
    return best_path, best_stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", type=Path, required=True, help="Directory of candidate PNGs")
    ap.add_argument("--out", type=Path, required=True, help="Destination for the winner")
    ap.add_argument(
        "--cleanup",
        action="store_true",
        help="Delete losing candidates under --dir (staging dirs only)",
    )
    args = ap.parse_args()

    pngs = sorted(args.dir.glob("*.png"))
    if not pngs:
        raise SystemExit(f"no PNGs in {args.dir}")

    winner, stats = pick_best(pngs)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(winner, args.out)
    print(
        f"score_pick: chose {winner.name} → {args.out} "
        f"(score={stats['score']:.1f} mean={stats['mean']:.0f} "
        f"sat={stats['satPct']:.1f}% centerStd={stats['centerStd']:.1f})"
    )
    if args.cleanup:
        out_res = args.out.resolve()
        for p in pngs:
            if p.resolve() != out_res:
                p.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
