#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-/opt/yerb-multi-explorer}"
APP_USER="${APP_USER:-yerbexplorer}"

[[ ${EUID} -eq 0 ]] || {
  echo "Run the unified installer with sudo." >&2
  exit 1
}

if [[ -z "${BRANCH:-}" ]]; then
  BRANCH=$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)
  BRANCH="${BRANCH:-main}"
fi
export BRANCH

echo "Installing the unified Yerbas Portal from branch: $BRANCH"

chmod 0755 "$ROOT_DIR/installer/install.sh"
"$ROOT_DIR/installer/install.sh"

[[ -x "$APP_DIR/installer/integrate-assets.sh" ]] || chmod 0755 "$APP_DIR/installer/integrate-assets.sh"
APP_DIR="$APP_DIR" APP_USER="$APP_USER" bash "$APP_DIR/installer/integrate-assets.sh"

systemctl is-active --quiet nginx
systemctl is-active --quiet "pm2-${APP_USER}"
systemctl is-active --quiet yerbas-assets-sync.timer

curl -fsS --max-time 10 http://127.0.0.1/assets/ >/dev/null

echo
echo "Unified Yerbas Portal installation complete."
echo "Explorer and Assets are installed together under: $APP_DIR"
echo "Assets module: $APP_DIR/modules/assets-viewer"
echo "Assets URL: /assets/"
