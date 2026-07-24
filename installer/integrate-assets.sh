#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/yerb-multi-explorer}"
ASSETS_DIR="$APP_DIR/modules/assets-viewer"
ASSETS_DATA="$ASSETS_DIR/storage"
APP_USER="${APP_USER:-yerbexplorer}"
RPC_HOST="${RPC_HOST:-127.0.0.1}"
RPC_PORT="${RPC_PORT:-8766}"
RPC_USER="${RPC_USER:-}"
RPC_PASSWORD="${RPC_PASSWORD:-}"
MODE="${1:-deploy}"

repository_patch() {
  if [[ -f "$APP_DIR/installer/apply-portal-navigation.py" ]]; then
    python3 "$APP_DIR/installer/apply-portal-navigation.py" "$APP_DIR"
    return
  fi

  local layout="$APP_DIR/views/layout.pug"
  [[ -f "$layout" ]] || return 0
  python3 - "$layout" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
s = s.replace("href='https://assetsviewer.yerbas.org/'", "href='/assets/'")
s = s.replace("href='https://assetsviewer.yerbas.org'", "href='/assets/'")

if "li#assets.nav-item" not in s:
    block = """              li#assets.nav-item
                a.nav-link.portal-assets-link(href='/assets/', title='Browse Yerbas Assets')
                  span.fas.fa-layer-group
                  span.margin-left-5 Assets
"""
    anchor = "              if settings.markets_page.enabled == true\n"
    if anchor in s:
        s = s.replace(anchor, block + anchor, 1)

p.write_text(s, encoding='utf-8')
PY
}

[[ "$MODE" == "--repository" ]] && { repository_patch; exit 0; }
[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ -d "$ASSETS_DIR" ]] || { echo "Missing integrated Assets module at $ASSETS_DIR" >&2; exit 1; }

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y php-fpm php-cli php-curl php-sqlite3 sqlite3

install -d -o www-data -g www-data -m 0770 "$ASSETS_DATA"
find "$ASSETS_DIR" -type d -exec chmod 0755 {} +
find "$ASSETS_DIR" -type f -exec chmod 0644 {} +
chown -R "$APP_USER:$APP_USER" "$ASSETS_DIR"
chown -R www-data:www-data "$ASSETS_DATA"
chmod 0770 "$ASSETS_DATA"

if [[ -f "$APP_DIR/.installer.env" ]]; then
  # shellcheck disable=SC1090
  source "$APP_DIR/.installer.env"
fi

if [[ -z "$RPC_USER" || -z "$RPC_PASSWORD" ]]; then
  SETTINGS="$APP_DIR/settings.json"
  [[ -f "$SETTINGS" ]] || { echo "Missing $SETTINGS" >&2; exit 1; }
  RPC_USER=$(python3 - "$SETTINGS" <<'PY'
import json, re, sys
s = open(sys.argv[1], encoding='utf-8').read()
s = re.sub(r'/\*.*?\*/|//.*', '', s, flags=re.S)
print(json.loads(s)['wallet']['username'])
PY
)
  RPC_PASSWORD=$(python3 - "$SETTINGS" <<'PY'
import json, re, sys
s = open(sys.argv[1], encoding='utf-8').read()
s = re.sub(r'/\*.*?\*/|//.*', '', s, flags=re.S)
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

# config.php is generated from the explorer's shared RPC settings. Keep it in the
# module path while preventing local secrets from blocking future git pulls.
if [[ -d "$APP_DIR/.git" ]]; then
  sudo -u "$APP_USER" git -C "$APP_DIR" update-index --skip-worktree modules/assets-viewer/config.php 2>/dev/null || true
fi

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

NGINX_SITE="/etc/nginx/sites-available/yerb-multi-explorer"
if [[ -f "$NGINX_SITE" ]] && ! grep -q 'yerbas-assets-portal.conf' "$NGINX_SITE"; then
  sed -i '/^[[:space:]]*server[[:space:]]*{/a\    include /etc/nginx/snippets/yerbas-assets-portal.conf;' "$NGINX_SITE"
fi

cat > /etc/systemd/system/yerbas-assets-sync.service <<UNIT
[Unit]
Description=Yerbas Portal integrated asset index synchronization
After=network-online.target yerbasd.service
Requires=yerbasd.service

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
Description=Synchronize integrated Yerbas Portal assets

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

echo "Integrated Assets module enabled from $ASSETS_DIR at /assets/"
