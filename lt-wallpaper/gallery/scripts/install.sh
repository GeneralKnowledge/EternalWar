#!/usr/bin/env bash
# Install LT Wallpaper Gallery on a Linux VPS (build ltheory + systemd unit).
#
# Usage:
#   sudo ./scripts/install.sh
#   sudo LT_INSTALL_ROOT=/opt/lt-wallpaper ./scripts/install.sh
#
# For 1 GiB + swap boxes, build may need swap thrash time — be patient.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

GALLERY_SRC="$(cd "$(dirname "$0")/.." && pwd)"
LT_WALLPAPER_SRC="$(cd "$GALLERY_SRC/.." && pwd)"
INSTALL_ROOT="${LT_INSTALL_ROOT:-/opt/lt-wallpaper}"
DATA_ROOT="${LT_GALLERY_DATA:-/var/lib/lt-wallpaper/gallery}"
SPOOL_ROOT="${LT_WALLPAPER_SPOOL:-/var/lib/lt-wallpaper/spool}"
SERVICE_USER="${LT_SERVICE_USER:-ltwallpaper}"
PROFILE="${LT_GALLERY_PROFILE:-}"

echo "==> Installing apt deps"
bash "$GALLERY_SRC/scripts/install-deps.sh"

echo "==> Creating user $SERVICE_USER"
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home "$INSTALL_ROOT" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

echo "==> Syncing project → $INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"
rsync -a --delete \
  --exclude 'ltheory/' \
  --exclude 'gallery/data/images/' \
  --exclude 'gallery/data/manifest.json' \
  --exclude 'gallery/.env' \
  --exclude '.git/' \
  "$LT_WALLPAPER_SRC/" "$INSTALL_ROOT/"

mkdir -p "$DATA_ROOT/images" "$SPOOL_ROOT"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_ROOT" "$DATA_ROOT" "$SPOOL_ROOT"

if [[ -z "$PROFILE" ]]; then
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  mem_mib=$((mem_kb / 1024))
  if (( mem_mib <= 1536 )); then
    PROFILE=small
  else
    PROFILE=standard
  fi
fi

echo "==> Writing $INSTALL_ROOT/gallery/.env (profile=$PROFILE)"
cat > "$INSTALL_ROOT/gallery/.env" <<EOF
LTHEORY_ROOT=$INSTALL_ROOT/ltheory
LT_GALLERY_HOST=127.0.0.1
LT_GALLERY_PORT=8080
LT_GALLERY_DATA=$DATA_ROOT
LT_GALLERY_PROFILE=$PROFILE
LT_GALLERY_RATE_SEC=60
LT_GALLERY_BAKE_TIMEOUT=600
LT_WALLPAPER_DAEMON=auto
LT_WALLPAPER_SPOOL=$SPOOL_ROOT
EOF
chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_ROOT/gallery/.env"
chmod 640 "$INSTALL_ROOT/gallery/.env"

echo "==> Building ltheory (this can take a while / thrash on 1 GiB)"
# Run as service user from a cwd they can access (not ~/… of the invoking user).
# Otherwise git fails: "failed to stat '.../gallery': Permission denied".
sudo -u "$SERVICE_USER" -H env LTHEORY_DIR="$INSTALL_ROOT/ltheory" \
  bash -c "cd '$INSTALL_ROOT' && bash '$INSTALL_ROOT/setup.sh'"

# Ensure wallpaper overlay tools/app are present after build
cp -a "$INSTALL_ROOT/overlay/script/App/Wallpaper.lua" \
  "$INSTALL_ROOT/ltheory/script/App/Wallpaper.lua"
if [[ -d "$INSTALL_ROOT/overlay/script/Game" ]]; then
  mkdir -p "$INSTALL_ROOT/ltheory/script/Game"
  cp -a "$INSTALL_ROOT/overlay/script/Game/." "$INSTALL_ROOT/ltheory/script/Game/"
fi
if [[ -d "$INSTALL_ROOT/overlay/script/Gen" ]]; then
  mkdir -p "$INSTALL_ROOT/ltheory/script/Gen"
  cp -a "$INSTALL_ROOT/overlay/script/Gen/." "$INSTALL_ROOT/ltheory/script/Gen/"
fi
cp -a "$INSTALL_ROOT/overlay/tools/wallpaper.sh" \
  "$INSTALL_ROOT/overlay/tools/score_pick.py" \
  "$INSTALL_ROOT/overlay/tools/wallpaperd.py" \
  "$INSTALL_ROOT/ltheory/tools/"
chmod +x "$INSTALL_ROOT/ltheory/tools/wallpaper.sh" \
  "$INSTALL_ROOT/ltheory/tools/score_pick.py" \
  "$INSTALL_ROOT/ltheory/tools/wallpaperd.py"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_ROOT/ltheory"

echo "==> Installing systemd units (warm daemon + gallery)"
for unit in lt-wallpaperd.service lt-wallpaper-gallery.service; do
  install -m 644 "$GALLERY_SRC/deploy/$unit" "/etc/systemd/system/$unit"
  sed -i \
    -e "s|/opt/lt-wallpaper|$INSTALL_ROOT|g" \
    -e "s|/var/lib/lt-wallpaper/spool|$SPOOL_ROOT|g" \
    -e "s|User=ltwallpaper|User=$SERVICE_USER|g" \
    -e "s|Group=ltwallpaper|Group=$SERVICE_USER|g" \
    "/etc/systemd/system/$unit"
done

systemctl daemon-reload
systemctl enable --now lt-wallpaperd.service
systemctl enable --now lt-wallpaper-gallery.service

echo
echo "Installed."
echo "  daemon:   systemctl status lt-wallpaperd"
echo "  gallery:  systemctl status lt-wallpaper-gallery"
echo "  health:   curl -sS http://127.0.0.1:8080/api/health"
echo "  UI:       http://127.0.0.1:8080/  (localhost — point your tunnel/proxy here)"
echo "  env:      $INSTALL_ROOT/gallery/.env"
echo "  data:     $DATA_ROOT"
echo "  spool:    $SPOOL_ROOT"
