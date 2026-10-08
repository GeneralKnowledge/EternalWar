#!/usr/bin/env bash
# Clone JoshParnell/ltheory, apply the wallpaper overlay, build on Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OVERLAY="$ROOT/overlay"
DEST="${LTHEORY_DIR:-$ROOT/ltheory}"
PIN="${LTHEORY_PIN:-21d450406b2a742b2773692198e7a908a9978ec4}"

if [[ ! -d "$DEST/.git" ]]; then
  echo "Cloning JoshParnell/ltheory @ $PIN → $DEST"
  git lfs install
  git clone --recursive https://github.com/JoshParnell/ltheory.git "$DEST"
  git -C "$DEST" checkout "$PIN"
  git -C "$DEST" submodule update --init --recursive
else
  echo "Using existing checkout: $DEST"
fi

echo "Applying overlay from $OVERLAY"
# Copy overlay files (do not wipe unrelated upstream files)
cp -a "$OVERLAY/." "$DEST/"

echo "Fetching/building missing linux64 libs…"
LTHEORY_DIR="$DEST" "$ROOT/scripts/fetch-linux-libs.sh"

# SONAME helpers for vendored Bullet / FMOD
LIB64="$DEST/libphx/ext/lib/linux64"
if [[ -d "$LIB64" ]]; then
  cd "$LIB64"
  [[ -e libBulletCollision.so.2.87 ]] && ln -sfn libBulletCollision.so.2.87 libBulletCollision.so
  [[ -e libBulletDynamics.so.2.87 ]] && ln -sfn libBulletDynamics.so.2.87 libBulletDynamics.so
  [[ -e libLinearMath.so.2.87 ]] && ln -sfn libLinearMath.so.2.87 libLinearMath.so
  [[ -e libfmod.so ]] && ln -sfn libfmod.so libfmod.so.10
  [[ -e libfmodstudio.so ]] && ln -sfn libfmodstudio.so libfmodstudio.so.10
  [[ -e libfmodL.so ]] && ln -sfn libfmodL.so libfmodL.so.10
  [[ -e libfmodstudioL.so ]] && ln -sfn libfmodstudioL.so libfmodstudioL.so.10
fi

cd "$DEST"
chmod +x tools/wallpaper.sh tools/score_pick.py tools/wallpaperd.py configure.py
echo "Configuring…"
python3 configure.py
echo "Building…"
python3 configure.py build
echo
echo "Done. Generate with:"
echo "  cd $DEST && ./tools/wallpaper.sh seed=42 preset=ship out=wallpaper/out.png"
echo "  cd $DEST && ./tools/wallpaper.sh best=6 preset=capital out=wallpaper/best.png"
echo "  # Warm daemon (keep lt loaded across bakes):"
echo "  cd $DEST && ./tools/wallpaperd.py serve &"
echo "  cd $DEST && ./tools/wallpaperd.py bake --cold preset=fleet best=4 out=wallpaper/out.png"
