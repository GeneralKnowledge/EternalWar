#!/usr/bin/env bash
# System packages for native wallpaper bake + gallery on Debian/Ubuntu.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo $0)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential cmake git git-lfs rsync \
  python3 python3-venv \
  libglew-dev libsdl2-dev libfreetype-dev libluajit-5.1-dev \
  libgl1-mesa-dev libgl1-mesa-dri mesa-utils \
  g++ \
  xvfb xauth \
  lua-filesystem \
  curl ca-certificates

git lfs install --system || git lfs install || true
echo "Deps installed."
