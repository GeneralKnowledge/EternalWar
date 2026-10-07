#!/usr/bin/env bash
# Populate missing linux64 artifacts after cloning Josh's tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LTHEORY="${LTHEORY_DIR:-$ROOT/ltheory}"
LIB64="$LTHEORY/libphx/ext/lib/linux64"
mkdir -p "$LIB64"

if [[ ! -f "$LIB64/lfs.so" ]]; then
  if [[ -f /usr/lib/x86_64-linux-gnu/lua/5.1/lfs.so ]]; then
    cp /usr/lib/x86_64-linux-gnu/lua/5.1/lfs.so "$LIB64/lfs.so"
    echo "Copied system lfs.so"
  else
    echo "Install lua-filesystem (apt) or place lfs.so in $LIB64" >&2
    exit 1
  fi
fi

if [[ ! -f "$LIB64/libLinearMath.so.2.87" ]]; then
  echo "Building Bullet 2.87 LinearMath (one-time)…"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -sL -o "$TMP/bullet.tgz" https://github.com/bulletphysics/bullet3/archive/refs/tags/2.87.tar.gz
  tar xzf "$TMP/bullet.tgz" -C "$TMP"
  mkdir -p "$TMP/build"
  (cd "$TMP/build" && CXX=g++ CC=gcc cmake "$TMP/bullet3-2.87" \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DBUILD_BULLET2_DEMOS=OFF -DBUILD_EXTRAS=OFF -DBUILD_UNIT_TESTS=OFF \
      -DBUILD_CPU_DEMOS=OFF -DBUILD_OPENGL3_DEMOS=OFF -DUSE_DOUBLE_PRECISION=OFF \
      >/dev/null)
  cmake --build "$TMP/build" --target LinearMath -j"$(nproc)"
  cp "$TMP/build/src/LinearMath/libLinearMath.so.2.87" "$LIB64/"
  echo "Installed libLinearMath.so.2.87"
fi

cd "$LIB64"
ln -sfn libLinearMath.so.2.87 libLinearMath.so
echo "Linux libs ready in $LIB64"
