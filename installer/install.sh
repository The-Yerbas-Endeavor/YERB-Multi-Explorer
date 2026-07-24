#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="yerb-multi-explorer"
APP_USER="yerbexplorer"
APP_DIR="/opt/yerb-multi-explorer"
REPO_URL="https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git"
BRANCH="${BRANCH:-main}"
APP_PORT="${APP_PORT:-3001}"
MONGO_VERSION="${MONGO_VERSION:-8.0}"
MONGO_DB="${MONGO_DB:-explorerdb}"
MONGO_USER="${MONGO_USER:-yerbas}"
LOG_FILE="/var/log/${APP_NAME}-install.log"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
YERBAS_ENV_FILE="/etc/yerbas/explorer.env"

exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "[ERROR] Installation failed near line $LINENO. Review $LOG_FILE" >&2' ERR

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

prompt_url_safe_password() {
  local prompt="$1"
  local variable_name="$2"
  local first second
  while true; do
    read -r -s -p "$prompt" first
    echo
    read -r -s -p "Confirm password: " second
    echo
    [[ "$first" == "$second" ]] || { warn "Passwords do not match."; continue; }
    [[ ${#first} -ge 16 ]] || { warn "Password must be at least 16 characters."; continue; }
    [[ "$first" =~ ^[A-Za-z0-9._~-]+$ ]] || { warn "Use URL-safe characters only: A-Z a-z 0-9 . _ ~ -"; continue; }
    printf -v "$variable_name" '%s' "$first"
    break
  done
}

[[ ${EUID} -eq 0 ]] || die "Run this installer with sudo."
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only."
[[ "${VERSION_ID:-}" == "26.04" ]] || warn "Designed for Ubuntu 26.04; detected ${PRETTY_NAME:-unknown}."

read -r -p "Explorer domain (example: explorer.yerbas.org, blank for IP-only): " DOMAIN
read -r -p "Yerbas RPC username [yerbasrpc]: " RPC_USER
RPC_USER="${RPC_USER:-yerbasrpc}"
[[ "$RPC_USER" =~ ^[A-Za-z0-9._~-]+$ ]] || die "Yerbas RPC username must use URL-safe characters only."
prompt_url_safe_password "Yerbas RPC password: " RPC_PASSWORD
prompt_url_safe_password "MongoDB password for user '${MONGO_USER}': " MONGO_PASSWORD
read -r -p "Install Let's Encrypt SSL when DNS is ready? [y/N]: " ENABLE_SSL
ENABLE_SSL="${ENABLE_SSL,,}"

export RPC_USER RPC_PASSWORD

info "Installing system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg git nginx ufw jq build-essential python3 unattended-upgrades certbot python3-certbot-nginx openssl unzip
systemctl enable --now nginx

info "Installing Yerbas Core wallet and local RPC node"
[[ -x "$SCRIPT_DIR/install-yerbas-core.sh" ]] || chmod +x "$SCRIPT_DIR/install-yerbas-core.sh"
"$SCRIPT_DIR/install-yerbas-core.sh"
[[ -f "$YERBAS_ENV_FILE" ]] || die "Yerbas Core installer did not create $YERBAS_ENV_FILE"
# shellcheck disable=SC1090
source "$YERBAS_ENV_FILE"
[[ -n "${RPC_USER:-}" && -n "${RPC_PASSWORD:-}" && -n "${RPC_PORT:-}" ]] || die "Yerbas RPC credentials are incomplete."
RPC_HOST="${RPC_HOST:-127.0.0.1}"

info "Installing native MongoDB ${MONGO_VERSION}"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_VERSION}.asc" | gpg --dearmor --yes -o "/etc/apt/keyrings/mongodb-server-${MONGO_VERSION}.gpg"
cat > "/etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list" <<EOF_MONGO_REPO
deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/mongodb-server-${MONGO_VERSION}.gpg] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/${MONGO_VERSION} multiverse
EOF_MONGO_REPO
apt-get update
apt-get install -y mongodb-org
sed -i 's/^\([[:space:]]*bindIp:[[:space:]]*\).*/\1127.0.0.1/' /etc/mongod.conf
systemctl enable --now mongod
systemctl is-active --quiet mongod || die "MongoDB failed to start. Check: journalctl -u mongod -n 100 --no-pager -l"

info "Waiting for MongoDB to accept connections"
MONGO_READY=false
for _ in $(seq 1 60); do
  if mongosh --host 127.0.0.1 --port 27017 --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>/dev/null | grep -q '^1$'; then
    MONGO_READY=true
    break
  fi
  sleep 2
done

if [[ "$MONGO_READY" != true ]]; then
  systemctl status mongod --no-pager -l || true
  journalctl -u mongod -n 100 --no-pager -l || true
  die "MongoDB started but did not become ready on 127.0.0.1:27017."
fi
ok "MongoDB is accepting connections"

info "Creating MongoDB user ${MONGO_USER}"
mongosh --host 127.0.0.1 --port 27017 --quiet --eval "
const database = db.getSiblingDB('${MONGO_DB}');
if (database.getUser('${MONGO_USER}')) {
  database.updateUser('${MONGO_USER}', {
    pwd: '${MONGO_PASSWORD}',
    roles: [{ role: 'readWrite', db: '${MONGO_DB}' }]
  });
} else {
  database.createUser({
    user: '${MONGO_USER}',
    pwd: '${MONGO_PASSWORD}',
    roles: [{ role: 'readWrite', db: '${MONGO_DB}' }]
  });
}
"
MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@127.0.0.1:27017/${MONGO_DB}?authSource=${MONGO_DB}"
mongosh "$MONGO_URI" --quiet --eval 'if (db.runCommand({ ping: 1 }).ok !== 1) quit(1)' || die "MongoDB credential test failed."
ok "MongoDB credentials verified"

info "Installing Node.js 22"
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
node --version | grep -q '^v22\.' || die "Node.js 22 was not installed."
npm install -g pm2

info "Creating explorer service account"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --create-home --home-dir "/home/$APP_USER" --shell /bin/bash "$APP_USER"

info "Installing explorer source"
if [[ -d "$APP_DIR/.git" ]]; then
  sudo -u "$APP_USER" git -C "$APP_DIR" fetch origin
  sudo -u "$APP_USER" git -C "$APP_DIR" checkout "$BRANCH"
  sudo -u "$APP_USER" git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
else
  rm -rf "$APP_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

info "Replacing legacy eIquidus branding with Yerbas"
while IFS= read -r -d '' file; do
  sed -i -e 's/eIquidus/Yerbas/g' -e 's/eiquidus/yerbas/g' "$file"
done < <(grep -RIlZ --exclude-dir=.git -e 'eIquidus' -e 'eiquidus' "$APP_DIR" 2>/dev/null || true)

info "Installing locked Node dependencies"
sudo -u "$APP_USER" bash -lc "cd '$APP_DIR' && npm ci"

if grep -q "app.get('\*'" "$APP_DIR/lib/nodeapi.js"; then
  warn "Applying Express 5-compatible wildcard route to lib/nodeapi.js"
  sed -i "s/app\.get('\*', hasAccess/app.get(\/\.\*\//, hasAccess/" "$APP_DIR/lib/nodeapi.js"
fi

info "Creating explorer configuration"
if [[ ! -f "$APP_DIR/settings.json" ]]; then
  if [[ -f "$APP_DIR/settings.json.template" ]]; then
    cp "$APP_DIR/settings.json.template" "$APP_DIR/settings.json"
  elif [[ -f "$APP_DIR/settings.json.example" ]]; then
    cp "$APP_DIR/settings.json.example" "$APP_DIR/settings.json"
  else
    die "No settings template was found."
  fi
fi

if [[ -f "$APP_DIR/settings.json" ]]; then
  SETTINGS_TMP="$(mktemp)"
  jq \
    --arg mongo_user "$MONGO_USER" \
    --arg mongo_password "$MONGO_PASSWORD" \
    --arg mongo_database "$MONGO_DB" \
    --arg mongo_address "127.0.0.1" \
    --argjson mongo_port 27017 \
    --arg rpc_host "$RPC_HOST" \
    --argjson rpc_port "$RPC_PORT" \
    --arg rpc_user "$RPC_USER" \
    --arg rpc_password "$RPC_PASSWORD" \
    '.dbsettings.user = $mongo_user
     | .dbsettings.password = $mongo_password
     | .dbsettings.database = $mongo_database
     | .dbsettings.address = $mongo_address
     | .dbsettings.port = $mongo_port
     | .wallet.host = $rpc_host
     | .wallet.port = $rpc_port
     | .wallet.username = $rpc_user
     | .wallet.password = $rpc_password' \
    "$APP_DIR/settings.json" > "$SETTINGS_TMP" || {
      rm -f "$SETTINGS_TMP"
      die "Unable to update settings.json with jq."
    }
  jq empty "$SETTINGS_TMP" || {
    rm -f "$SETTINGS_TMP"
    die "Generated settings.json is not valid JSON."
  }
  install -m 0600 -o "$APP_USER" -g "$APP_USER" "$SETTINGS_TMP" "$APP_DIR/settings.json"
  rm -f "$SETTINGS_TMP"
fi

cat > "$APP_DIR/.installer.env" <<EOF_ENV
RPC_HOST=$RPC_HOST
RPC_PORT=$RPC_PORT
RPC_USER=$RPC_USER
RPC_PASSWORD=$RPC_PASSWORD
APP_PORT=$APP_PORT
DOMAIN=$DOMAIN
MONGO_USER=$MONGO_USER
MONGO_PASSWORD=$MONGO_PASSWORD
MONGO_URI=$MONGO_URI
YERBAS_VERSION=${YERBAS_VERSION:-unknown}
EOF_ENV
chmod 600 "$APP_DIR/.installer.env"
chown "$APP_USER:$APP_USER" "$APP_DIR/.installer.env"

cat > "$APP_DIR/ecosystem.config.cjs" <<EOF_PM2
module.exports = {
  apps: [{
    name: '${APP_NAME}',
    cwd: '${APP_DIR}',
    script: './bin/instance',
    instances: 1,
    exec_mode: 'fork',
    node_args: '--stack-size=10000',
    max_memory_restart: '1500M',
    restart_delay: 5000,
    max_restarts: 20,
    time: true,
    env: {
      NODE_ENV: 'production',
      RPC_HOST: '${RPC_HOST}',
      RPC_PORT: '${RPC_PORT}',
      RPC_USER: '${RPC_USER}',
      RPC_PASSWORD: '${RPC_PASSWORD}',
      MONGO_URI: '${MONGO_URI}'
    }
  }]
};
EOF_PM2
chown "$APP_USER:$APP_USER" "$APP_DIR/ecosystem.config.cjs"
chmod 600 "$APP_DIR/ecosystem.config.cjs"

info "Configuring PM2 startup"
PM2_HOME_DIR="/home/${APP_USER}/.pm2"
sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="$PM2_HOME_DIR" pm2 delete "$APP_NAME" >/dev/null 2>&1 || true
sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="$PM2_HOME_DIR" bash -lc "cd '$APP_DIR' && pm2 start ecosystem.config.cjs"
sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="$PM2_HOME_DIR" pm2 save
PM2_BIN="$(command -v pm2)"
cat > /etc/systemd/system/pm2-${APP_USER}.service <<EOF_PM2_SERVICE
[Unit]
Description=PM2 process manager for ${APP_USER}
After=network.target mongod.service yerbasd.service
Requires=mongod.service yerbasd.service

[Service]
Type=forking
User=${APP_USER}
Environment=HOME=/home/${APP_USER}
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PM2_HOME=${PM2_HOME_DIR}
PIDFile=${PM2_HOME_DIR}/pm2.pid
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Restart=on-failure
ExecStart=${PM2_BIN} resurrect
ExecReload=${PM2_BIN} reload all
ExecStop=${PM2_BIN} kill

[Install]
WantedBy=multi-user.target
EOF_PM2_SERVICE
systemctl daemon-reload
systemctl disable --now "pm2-${APP_USER}" >/dev/null 2>&1 || true
sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="$PM2_HOME_DIR" pm2 kill >/dev/null 2>&1 || true
rm -f "${PM2_HOME_DIR}/pm2.pid"
systemctl enable --now "pm2-${APP_USER}"
systemctl is-active --quiet "pm2-${APP_USER}" || die "PM2 systemd service failed. Check: journalctl -u pm2-${APP_USER} -n 100"

info "Configuring Nginx"
SERVER_NAME="${DOMAIN:-_}"
cat > /etc/nginx/sites-available/yerb-multi-explorer <<EOF_NGINX
limit_req_zone \$binary_remote_addr zone=yerb_api:10m rate=20r/s;

server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAME};
    client_max_body_size 10m;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 15s;
        proxy_read_timeout 90s;
    }

    location /ext/ {
        limit_req zone=yerb_api burst=40 nodelay;
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
}
EOF_NGINX
ln -sfn /etc/nginx/sites-available/yerb-multi-explorer /etc/nginx/sites-enabled/yerb-multi-explorer
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

info "Configuring firewall and security updates"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
systemctl enable --now unattended-upgrades

if [[ -n "$DOMAIN" && "$ENABLE_SSL" =~ ^(y|yes)$ ]]; then
  info "Requesting Let's Encrypt certificate"
  certbot --nginx --non-interactive --agree-tos --redirect --register-unsafely-without-email -d "$DOMAIN" || warn "SSL setup failed. Verify DNS and retry: sudo certbot --nginx -d $DOMAIN"
fi

install -m 0755 "$APP_DIR/installer/update.sh" /usr/local/sbin/yerb-explorer-update 2>/dev/null || true
install -m 0755 "$APP_DIR/installer/healthcheck.sh" /usr/local/sbin/yerb-explorer-health 2>/dev/null || true
install -m 0755 "$APP_DIR/installer/uninstall.sh" /usr/local/sbin/yerb-explorer-uninstall 2>/dev/null || true
install -m 0755 "$APP_DIR/installer/install-yerbas-core.sh" /usr/local/sbin/yerbas-core-install 2>/dev/null || true

info "Running health checks"
systemctl is-active --quiet yerbasd || die "Yerbas Core is not running."
systemctl is-active --quiet mongod || die "MongoDB is not running."
systemctl is-active --quiet nginx || die "Nginx is not running."
systemctl is-active --quiet "pm2-${APP_USER}" || die "PM2 systemd service is not running."
mongosh "$MONGO_URI" --quiet --eval 'if (db.runCommand({ ping: 1 }).ok !== 1) quit(1)' || die "MongoDB authenticated connection failed."

info "Waiting for explorer HTTP service"
EXPLORER_READY=false
for _ in $(seq 1 60); do
  if curl -fsS --max-time 5 "http://127.0.0.1:${APP_PORT}/" >/dev/null 2>&1; then
    EXPLORER_READY=true
    break
  fi
  if ! sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="$PM2_HOME_DIR" \
      pm2 describe "$APP_NAME" 2>/dev/null | grep -q 'online'; then
    break
  fi
  sleep 2
done
if [[ "$EXPLORER_READY" != true ]]; then
  sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="$PM2_HOME_DIR" pm2 status || true
  sudo -u "$APP_USER" env HOME="/home/$APP_USER" PM2_HOME="$PM2_HOME_DIR" \
    pm2 logs "$APP_NAME" --lines 100 --nostream || true
  die "Explorer failed to start on port ${APP_PORT}."
fi
ok "Yerbas Core is running"
ok "MongoDB authenticated connection is working"
ok "Nginx is running"
ok "Explorer is online and responding"

printf '\nInstallation complete.\n'
printf 'Application directory: %s\n' "$APP_DIR"
printf 'Yerbas Core: %s, native yerbasd service\n' "${YERBAS_VERSION:-installed}"
printf 'Yerbas data directory: /var/lib/yerbas/.yerbas\n'
printf 'Yerbas RPC: 127.0.0.1:%s\n' "$RPC_PORT"
printf 'MongoDB: authenticated user %s on 127.0.0.1:27017/%s\n' "$MONGO_USER" "$MONGO_DB"
printf 'PM2 logs: sudo -u %s PM2_HOME=/home/%s/.pm2 pm2 logs %s\n' "$APP_USER" "$APP_USER" "$APP_NAME"
printf 'Wallet status: sudo systemctl status yerbasd --no-pager\n'
printf 'Wallet sync: sudo -u yerbas yerbas-cli -conf=/var/lib/yerbas/.yerbas/yerbas.conf -datadir=/var/lib/yerbas/.yerbas getblockchaininfo\n'
printf 'Health check: sudo yerb-explorer-health\n'
printf 'Update: sudo yerb-explorer-update\n'
if [[ -n "$DOMAIN" ]]; then printf 'Explorer URL: http%s://%s\n' "$([[ "$ENABLE_SSL" =~ ^(y|yes)$ ]] && echo s)" "$DOMAIN"; else printf 'Explorer URL: http://SERVER_IP\n'; fi
