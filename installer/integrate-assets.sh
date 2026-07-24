#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/yerb-multi-explorer}"
ASSETS_SOURCE="$APP_DIR/modules/assets-viewer"
ASSETS_DIR="${ASSETS_DIR:-/opt/yerbas-portal-assets}"
ASSETS_DATA="${ASSETS_DATA:-/var/lib/yerbas-assets}"
APP_USER="${APP_USER:-yerbexplorer}"
RPC_HOST="${RPC_HOST:-127.0.0.1}"
RPC_PORT="${RPC_PORT:-8766}"
RPC_USER="${RPC_USER:-}"
RPC_PASSWORD="${RPC_PASSWORD:-}"
MODE="${1:-deploy}"

repository_patch() {
  local layout="$APP_DIR/views/layout.pug"
  [[ -f "$layout" ]] || return 0
  python3 - "$layout" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace("a.nav-link.portal-assets-link(href='https://assetsviewer.yerbas.org/'", "a.nav-link.portal-assets-link(href='/assets/'")
s=s.replace("a.nav-link.portal-assets-link(href='https://assetsviewer.yerbas.org'", "a.nav-link.portal-assets-link(href='/assets/'")
p.write_text(s)
PY
}

[[ "$MODE" == "--repository" ]] && { repository_patch; exit 0; }
[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ -d "$ASSETS_SOURCE" ]] || { echo "Missing imported Assets Viewer at $ASSETS_SOURCE" >&2; exit 1; }

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y php-fpm php-cli php-curl php-sqlite3 sqlite3 rsync

install -d -o root -g www-data -m 0750 "$ASSETS_DIR"
rsync -a --delete --exclude='.git' --exclude='storage/' "$ASSETS_SOURCE/" "$ASSETS_DIR/"
install -d -o www-data -g www-data -m 0770 "$ASSETS_DATA"
ln -sfn "$ASSETS_DATA" "$ASSETS_DIR/storage"

if [[ -z "$RPC_USER" || -z "$RPC_PASSWORD" ]]; then
  SETTINGS="$APP_DIR/settings.json"
  RPC_USER=$(python3 - "$SETTINGS" <<'PY'
import json,re,sys
s=open(sys.argv[1]).read(); s=re.sub(r'/\*.*?\*/|//.*','',s,flags=re.S)
print(json.loads(s)['wallet']['username'])
PY
)
  RPC_PASSWORD=$(python3 - "$SETTINGS" <<'PY'
import json,re,sys
s=open(sys.argv[1]).read(); s=re.sub(r'/\*.*?\*/|//.*','',s,flags=re.S)
print(json.loads(s)['wallet']['password'])
PY
)
fi

cat > "$ASSETS_DIR/config.php" <<PHP
<?php
\$cfg['rpcUsername'] = '${RPC_USER//\'/\\\'}';
\$cfg['rpcPassword'] = '${RPC_PASSWORD//\'/\\\'}';
\$cfg['rpcHostIP'] = '${RPC_HOST}';
\$cfg['rpcHostPort'] = ${RPC_PORT};
\$cfg['rpcURL'] = '';
\$cfg['theme'] = 'w3css';
\$cfg['wordFilter'] = '';
\$cfg['filterReplaceChar'] = '&hearts;';
\$cfg['databasePath'] = '${ASSETS_DATA}/assets.sqlite';
\$cfg['assetsPerPage'] = 50;
\$cfg['activityInitialBlocks'] = 500;
\$cfg['basePath'] = '/assets';
?>
PHP
chown root:www-data "$ASSETS_DIR/config.php"
chmod 0640 "$ASSETS_DIR/config.php"
chmod +x "$ASSETS_DIR"/scripts/*.sh "$ASSETS_DIR"/scripts/*.php 2>/dev/null || true

PHP_SOCK=$(find /run/php -maxdepth 1 -name 'php*-fpm.sock' | sort -V | tail -1)
[[ -n "$PHP_SOCK" ]] || { echo "PHP-FPM socket not found" >&2; exit 1; }

cat > /etc/nginx/snippets/yerbas-assets-portal.conf <<NGINX
location = /assets { return 301 /assets/; }
location ^~ /assets/storage/ { deny all; }
location ^~ /assets/src/ { deny all; }
location ^~ /assets/scripts/ { deny all; }
location ^~ /assets/deploy/ { deny all; }
location ~ ^/assets/(.+\.php)$ {
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME ${ASSETS_DIR}/\$1;
    fastcgi_param SCRIPT_NAME /assets/\$1;
    fastcgi_param HTTP_X_FORWARDED_PREFIX /assets;
    fastcgi_pass unix:${PHP_SOCK};
}
location /assets/ {
    alias ${ASSETS_DIR}/;
    index index.php;
    try_files \$uri \$uri/ /assets/index.php?\$query_string;
}
NGINX

NGINX_SITE=$(grep -rl "proxy_pass http://127.0.0.1:300" /etc/nginx/sites-available | head -1 || true)
if [[ -n "$NGINX_SITE" ]] && ! grep -q 'yerbas-assets-portal.conf' "$NGINX_SITE"; then
  sed -i '/^[[:space:]]*server[[:space:]]*{/a\    include /etc/nginx/snippets/yerbas-assets-portal.conf;' "$NGINX_SITE"
fi

cat > /etc/systemd/system/yerbas-assets-sync.service <<UNIT
[Unit]
Description=Yerbas Portal asset index synchronization
After=network-online.target

[Service]
Type=oneshot
User=www-data
Group=www-data
WorkingDirectory=${ASSETS_DIR}
ExecStart=${ASSETS_DIR}/scripts/run-sync.sh
Nice=10
PrivateTmp=true
NoNewPrivileges=true
UNIT

cat > /etc/systemd/system/yerbas-assets-sync.timer <<'UNIT'
[Unit]
Description=Synchronize Yerbas Portal assets

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

repository_patch
systemctl daemon-reload
systemctl enable --now yerbas-assets-sync.timer
systemctl start yerbas-assets-sync.service || true
nginx -t
systemctl reload nginx

echo "Yerbas Assets Viewer merged and enabled at /assets/"
