#!/usr/bin/env python3
"""Fill the gallery with a batch of native wallpaper plates.

Runs server-side (imports gallery bake helpers) so it skips the per-IP rate
limit. Prefer the warm daemon: keep lt-wallpaperd running and avoid UI
generates while this script is active.

Examples (on the VPS install):

  cd /opt/lt-wallpaper/gallery
  sudo -u ltwallpaper bash -lc '
    set -a; source .env; set +a
    python3 scripts/fill-gallery.py -n 20
  '

  # Mix only light presets (default on small profile):
  python3 scripts/fill-gallery.py -n 20 --mix safe

  # All categories (heavy on 1 GiB — not recommended):
  python3 scripts/fill-gallery.py -n 12 --mix all --continue-on-error
"""

from __future__ import annotations

import argparse
import os
import random
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load_dotenv(path: Path) -> None:
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip("'").strip('"')
        if key and key not in os.environ:
            os.environ[key] = val


# Light presets that finish in a few minutes on ≈1 GiB + software GL.
SAFE_CATEGORIES = (
    "sky",
    "solo",
    "fleet",
    "ship",
    "asteroids",
    "skirmish",
    "capital",
    "station",
    "mining",
    "vista",
)

# Heavier / slower on small hosts (planet SDF, many ships, explosions).
HEAVY_CATEGORIES = (
    "system",
    "armada",
    "aftermath",
    "planet",
    "belt",
)


def _wait_daemon_idle(spool: Path, timeout: float) -> None:
    ready = spool / "daemon.ready"
    req = spool / "job.req"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if ready.is_file() and not req.is_file():
            return
        time.sleep(1.0)
    raise TimeoutError(
        f"daemon not idle after {int(timeout)}s "
        f"(ready={ready.is_file()} req={req.is_file()})"
    )


def _resolve_mix(name: str, available: list[str]) -> list[str]:
    name = name.strip().lower()
    if name == "safe":
        cats = [c for c in SAFE_CATEGORIES if c in available]
    elif name == "all":
        cats = list(available)
    elif name == "heavy":
        cats = [c for c in HEAVY_CATEGORIES if c in available]
    else:
        cats = [c.strip() for c in name.split(",") if c.strip()]
        unknown = [c for c in cats if c not in available]
        if unknown:
            raise SystemExit(
                f"unknown categories: {unknown}; choose from {available}"
            )
    if not cats:
        raise SystemExit("no categories left after mix filter")
    return cats


def main() -> int:
    _load_dotenv(ROOT / ".env")
    sys.path.insert(0, str(ROOT))
    import server  # noqa: WPS433 — after env load

    parser = argparse.ArgumentParser(
        description="Bake N wallpapers into the gallery (server-side)."
    )
    parser.add_argument(
        "-n",
        "--count",
        type=int,
        default=20,
        help="number of plates to bake (default 20)",
    )
    parser.add_argument(
        "--mix",
        default="safe",
        help="safe | all | heavy | comma-separated category ids (default: safe)",
    )
    parser.add_argument(
        "--size",
        default=None,
        help="size key from profile (default: profile default)",
    )
    parser.add_argument(
        "--quality",
        default=None,
        help="quality key from profile (default: profile default)",
    )
    parser.add_argument(
        "--best",
        type=int,
        default=1,
        help="best-of N candidates per plate (default 1)",
    )
    parser.add_argument(
        "--seed",
        default=None,
        help="base seed; plate i uses seed+i (default: random each plate)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=2.0,
        help="seconds to pause between plates (default 2)",
    )
    parser.add_argument(
        "--daemon-wait",
        type=float,
        default=900.0,
        help="max seconds to wait for warm daemon idle before each bake",
    )
    parser.add_argument(
        "--continue-on-error",
        action="store_true",
        help="keep going after a failed plate",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the plan only",
    )
    args = parser.parse_args()

    if args.count < 1:
        raise SystemExit("--count must be ≥ 1")

    profile = server.resolve_profile()
    sizes = server.active_sizes()
    quality = server.active_quality()
    size_key = args.size or server.PROFILES[profile]["defaultSize"]
    quality_key = args.quality or server.PROFILES[profile]["defaultQuality"]
    if size_key not in sizes:
        raise SystemExit(f"size {size_key!r} not in profile {profile}: {list(sizes)}")
    if quality_key not in quality:
        raise SystemExit(
            f"quality {quality_key!r} not in profile {profile}: {list(quality)}"
        )
    width, height = sizes[size_key]
    nebula_res = quality[quality_key]
    cats = _resolve_mix(args.mix, list(server.CATEGORIES))

    spool = Path(
        os.environ.get("LT_WALLPAPER_SPOOL", str(server.DAEMON_SPOOL))
    ).resolve()

    print(
        f"fill-gallery: n={args.count} mix={args.mix} "
        f"profile={profile} {size_key} {quality_key} "
        f"(nebulaRes={nebula_res}) best={args.best}"
    )
    print(f"  categories: {', '.join(cats)}")
    print(f"  data: {server.DATA}")
    print(f"  spool: {spool}")

    plan: list[tuple[str, str]] = []
    base_seed = int(args.seed) if args.seed is not None else None
    for i in range(args.count):
        category = cats[i % len(cats)]
        if base_seed is not None:
            seed = str(base_seed + i)
        else:
            seed = str(random.SystemRandom().getrandbits(64))
        plan.append((category, seed))

    if args.dry_run:
        for i, (category, seed) in enumerate(plan, 1):
            print(f"  [{i}/{args.count}] {category} seed={seed}")
        return 0

    ok = 0
    failed = 0
    t0 = time.monotonic()
    for i, (category, seed) in enumerate(plan, 1):
        label = server.CATEGORIES[category]["label"]
        print(
            f"[{i}/{args.count}] {label} ({category}) seed={seed[:18]}…",
            flush=True,
        )
        try:
            try:
                _wait_daemon_idle(spool, args.daemon_wait)
            except TimeoutError as exc:
                print(f"  warn: {exc} — falling through (may cold-bake)", flush=True)
            started = time.monotonic()
            item = server.run_bake(
                category=category,
                seed=seed,
                width=width,
                height=height,
                nebula_res=nebula_res,
                count=1,
                best=max(1, args.best),
            )
            elapsed = time.monotonic() - started
            if isinstance(item, list):
                item = item[0]
            ok += 1
            print(
                f"  ok id={item['id']} file={item['file']} ({elapsed:.0f}s)",
                flush=True,
            )
        except Exception as exc:  # noqa: BLE001 — batch runner
            failed += 1
            print(f"  FAIL: {exc}", flush=True)
            if not args.continue_on_error:
                print(
                    f"stopped after {ok} ok / {failed} failed "
                    f"({time.monotonic() - t0:.0f}s total)"
                )
                return 1
        if i < args.count and args.delay > 0:
            time.sleep(args.delay)

    total = time.monotonic() - t0
    print(f"done: {ok} ok, {failed} failed, {total:.0f}s total")
    return 0 if failed == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
