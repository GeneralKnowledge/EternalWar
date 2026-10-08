#!/usr/bin/env bash
# Generate a Limit Theory wallpaper on Linux (Xvfb when no usable display).
# Supports best=N — bake N candidates in one engine launch, keep the winner.
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

BEST=""
OUT=""
PASS=()
for arg in "$@"; do
  case "$arg" in
    best=*) BEST="${arg#best=}" ;;
    out=*) OUT="${arg#out=}"; PASS+=("$arg") ;;
    count=*)
      # best= owns the candidate count; ignore explicit count=
      if [[ -z "$BEST" ]]; then PASS+=("$arg"); fi
      ;;
    *) PASS+=("$arg") ;;
  esac
done

run_lt () {
  local -a args=("Wallpaper" "$@")
  if [[ "${FORCE_DISPLAY:-}" == "1" && -n "${DISPLAY:-}" ]]; then
    "$BIN" "${args[@]}"
    return
  fi
  if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a -s "-screen 0 1920x1080x24" env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
      "$BIN" "${args[@]}"
    return
  fi
  if [[ -n "${DISPLAY:-}" ]]; then
    "$BIN" "${args[@]}"
    return
  fi
  echo "No DISPLAY and xvfb-run not found. Install xvfb or set DISPLAY." >&2
  exit 1
}

if [[ -n "$BEST" ]]; then
  if ! [[ "$BEST" =~ ^[0-9]+$ ]] || [[ "$BEST" -lt 1 ]]; then
    echo "best= must be a positive integer" >&2
    exit 1
  fi
  if [[ "$BEST" -eq 1 ]]; then
    run_lt "${PASS[@]}"
    exit 0
  fi
  if [[ -z "$OUT" ]]; then
    echo "best=$BEST requires out=<path>" >&2
    exit 1
  fi
  STAGE="$(mktemp -d "$ROOT/wallpaper/.best.XXXXXX" 2>/dev/null || mktemp -d /tmp/lt-best.XXXXXX)"
  mkdir -p "$(dirname "$OUT")"
  # Strip out= from PASS for the staged batch.
  STAGE_ARGS=()
  for arg in "${PASS[@]}"; do
    case "$arg" in
      out=*) ;;
      *) STAGE_ARGS+=("$arg") ;;
    esac
  done
  cleanup() { rm -rf "$STAGE"; }
  trap cleanup EXIT
  run_lt "${STAGE_ARGS[@]}" "count=$BEST" "outdir=$STAGE"
  python3 "$ROOT/tools/score_pick.py" --dir "$STAGE" --out "$OUT" --cleanup
  exit 0
fi

run_lt "${PASS[@]}"
