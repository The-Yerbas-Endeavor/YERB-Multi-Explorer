#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer with sudo." >&2
  exit 1
fi

INSTALL_DIR="/opt/yerbas-multi-explorer"
REPO_URL="https://github.com/The-Yerbas-Endeavor/Multi-Explorer.git"
BRANCH="main"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  ca-certificates curl git nginx sqlite3 \
  php-cli php-fpm php-curl php-sqlite3

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

npm install -g pm2

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
else
  git -C "$INSTALL_DIR" fetch origin "$BRANCH"
  git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
fi

if [[ ! -d "$INSTALL_DIR/apps/explorer" || ! -d "$INSTALL_DIR/apps/assets" ]]; then
  echo "Application sources have not yet been imported into this branch." >&2
  echo "Run scripts/import-sources.sh from a development checkout and commit the result." >&2
  exit 1
fi

cd "$INSTALL_DIR/apps/explorer"
npm ci --omit=dev

mkdir -p "$INSTALL_DIR/apps/assets/storage"
chown -R www-data:www-data "$INSTALL_DIR/apps/assets/storage"
chmod 775 "$INSTALL_DIR/apps/assets/storage"

PHP_FPM_SERVICE="$(systemctl list-unit-files --type=service --no-legend 'php*-fpm.service' | awk 'NR==1 {print $1}')"
PHP_FPM_SOCKET="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -n1)"

if [[ -z "$PHP_FPM_SERVICE" || -z "$PHP_FPM_SOCKET" ]]; then
  echo "Unable to detect PHP-FPM service or socket." >&2
  exit 1
fi

ln -sfn "$PHP_FPM_SOCKET" /run/php/yerbas-assets-fpm.sock
cp "$INSTALL_DIR/deploy/nginx/multi-explorer.conf" /etc/nginx/sites-available/yerbas-multi-explorer
ln -sfn /etc/nginx/sites-available/yerbas-multi-explorer /etc/nginx/sites-enabled/yerbas-multi-explorer
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable --now "$PHP_FPM_SERVICE" nginx

pm2 start "$INSTALL_DIR/apps/explorer/bin/instance" \
  --name yerbas-explorer \
  --node-args="--stack-size=10000"
pm2 save
pm2 startup systemd -u root --hp /root >/tmp/yerbas-pm2-startup.txt || true

systemctl reload nginx

echo "Base installation complete. Configure MongoDB, explorer settings, asset RPC credentials, and synchronization services before production use."
