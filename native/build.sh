#!/usr/bin/env bash
# Build EternalWar native kernels (Rust GDExtension) and install into bin/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CRATE="$ROOT/native/ew_kernels"
BIN="$ROOT/bin"
PROFILE="${1:-release}"

mkdir -p "$BIN"
cd "$CRATE"

if [[ "$PROFILE" == "debug" ]]; then
  cargo build
  SRC="$CRATE/target/debug/libew_kernels.so"
else
  cargo build --release
  SRC="$CRATE/target/release/libew_kernels.so"
fi

cp -f "$SRC" "$BIN/libew_kernels.so"
echo "Installed $BIN/libew_kernels.so ($(wc -c < "$BIN/libew_kernels.so") bytes, profile=$PROFILE)"
