#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="yerbexplorer"
APP_DIR="/opt/yerb-multi-explorer"
APP_NAME="yerb-multi-explorer"
BRANCH="${BRANCH:-main}"
[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
[[ -d "$APP_DIR/.git" ]] || { echo "Explorer is not installed at $APP_DIR" >&2; exit 1; }
backup_dir="/var/backups/yerb-multi-explorer/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
cp -a "$APP_DIR/settings.json" "$backup_dir/" 2>/dev/null || true
cp -a "$APP_DIR/.installer.env" "$backup_dir/" 2>/dev/null || true
sudo -u "$APP_USER" git -C "$APP_DIR" fetch origin
sudo -u "$APP_USER" git -C "$APP_DIR" checkout "$BRANCH"
sudo -u "$APP_USER" git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
sudo -u "$APP_USER" bash -lc "cd '$APP_DIR' && npm ci"
if grep -q "app.get('\*'" "$APP_DIR/lib/nodeapi.js"; then
  sed -i "s/app\.get('\*', hasAccess/app.get(\/\.\*\//, hasAccess/" "$APP_DIR/lib/nodeapi.js"
fi
if [[ -f "$APP_DIR/installer/apply-yerbas-branding.sh" ]]; then
  chmod 0755 "$APP_DIR/installer/apply-yerbas-branding.sh"
  APP_DIR="$APP_DIR" APP_USER="$APP_USER" bash "$APP_DIR/installer/apply-yerbas-branding.sh"
fi
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="/home/$APP_USER/.pm2" pm2 reload "$APP_NAME" --update-env
sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="/home/$APP_USER/.pm2" pm2 save
sleep 5
/usr/local/sbin/yerb-explorer-health || true
echo "Update complete. Backup: $backup_dir"
