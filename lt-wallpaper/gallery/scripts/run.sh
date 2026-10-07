#!/usr/bin/env bash
# Dev / manual foreground run (loads gallery/.env if present).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
exec python3 server.py "$@"
