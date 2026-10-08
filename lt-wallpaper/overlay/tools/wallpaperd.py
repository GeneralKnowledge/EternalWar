#!/usr/bin/env python3
"""
Warm LT wallpaper daemon — keep one lt process loaded across bakes.

Protocol (spool directory):
  daemon.ready  — present while idle
  job.req       — client writes key=value job (atomic rename from .tmp)
  job.done      — daemon writes result paths
  shutdown      — touch to stop the engine process

Usage:
  # Start warm engine (blocks; supervise with systemd)
  ./tools/wallpaperd.py serve --spool /var/lib/lt-wallpaper/spool

  # Submit a bake (uses daemon if ready, else cold wallpaper.sh)
  ./tools/wallpaperd.py bake preset=fleet best=4 out=wallpaper/out.png
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPOOL = Path(
    os.environ.get("LT_WALLPAPER_SPOOL", str(ROOT / "wallpaper" / "spool"))
)
BAKE_TIMEOUT = int(os.environ.get("LT_WALLPAPER_DAEMON_TIMEOUT", "600"))
READY_WAIT = float(os.environ.get("LT_WALLPAPER_DAEMON_READY_WAIT", "120"))


def _bin() -> Path:
    for name in ("lt64", "lt64r", "lt64d"):
        p = ROOT / "bin" / name
        if p.is_file() and os.access(p, os.X_OK):
            return p
    raise FileNotFoundError("lt binary not found — build ltheory first")


def _lib_env() -> dict[str, str]:
    env = os.environ.copy()
    arch = "64"
    libdir = ROOT / "libphx" / "ext" / "lib" / f"linux{arch}"
    bindir = ROOT / "bin"
    # Alias release .so names when needed
    r_so = bindir / f"libphx{arch}r.so"
    so = bindir / f"libphx{arch}.so"
    if r_so.is_file() and not so.exists():
        so.symlink_to(r_so.name)
    r_bin = bindir / f"lt{arch}r"
    bin_alias = bindir / f"lt{arch}"
    if r_bin.is_file() and not bin_alias.exists():
        bin_alias.symlink_to(r_bin.name)
    env["LD_LIBRARY_PATH"] = f"{bindir}:{libdir}" + (
        f":{env['LD_LIBRARY_PATH']}" if env.get("LD_LIBRARY_PATH") else ""
    )
    return env


def spool_paths(spool: Path) -> dict[str, Path]:
    return {
        "ready": spool / "daemon.ready",
        "req": spool / "job.req",
        "req_tmp": spool / "job.req.tmp",
        "done": spool / "job.done",
        "shutdown": spool / "shutdown",
        "pid": spool / "daemon.pid",
    }


def is_ready(spool: Path) -> bool:
    p = spool_paths(spool)
    return p["ready"].is_file() and not p["req"].is_file()


def wait_ready(spool: Path, timeout: float = READY_WAIT) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if is_ready(spool):
            return
        time.sleep(0.05)
    raise TimeoutError(f"daemon not ready in {timeout:.0f}s (spool={spool})")


def _parse_done(text: str) -> dict[str, object]:
    data: dict[str, object] = {"paths": []}
    paths: list[str] = []
    for line in text.splitlines():
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        if k.startswith("path") and k[4:].isdigit():
            paths.append(v)
        else:
            data[k] = v
    data["paths"] = paths
    return data


def submit_job(spool: Path, fields: dict[str, str], timeout: float = BAKE_TIMEOUT) -> dict[str, object]:
    """Block until the warm daemon finishes one job."""
    spool.mkdir(parents=True, exist_ok=True)
    paths = spool_paths(spool)
    wait_ready(spool, timeout=min(timeout, READY_WAIT))

    job_id = fields.get("id") or uuid.uuid4().hex[:12]
    fields = {**fields, "id": job_id}
    body = "".join(f"{k}={v}\n" for k, v in fields.items() if v is not None)

    if paths["done"].is_file():
        paths["done"].unlink()
    paths["req_tmp"].write_text(body, encoding="utf-8")
    paths["req_tmp"].replace(paths["req"])

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if paths["done"].is_file():
            text = paths["done"].read_text(encoding="utf-8")
            result = _parse_done(text)
            if str(result.get("id", "")) not in ("", job_id):
                # Stale done from another client — keep waiting.
                time.sleep(0.05)
                continue
            if str(result.get("ok", "0")) != "1":
                raise RuntimeError(str(result.get("error") or "daemon job failed"))
            return result
        if paths["shutdown"].is_file():
            raise RuntimeError("daemon shutting down")
        time.sleep(0.05)
    raise TimeoutError(f"job {job_id} timed out after {timeout}s")


def serve(spool: Path, width: int, height: int) -> int:
    """Run the warm lt process in the foreground."""
    spool.mkdir(parents=True, exist_ok=True)
    for name in ("job.req", "job.done", "daemon.ready", "shutdown"):
        p = spool / name
        if p.is_file():
            p.unlink()

    bin_path = _bin()
    env = _lib_env()
    args = [
        str(bin_path),
        "Wallpaper",
        "daemon=1",
        f"spool={spool}",
        f"width={width}",
        f"height={height}",
        "preset=sky",
    ]
    print(f"wallpaperd: starting {bin_path} spool={spool}", flush=True)

    if os.environ.get("FORCE_DISPLAY") == "1" and env.get("DISPLAY"):
        proc = subprocess.Popen(args, cwd=str(ROOT), env=env)
    elif shutil.which("xvfb-run"):
        proc = subprocess.Popen(
            ["xvfb-run", "-a", "-s", "-screen 0 1920x1080x24", *args],
            cwd=str(ROOT),
            env=env,
        )
    elif env.get("DISPLAY"):
        proc = subprocess.Popen(args, cwd=str(ROOT), env=env)
    else:
        print("wallpaperd: need xvfb-run or DISPLAY", file=sys.stderr)
        return 1

    try:
        return proc.wait()
    except KeyboardInterrupt:
        (spool / "shutdown").write_text("1\n", encoding="utf-8")
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
        return 0


def _parse_bake_args(argv: list[str]) -> dict[str, str]:
    fields: dict[str, str] = {}
    for a in argv:
        if "=" in a:
            k, _, v = a.partition("=")
            fields[k] = v
    return fields


def bake(spool: Path, argv: list[str], allow_cold: bool) -> int:
    fields = _parse_bake_args(argv)
    best = int(fields.pop("best", "1") or "1")
    out = fields.get("out")
    if best > 1 and not out:
        print("best=N requires out=", file=sys.stderr)
        return 2

    use_daemon = is_ready(spool) or (
        spool_paths(spool)["pid"].is_file() and allow_cold is False
    )
    # Prefer daemon when ready; optionally wait briefly if pid exists.
    if not is_ready(spool) and spool_paths(spool)["pid"].is_file():
        try:
            wait_ready(spool, timeout=30)
            use_daemon = True
        except TimeoutError:
            use_daemon = False

    if not use_daemon:
        if not allow_cold:
            print("wallpaperd: daemon not ready", file=sys.stderr)
            return 3
        script = ROOT / "tools" / "wallpaper.sh"
        cmd = [str(script), *argv]
        print("wallpaperd: cold fallback → wallpaper.sh", flush=True)
        return subprocess.call(cmd, cwd=str(ROOT))

    stage: Path | None = None
    try:
        job = {
            "seed": fields.get("seed", ""),
            "preset": fields.get("preset", "ship"),
            "width": fields.get("width", "1920"),
            "height": fields.get("height", "1080"),
            "nebulaRes": fields.get("nebulaRes", ""),
            "frames": fields.get("frames", ""),
        }
        # Drop empties
        job = {k: v for k, v in job.items() if v}

        if best > 1:
            stage = Path(tempfile.mkdtemp(prefix="lt-best.", dir=str(ROOT / "wallpaper")))
            job["count"] = str(best)
            job["outdir"] = str(stage)
        elif fields.get("count") and int(fields["count"]) > 1:
            job["count"] = fields["count"]
            job["outdir"] = fields.get("outdir") or str(
                Path(tempfile.mkdtemp(prefix="lt-batch.", dir=str(ROOT / "wallpaper")))
            )
            if out and "outdir" not in fields:
                # batch with out stem not used; prefer outdir
                pass
        else:
            job["count"] = "1"
            if out:
                job["out"] = out
            if fields.get("outdir"):
                job["outdir"] = fields["outdir"]

        if fields.get("presets"):
            job["presets"] = fields["presets"]

        print(f"wallpaperd: warm job {job}", flush=True)
        result = submit_job(spool, job)
        paths = list(result.get("paths") or [])
        if not paths:
            print("wallpaperd: daemon returned no paths", file=sys.stderr)
            return 1

        if best > 1 and out:
            score = ROOT / "tools" / "score_pick.py"
            rc = subprocess.call(
                [sys.executable, str(score), "--dir", str(stage), "--out", out, "--cleanup"],
                cwd=str(ROOT),
            )
            return rc

        if out and paths[0] != out:
            Path(out).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(paths[0], out)
            print(f"wallpaperd: wrote {out}", flush=True)
        else:
            for p in paths:
                print(f"wallpaperd: wrote {p}", flush=True)
        return 0
    finally:
        if stage and stage.is_dir():
            shutil.rmtree(stage, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--spool",
        type=Path,
        default=DEFAULT_SPOOL,
        help="Job spool directory shared by daemon + clients",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_serve = sub.add_parser("serve", help="Run warm lt process")
    p_serve.add_argument("--width", type=int, default=1920)
    p_serve.add_argument("--height", type=int, default=1080)

    p_bake = sub.add_parser("bake", help="Submit a bake job")
    p_bake.add_argument("args", nargs="*", help="key=value flags (preset=, out=, best=, …)")
    p_bake.add_argument(
        "--cold",
        action="store_true",
        help="Allow fallback to wallpaper.sh if daemon is down",
    )

    p_status = sub.add_parser("status", help="Print daemon readiness")

    ns = ap.parse_args()
    spool = ns.spool.resolve()

    if ns.cmd == "serve":
        return serve(spool, ns.width, ns.height)
    if ns.cmd == "status":
        ready = is_ready(spool)
        print(f"spool={spool}")
        print(f"ready={ready}")
        print(f"pid_file={spool_paths(spool)['pid'].is_file()}")
        return 0 if ready else 1
    if ns.cmd == "bake":
        return bake(spool, list(ns.args), allow_cold=ns.cold)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
