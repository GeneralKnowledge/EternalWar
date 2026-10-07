#!/usr/bin/env bash
# Generate a Limit Theory wallpaper on Linux (Xvfb when no usable display).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ARCH=64
BIN=""
for candidate in "bin/lt${ARCH}" "bin/lt${ARCH}r" "bin/lt${ARCH}d"; do
  if [[ -x "$candidate" ]]; then BIN="$candidate"; break; fi
done
if [[ -z "$BIN" ]]; then
  echo "lt binary not found. Run: python3 configure.py && python3 configure.py build" >&2
  exit 1
fi

# ffi.load('libphx64') and lfs.so live in bin/; Bullet/FMOD in ext.
LIBDIR="$ROOT/libphx/ext/lib/linux${ARCH}"
# Release builds emit libphx64r.so — alias for the RelWithDebInfo name.
if [[ -e "$ROOT/bin/libphx${ARCH}r.so" && ! -e "$ROOT/bin/libphx${ARCH}.so" ]]; then
  ln -sf "libphx${ARCH}r.so" "$ROOT/bin/libphx${ARCH}.so"
fi
if [[ -e "$ROOT/bin/lt${ARCH}r" && ! -e "$ROOT/bin/lt${ARCH}" ]]; then
  ln -sf "lt${ARCH}r" "$ROOT/bin/lt${ARCH}"
fi

export LD_LIBRARY_PATH="$ROOT/bin:${LIBDIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

ARGS=("Wallpaper" "$@")

# Prefer real display only if FORCE_DISPLAY=1; cloud/headless boxes often have
# a stale DISPLAY that cannot create a GL context.
if [[ "${FORCE_DISPLAY:-}" == "1" && -n "${DISPLAY:-}" ]]; then
  exec "$BIN" "${ARGS[@]}"
fi

if command -v xvfb-run >/dev/null 2>&1; then
  exec xvfb-run -a -s "-screen 0 1920x1080x24" env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
    "$BIN" "${ARGS[@]}"
fi

if [[ -n "${DISPLAY:-}" ]]; then
  exec "$BIN" "${ARGS[@]}"
fi

echo "No DISPLAY and xvfb-run not found. Install xvfb or set DISPLAY." >&2
exit 1
