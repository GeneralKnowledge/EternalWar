#!/usr/bin/env bash
# Wrapper: load gallery/.env then run fill-gallery.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
exec python3 "$ROOT/scripts/fill-gallery.py" "$@"
