#!/usr/bin/env python3
"""
LT Wallpaper Gallery — thin HTTP UI over the native Wallpaper App.

Generates PNGs via tools/wallpaper.sh (Josh's ltheory). Rate-limited to
one bake per IP per minute. Serves a selectable-category gallery.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import random
import re
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent


def _load_dotenv(path: Path) -> None:
    """Minimal .env loader (no dependency). Does not override existing env."""
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


_load_dotenv(ROOT / ".env")

DATA = Path(os.environ.get("LT_GALLERY_DATA", str(ROOT / "data"))).resolve()
IMAGES = DATA / "images"
MANIFEST_PATH = DATA / "manifest.json"
STATIC = ROOT / "static"

RATE_LIMIT_SEC = int(os.environ.get("LT_GALLERY_RATE_SEC", "60"))
BAKE_TIMEOUT_SEC = int(os.environ.get("LT_GALLERY_BAKE_TIMEOUT", "300"))
MAX_BATCH_COUNT = int(os.environ.get("LT_GALLERY_MAX_BATCH", "8"))
MAX_BEST_COUNT = int(os.environ.get("LT_GALLERY_MAX_BEST", "8"))
DEFAULT_HOST = os.environ.get("LT_GALLERY_HOST", "0.0.0.0")
DEFAULT_PORT = int(os.environ.get("LT_GALLERY_PORT", "8080"))
# auto = use warm daemon when ready, else cold wallpaper.sh
DAEMON_MODE = os.environ.get("LT_WALLPAPER_DAEMON", "auto").lower()
DAEMON_SPOOL = Path(
    os.environ.get(
        "LT_WALLPAPER_SPOOL",
        "/var/lib/lt-wallpaper/spool",
    )
)

CATEGORIES: dict[str, dict[str, str]] = {
    "sky": {
        "preset": "sky",
        "label": "Sky",
        "blurb": "IFS nebula + stars — the void alone",
    },
    "ship": {
        "preset": "ship",
        "label": "Ship",
        "blurb": "Fighter drifting a rock field",
    },
    "solo": {
        "preset": "solo",
        "label": "Solo ship",
        "blurb": "One hull against the nebula",
    },
    "fleet": {
        "preset": "fleet",
        "label": "Fleet",
        "blurb": "V formation — many hulls in frame",
    },
    "skirmish": {
        "preset": "skirmish",
        "label": "Skirmish",
        "blurb": "Two wings facing off — turrets firing",
    },
    "capital": {
        "preset": "capital",
        "label": "Capital",
        "blurb": "ShapeLib capital — the ship that could have been",
    },
    "armada": {
        "preset": "armada",
        "label": "Armada",
        "blurb": "Capital lead with a fighter screen",
    },
    "station": {
        "preset": "station",
        "label": "Station",
        "blurb": "ShapeLib hub and light traffic",
    },
    "system": {
        "preset": "system",
        "label": "System",
        "blurb": "Station, rocks, ships — a living plate",
    },
    "vista": {
        "preset": "vista",
        "label": "Vista",
        "blurb": "LTheory-lite — station, field, escort cloud",
    },
    "mining": {
        "preset": "mining",
        "label": "Mining",
        "blurb": "Ore rocks and posed miners",
    },
    "aftermath": {
        "preset": "aftermath",
        "label": "Aftermath",
        "blurb": "Mid-explosion still after a clash",
    },
    "asteroids": {
        "preset": "asteroids",
        "label": "Asteroids",
        "blurb": "Ore field, camera pulled back",
    },
    "planet": {
        "preset": "planet",
        "label": "Planet",
        "blurb": "Procedural world under the sky",
    },
    "belt": {
        "preset": "belt",
        "label": "Belt",
        "blurb": "Planet with a rock ring",
    },
}

ALL_SIZES = {
    "720p": (1280, 720),
    "1080p": (1920, 1080),
    "1440p": (2560, 1440),
    "ultrawide": (2560, 1080),
}

ALL_QUALITY = {
    "draft": 256,
    "good": 512,
    "high": 1024,
}

# Measured peaks (lt64 + Xvfb) on Linux bake — use to pick a safe profile.
# draft/720p ≈ 510 MiB · good/1080p ≈ 760 MiB · high/1080p ≈ 920 MiB
PROFILES = {
    "small": {  # ~1 GiB RAM / 1 core VPS
        "sizes": ("720p",),
        "quality": ("draft", "good"),
        "defaultSize": "720p",
        "defaultQuality": "draft",
        "note": "Capped for ≈1 GiB hosts. Prefer draft; good/720p is tight.",
    },
    "standard": {
        "sizes": ("720p", "1080p", "ultrawide"),
        "quality": ("draft", "good", "high"),
        "defaultSize": "1080p",
        "defaultQuality": "good",
        "note": "Default. Avoid high+1440p on hosts under 2 GiB.",
    },
    "full": {
        "sizes": tuple(ALL_SIZES),
        "quality": tuple(ALL_QUALITY),
        "defaultSize": "1080p",
        "defaultQuality": "good",
        "note": "All sizes unlocked.",
    },
}

_lock = threading.Lock()
_bake_lock = threading.Lock()
_rate: dict[str, float] = {}  # ip -> last bake monotonic time
_busy = False
_busy_since: float | None = None
_last_error: str | None = None
# Async bake jobs: id -> job dict (survives proxy timeouts on long POSTs)
_jobs: dict[str, dict[str, Any]] = {}
_jobs_lock = threading.Lock()
_JOB_TTL_SEC = 3600


def mem_total_mib() -> int | None:
    try:
        with open("/proc/meminfo", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("MemTotal:"):
                    kb = int(line.split()[1])
                    return kb // 1024
    except OSError:
        return None
    return None


def resolve_profile() -> str:
    forced = os.environ.get("LT_GALLERY_PROFILE", "").strip().lower()
    if forced in PROFILES:
        return forced
    mem = mem_total_mib()
    if mem is not None and mem <= 1536:
        return "small"
    return "standard"


def active_sizes() -> dict[str, tuple[int, int]]:
    keys = PROFILES[resolve_profile()]["sizes"]
    return {k: ALL_SIZES[k] for k in keys}


def active_quality() -> dict[str, int]:
    keys = PROFILES[resolve_profile()]["quality"]
    return {k: ALL_QUALITY[k] for k in keys}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def find_ltheory_root() -> Path:
    env = os.environ.get("LTHEORY_ROOT")
    if env:
        return Path(env).resolve()
    candidates = [
        ROOT.parent / "ltheory",
        Path("/home/ubuntu/ltheory"),
        Path.home() / "ltheory",
    ]
    for c in candidates:
        script = c / "tools" / "wallpaper.sh"
        if script.is_file():
            return c.resolve()
    raise FileNotFoundError(
        "ltheory checkout not found. Set LTHEORY_ROOT or run lt-wallpaper/setup.sh"
    )


def load_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.exists():
        return {"version": 1, "items": []}
    return json.loads(MANIFEST_PATH.read_text())


def save_manifest(manifest: dict[str, Any]) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    IMAGES.mkdir(parents=True, exist_ok=True)
    tmp = MANIFEST_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(manifest, indent=2))
    tmp.replace(MANIFEST_PATH)


def client_ip(handler: SimpleHTTPRequestHandler) -> str:
    forwarded = handler.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return handler.client_address[0]


def rate_status(ip: str) -> dict[str, Any]:
    now = time.monotonic()
    last = _rate.get(ip, 0.0)
    remaining = max(0.0, RATE_LIMIT_SEC - (now - last))
    busy_for = None
    if _busy and _busy_since is not None:
        busy_for = int(max(0.0, now - _busy_since))
    job = _current_job_snapshot()
    return {
        "limitSec": RATE_LIMIT_SEC,
        "retryAfterSec": int(remaining + 0.999) if remaining > 0 else 0,
        "allowed": remaining <= 0 and not _busy,
        "busy": _busy,
        "busyForSec": busy_for,
        "lastError": _last_error,
        "job": job,
        "daemon": daemon_status(),
    }


def _current_job_snapshot() -> dict[str, Any] | None:
    with _jobs_lock:
        running = [j for j in _jobs.values() if j.get("status") in ("queued", "running")]
        if not running:
            return None
        j = max(running, key=lambda x: float(x.get("startedAtMono") or 0))
        return _public_job(j)


def _public_job(job: dict[str, Any]) -> dict[str, Any]:
    now = time.monotonic()
    started = float(job.get("startedAtMono") or now)
    return {
        "id": job.get("id"),
        "status": job.get("status"),
        "phase": job.get("phase"),
        "progress": job.get("progress", 0),
        "message": job.get("message"),
        "error": job.get("error"),
        "logTail": job.get("logTail"),
        "hint": job.get("hint"),
        "category": job.get("category"),
        "preset": job.get("preset"),
        "best": job.get("best"),
        "count": job.get("count"),
        "mode": job.get("mode"),
        "elapsedSec": int(max(0.0, now - started)),
        "item": job.get("item"),
        "items": job.get("items"),
    }


def _set_job(job_id: str, **fields: Any) -> None:
    with _jobs_lock:
        job = _jobs.get(job_id)
        if not job:
            return
        job.update(fields)


def _prune_jobs() -> None:
    now = time.monotonic()
    with _jobs_lock:
        dead = [
            jid
            for jid, j in _jobs.items()
            if now - float(j.get("startedAtMono") or now) > _JOB_TTL_SEC
        ]
        for jid in dead:
            del _jobs[jid]


def _job_hint(error: str) -> str:
    e = error.lower()
    if "namespace" in e or "readwritepaths" in e:
        return (
            "Warm daemon systemd unit is crashing. "
            "Run: sudo mkdir -p /opt/lt-wallpaper/ltheory/wallpaper && "
            "sudo systemctl reset-failed lt-wallpaperd && sudo systemctl restart lt-wallpaperd"
        )
    if "timed out" in e or "timeout" in e:
        return "Bake timed out. Try Solo + draft/720p + Best of 1, or raise LT_GALLERY_BAKE_TIMEOUT."
    if "memory" in e or "killed" in e or "oom" in e:
        return "Likely OOM on a small host. Use draft/720p, Best of 1, avoid Belt/Planet."
    if "not found" in e and "ltheory" in e:
        return "ltheory tree missing under LTHEORY_ROOT — re-run gallery/scripts/install.sh"
    if "daemon not ready" in e:
        return "Warm daemon down; cold fallback should still work. Check: systemctl status lt-wallpaperd"
    if "xvfb" in e or "display" in e:
        return "Install xvfb (sudo apt-get install xvfb) or set DISPLAY."
    return "Check: sudo journalctl -u lt-wallpaper-gallery -u lt-wallpaperd -n 80 --no-pager"


def _run_bake_job(job_id: str, ip: str, params: dict[str, Any]) -> None:
    global _busy, _busy_since, _last_error
    _set_job(
        job_id,
        status="running",
        phase="starting",
        progress=5,
        message="Starting bake…",
    )
    try:
        daemon = daemon_status()
        mode = "warm" if daemon.get("ready") else "cold"
        _set_job(
            job_id,
            mode=mode,
            phase="engine",
            progress=15,
            message=f"Running native engine ({mode})…",
        )
        result = run_bake(**params)
        _rate[ip] = time.monotonic()
        if isinstance(result, list):
            _set_job(
                job_id,
                status="done",
                phase="done",
                progress=100,
                message=f"Saved {len(result)} plates",
                items=result,
                item=result[0] if result else None,
            )
        else:
            _set_job(
                job_id,
                status="done",
                phase="done",
                progress=100,
                message=f"Saved {result.get('label') or 'wallpaper'}",
                item=result,
                items=None,
            )
    except Exception as exc:  # noqa: BLE001
        msg = str(exc).strip() or "bake failed (no details)"
        _last_error = msg[-800:]
        print(f"bake job {job_id} error: {msg}", flush=True)
        _set_job(
            job_id,
            status="error",
            phase="error",
            progress=100,
            message="Generate failed",
            error=msg[-1200:],
            logTail=msg[-1200:],
            hint=_job_hint(msg),
        )
    finally:
        _busy = False
        _busy_since = None


def random_seed() -> str:
    hi = random.randint(10**15, 9 * 10**15)
    lo = random.randint(0, 10**6 - 1)
    return f"{hi}{lo:06d}"


def daemon_status() -> dict[str, Any]:
    spool = Path(os.environ.get("LT_WALLPAPER_SPOOL", str(DAEMON_SPOOL))).resolve()
    ready = (spool / "daemon.ready").is_file() and not (spool / "job.req").is_file()
    return {
        "mode": DAEMON_MODE,
        "spool": str(spool),
        "ready": ready,
        "pidFile": (spool / "daemon.pid").is_file(),
    }


def _ingest_png(
    src: Path,
    *,
    category: str,
    preset: str,
    seed: str,
    width: int,
    height: int,
    nebula_res: int,
    label: str,
) -> dict[str, Any]:
    item_id = uuid.uuid4().hex[:12]
    dest = IMAGES / f"{item_id}.png"
    dest.write_bytes(src.read_bytes())
    return {
        "id": item_id,
        "category": category,
        "preset": preset,
        "seed": seed,
        "width": width,
        "height": height,
        "nebulaRes": nebula_res,
        "file": f"images/{item_id}.png",
        "source": "generated",
        "createdAt": utc_now(),
        "label": label,
    }


def _load_score_pick(ltheory: Path) -> Any:
    """Load tools/score_pick.py from the built ltheory tree (or overlay fallback)."""
    candidates = [
        ltheory / "tools" / "score_pick.py",
        ROOT.parent / "overlay" / "tools" / "score_pick.py",
    ]
    for path in candidates:
        if path.is_file():
            spec = importlib.util.spec_from_file_location("lt_score_pick", path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["lt_score_pick"] = mod
                spec.loader.exec_module(mod)
                return mod
    raise RuntimeError("score_pick.py not found")


def run_bake(
    *,
    category: str,
    seed: str,
    width: int,
    height: int,
    nebula_res: int,
    count: int = 1,
    best: int = 1,
) -> dict[str, Any] | list[dict[str, Any]]:
    """Run one Wallpaper process.

    count>1 keeps all plates. best>1 bakes that many candidates and keeps the
    highest-scoring plate only (still one engine launch).
    """
    global _busy, _busy_since, _last_error
    cat = CATEGORIES[category]
    preset = cat["preset"]
    count = max(1, min(int(count), MAX_BATCH_COUNT))
    best = max(1, min(int(best), MAX_BEST_COUNT))
    keep_best_only = best > 1
    if keep_best_only:
        count = best  # candidates in one warm process
    ltheory = find_ltheory_root()
    script = ltheory / "tools" / "wallpaper.sh"
    daemon = ltheory / "tools" / "wallpaperd.py"
    IMAGES.mkdir(parents=True, exist_ok=True)

    batch_dir: Path | None = None
    out_path: Path | None = None
    bake_args = [
        f"seed={seed}",
        f"preset={preset}",
        f"width={width}",
        f"height={height}",
        f"nebulaRes={nebula_res}",
        "frames=3",
    ]
    if keep_best_only:
        out_path = IMAGES / f"{uuid.uuid4().hex[:12]}.png"
        bake_args.extend([f"best={best}", f"out={out_path}"])
        # After best-of, a single PNG lands at out_path.
        count = 1
        timeout = BAKE_TIMEOUT_SEC + max(0, best - 1) * 45
    elif count > 1:
        batch_dir = IMAGES / f"_batch_{uuid.uuid4().hex[:10]}"
        batch_dir.mkdir(parents=True, exist_ok=True)
        bake_args.extend([f"count={count}", f"outdir={batch_dir}"])
        timeout = BAKE_TIMEOUT_SEC + max(0, count - 1) * 45
    else:
        out_path = IMAGES / f"{uuid.uuid4().hex[:12]}.png"
        bake_args.extend([f"count=1", f"out={out_path}"])
        timeout = BAKE_TIMEOUT_SEC

    use_daemon = DAEMON_MODE in ("1", "on", "true", "yes", "auto")
    if DAEMON_MODE in ("0", "off", "false", "no", "cold"):
        use_daemon = False
    spool = Path(
        os.environ.get("LT_WALLPAPER_SPOOL", str(DAEMON_SPOOL))
    ).resolve()

    with _bake_lock:
        _busy = True
        _busy_since = time.monotonic()
        _last_error = None
        try:
            if use_daemon and daemon.is_file():
                args = [
                    sys.executable,
                    str(daemon),
                    "--spool",
                    str(spool),
                    "bake",
                    "--cold",
                    *bake_args,
                ]
            else:
                args = [str(script), *bake_args]
            proc = subprocess.run(
                args,
                cwd=str(ltheory),
                capture_output=True,
                text=True,
                timeout=timeout,
                env={
                    **os.environ,
                    "FORCE_DISPLAY": os.environ.get("FORCE_DISPLAY", ""),
                    "LT_WALLPAPER_SPOOL": str(spool),
                },
            )
            if proc.returncode != 0:
                detail = (proc.stderr or proc.stdout or "bake failed").strip()
                _last_error = detail[-800:]
                raise RuntimeError(_last_error)
            if count == 1:
                assert out_path is not None
                if not out_path.is_file():
                    detail = (proc.stderr or proc.stdout or "bake failed").strip()
                    _last_error = detail[-800:]
                    raise RuntimeError(_last_error)
            else:
                assert batch_dir is not None
                pngs = sorted(batch_dir.glob("lt_*.png"))
                if len(pngs) < 1:
                    detail = (proc.stderr or proc.stdout or "batch produced no PNGs").strip()
                    _last_error = detail[-800:]
                    raise RuntimeError(_last_error)
        except subprocess.TimeoutExpired as exc:
            _last_error = f"bake timed out after {timeout}s"
            raise RuntimeError(_last_error) from exc
        finally:
            _busy = False
            _busy_since = None

    if count == 1:
        assert out_path is not None
        label = f"{cat['label']} · {seed[:16]}"
        if keep_best_only:
            label = f"{cat['label']} · best of {best} · {seed[:16]}"
        item = {
            "id": out_path.stem,
            "category": category,
            "preset": preset,
            "seed": seed,
            "width": width,
            "height": height,
            "nebulaRes": nebula_res,
            "file": f"images/{out_path.name}",
            "source": "generated",
            "createdAt": utc_now(),
            "label": label,
        }
        if keep_best_only:
            item["bestOf"] = best
        with _lock:
            manifest = load_manifest()
            manifest.setdefault("items", []).insert(0, item)
            save_manifest(manifest)
        return item

    assert batch_dir is not None
    pngs = sorted(batch_dir.glob("lt_*.png"))

    if keep_best_only:
        score_mod = _load_score_pick(ltheory)
        winner, stats = score_mod.pick_best(pngs)
        parts = winner.stem.split("_", 3)
        plate_preset = parts[2] if len(parts) >= 3 else preset
        plate_seed = parts[3] if len(parts) >= 4 else seed
        item = _ingest_png(
            winner,
            category=category,
            preset=plate_preset,
            seed=str(plate_seed),
            width=width,
            height=height,
            nebula_res=nebula_res,
            label=(
                f"{cat['label']} · best of {len(pngs)} · "
                f"score {stats['score']:.0f} · {str(plate_seed)[:12]}"
            ),
        )
        item["bestOf"] = len(pngs)
        item["score"] = round(float(stats["score"]), 2)
        for png in pngs:
            png.unlink(missing_ok=True)
        batch_dir.rmdir()
        with _lock:
            manifest = load_manifest()
            manifest.setdefault("items", []).insert(0, item)
            save_manifest(manifest)
        return item

    items: list[dict[str, Any]] = []
    for png in pngs:
        # Filename: lt_001_preset_seed.png — seed may contain digits only.
        parts = png.stem.split("_", 3)
        plate_preset = parts[2] if len(parts) >= 3 else preset
        plate_seed = parts[3] if len(parts) >= 4 else seed
        plate_cat = category
        for cid, cinfo in CATEGORIES.items():
            if cinfo["preset"] == plate_preset:
                plate_cat = cid
                break
        label_cat = CATEGORIES.get(plate_cat, cat)
        item = _ingest_png(
            png,
            category=plate_cat,
            preset=plate_preset,
            seed=plate_seed,
            width=width,
            height=height,
            nebula_res=nebula_res,
            label=f"{label_cat['label']} · {str(plate_seed)[:16]}",
        )
        items.append(item)
    for png in batch_dir.glob("*.png"):
        png.unlink(missing_ok=True)
    batch_dir.rmdir()

    with _lock:
        manifest = load_manifest()
        for item in reversed(items):
            manifest.setdefault("items", []).insert(0, item)
        save_manifest(manifest)
    return items


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(STATIC), **kwargs)

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[gallery] {self.address_string()} {fmt % args}")

    def _json(self, code: int, payload: Any) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        if not raw:
            return {}
        return json.loads(raw.decode())

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/meta":
            profile = resolve_profile()
            cfg = PROFILES[profile]
            sizes = active_sizes()
            quality = active_quality()
            self._json(
                HTTPStatus.OK,
                {
                    "categories": [
                        {"id": k, **v} for k, v in CATEGORIES.items()
                    ],
                    "sizes": {
                        k: {"width": w, "height": h} for k, (w, h) in sizes.items()
                    },
                    "quality": quality,
                    "defaults": {
                        "size": cfg["defaultSize"],
                        "quality": cfg["defaultQuality"],
                    },
                    "profile": profile,
                    "profileNote": cfg["note"],
                    "memTotalMiB": mem_total_mib(),
                    "rateLimitSec": RATE_LIMIT_SEC,
                    "bakeTimeoutSec": BAKE_TIMEOUT_SEC,
                    "maxBatchCount": MAX_BATCH_COUNT,
                    "maxBestCount": MAX_BEST_COUNT,
                    "daemon": daemon_status(),
                    "ltheory": str(find_ltheory_root()),
                },
            )
            return

        if path == "/api/health":
            try:
                ltheory = find_ltheory_root()
                ok = (ltheory / "tools" / "wallpaper.sh").is_file()
            except FileNotFoundError:
                ltheory = None
                ok = False
            code = HTTPStatus.OK if ok else HTTPStatus.SERVICE_UNAVAILABLE
            self._json(
                code,
                {
                    "ok": ok,
                    "busy": _busy,
                    "profile": resolve_profile(),
                    "daemon": daemon_status(),
                    "ltheory": str(ltheory) if ltheory else None,
                },
            )
            return

        if path == "/api/status":
            self._json(HTTPStatus.OK, rate_status(client_ip(self)))
            return

        if path.startswith("/api/jobs/"):
            job_id = path[len("/api/jobs/") :].strip("/")
            if not re.fullmatch(r"[a-f0-9]{12}", job_id or ""):
                self._json(HTTPStatus.BAD_REQUEST, {"error": "bad job id"})
                return
            with _jobs_lock:
                job = _jobs.get(job_id)
            if not job:
                self._json(HTTPStatus.NOT_FOUND, {"error": "job not found"})
                return
            self._json(HTTPStatus.OK, _public_job(job))
            return

        if path == "/api/gallery":
            qs = parse_qs(parsed.query)
            category = (qs.get("category") or [None])[0]
            with _lock:
                items = list(load_manifest().get("items", []))
            if category and category in CATEGORIES:
                items = [i for i in items if i.get("category") == category]
            self._json(HTTPStatus.OK, {"items": items})
            return

        if path.startswith("/api/image/"):
            item_id = path[len("/api/image/") :].strip("/")
            if not re.fullmatch(r"[a-f0-9]{12}", item_id or ""):
                self._json(HTTPStatus.BAD_REQUEST, {"error": "bad id"})
                return
            file_path = IMAGES / f"{item_id}.png"
            if not file_path.is_file():
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            data = file_path.read_bytes()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "public, max-age=86400")
            self.end_headers()
            self.wfile.write(data)
            return

        if path in ("/", ""):
            self.path = "/index.html"
        return SimpleHTTPRequestHandler.do_GET(self)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path != "/api/generate":
            self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return

        ip = client_ip(self)
        status = rate_status(ip)
        if status["busy"]:
            self._json(
                HTTPStatus.TOO_MANY_REQUESTS,
                {"error": "A bake is already running. Try again shortly.", **status},
            )
            return
        if status["retryAfterSec"] > 0:
            self._json(
                HTTPStatus.TOO_MANY_REQUESTS,
                {
                    "error": f"Rate limit: one wallpaper per {RATE_LIMIT_SEC}s.",
                    **status,
                },
            )
            return

        try:
            body = self._read_json()
        except json.JSONDecodeError:
            self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid JSON"})
            return

        category = str(body.get("category") or "sky")
        if category not in CATEGORIES:
            self._json(
                HTTPStatus.BAD_REQUEST,
                {"error": f"unknown category; choose one of {list(CATEGORIES)}"},
            )
            return

        sizes = active_sizes()
        quality = active_quality()
        cfg = PROFILES[resolve_profile()]
        size_key = str(body.get("size") or cfg["defaultSize"])
        if size_key not in sizes:
            self._json(
                HTTPStatus.BAD_REQUEST,
                {
                    "error": f"bad size for profile {resolve_profile()}; "
                    f"allowed: {list(sizes)}",
                },
            )
            return
        width, height = sizes[size_key]

        quality_key = str(body.get("quality") or cfg["defaultQuality"])
        if quality_key not in quality:
            self._json(
                HTTPStatus.BAD_REQUEST,
                {
                    "error": f"bad quality for profile {resolve_profile()}; "
                    f"allowed: {list(quality)}",
                },
            )
            return
        nebula_res = quality[quality_key]

        seed = str(body.get("seed") or "").strip()
        if not seed:
            seed = random_seed()
        if not re.fullmatch(r"[0-9A-Za-z_-]{1,64}", seed):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "bad seed"})
            return

        try:
            count = int(body.get("count") or 1)
        except (TypeError, ValueError):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "bad count"})
            return
        if count < 1 or count > MAX_BATCH_COUNT:
            self._json(
                HTTPStatus.BAD_REQUEST,
                {"error": f"count must be 1..{MAX_BATCH_COUNT}"},
            )
            return

        try:
            best = int(body.get("best") or 1)
        except (TypeError, ValueError):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "bad best"})
            return
        if best < 1 or best > MAX_BEST_COUNT:
            self._json(
                HTTPStatus.BAD_REQUEST,
                {"error": f"best must be 1..{MAX_BEST_COUNT}"},
            )
            return

        # Async job so long bakes survive reverse-proxy / tunnel POST timeouts.
        _prune_jobs()
        job_id = uuid.uuid4().hex[:12]
        cat = CATEGORIES[category]
        job = {
            "id": job_id,
            "status": "queued",
            "phase": "queued",
            "progress": 1,
            "message": "Queued…",
            "error": None,
            "logTail": None,
            "hint": None,
            "category": category,
            "preset": cat["preset"],
            "best": best,
            "count": count,
            "mode": None,
            "startedAtMono": time.monotonic(),
            "item": None,
            "items": None,
            "ip": ip,
        }
        with _jobs_lock:
            _jobs[job_id] = job
        # Reserve the bake slot immediately (run_bake also toggles _busy).
        global _busy, _busy_since
        _busy = True
        _busy_since = time.monotonic()

        params = {
            "category": category,
            "seed": seed,
            "width": width,
            "height": height,
            "nebula_res": nebula_res,
            "count": count,
            "best": best,
        }
        thread = threading.Thread(
            target=_run_bake_job,
            args=(job_id, ip, params),
            name=f"bake-{job_id}",
            daemon=True,
        )
        thread.start()
        self._json(
            HTTPStatus.ACCEPTED,
            {
                "jobId": job_id,
                "job": _public_job(job),
                **rate_status(ip),
            },
        )

def main() -> None:
    parser = argparse.ArgumentParser(description="LT Wallpaper Gallery server")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    IMAGES.mkdir(parents=True, exist_ok=True)
    if not MANIFEST_PATH.exists():
        save_manifest({"version": 1, "items": []})

    ltheory = find_ltheory_root()
    profile = resolve_profile()
    mem = mem_total_mib()
    print("LT Wallpaper Gallery")
    print(f"  ltheory:  {ltheory}")
    print(f"  gallery:  {DATA}")
    print(f"  listen:   http://{args.host}:{args.port}/")
    print(f"  rate:     1 bake / {RATE_LIMIT_SEC}s / IP")
    print(f"  profile:  {profile}" + (f" (MemTotal {mem} MiB)" if mem else ""))
    print(f"  note:     {PROFILES[profile]['note']}")

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
