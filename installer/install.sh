#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="yerb-multi-explorer"
APP_USER="yerbexplorer"
APP_DIR="/opt/yerb-multi-explorer"
REPO_URL="https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git"
BRANCH="${BRANCH:-main}"
APP_PORT="${APP_PORT:-3001}"
MONGO_CONTAINER="yerb-mongodb"
MONGO_VOLUME="yerb-mongodb-data"
LOG_FILE="/var/log/${APP_NAME}-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "[ERROR] Installation failed near line $LINENO. Review $LOG_FILE" >&2' ERR

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "Run this installer with sudo."
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only."
[[ "${VERSION_ID:-}" == "26.04" ]] || warn "Designed for Ubuntu 26.04; detected ${PRETTY_NAME:-unknown}."

read -r -p "Explorer domain (example: explorer.yerbas.org, blank for IP-only): " DOMAIN
read -r -p "Yerbas RPC host [127.0.0.1]: " RPC_HOST
RPC_HOST="${RPC_HOST:-127.0.0.1}"
read -r -p "Yerbas RPC port [8332]: " RPC_PORT
RPC_PORT="${RPC_PORT:-8332}"
read -r -p "Yerbas RPC username: " RPC_USER
read -r -s -p "Yerbas RPC password: " RPC_PASSWORD
echo
[[ -n "$RPC_USER" && -n "$RPC_PASSWORD" ]] || die "RPC username and password are required."
read -r -p "Install Let's Encrypt SSL when DNS is ready? [y/N]: " ENABLE_SSL
ENABLE_SSL="${ENABLE_SSL,,}"

info "Installing system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg git nginx ufw jq build-essential python3 docker.io unattended-upgrades certbot python3-certbot-nginx
systemctl enable --now docker nginx

info "Installing Node.js 22"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
node --version | grep -q '^v22\.' || die "Node.js 22 was not installed."
npm install -g pm2

info "Creating service account"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --create-home --home-dir "/home/$APP_USER" --shell /bin/bash "$APP_USER"
usermod -aG docker "$APP_USER"

info "Starting MongoDB 8 in a persistent local container"
docker volume inspect "$MONGO_VOLUME" >/dev/null 2>&1 || docker volume create "$MONGO_VOLUME" >/dev/null
if docker container inspect "$MONGO_CONTAINER" >/dev/null 2>&1; then
  docker start "$MONGO_CONTAINER" >/dev/null || true
else
  docker run -d --name "$MONGO_CONTAINER" --restart unless-stopped \
    -p 127.0.0.1:27017:27017 \
    -v "$MONGO_VOLUME:/data/db" mongo:8 >/dev/null
fi

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

info "Installing locked Node dependencies"
sudo -u "$APP_USER" bash -lc "cd '$APP_DIR' && npm ci"

if grep -q "app.get('\*'" "$APP_DIR/lib/nodeapi.js"; then
  warn "Applying Express 5-compatible wildcard route to lib/nodeapi.js"
  sed -i "s/app\.get('\*', hasAccess/app.get(\/\.\*\/, hasAccess/" "$APP_DIR/lib/nodeapi.js"
fi

info "Creating explorer configuration"
if [[ ! -f "$APP_DIR/settings.json" ]]; then
  if [[ -f "$APP_DIR/settings.json.template" ]]; then
    cp "$APP_DIR/settings.json.template" "$APP_DIR/settings.json"
  elif [[ -f "$APP_DIR/settings.json.example" ]]; then
    cp "$APP_DIR/settings.json.example" "$APP_DIR/settings.json"
  else
    warn "No settings template was found. The explorer will use defaults until settings.json is created."
  fi
fi

cat > "$APP_DIR/.installer.env" <<EOF
RPC_HOST=$RPC_HOST
RPC_PORT=$RPC_PORT
RPC_USER=$RPC_USER
RPC_PASSWORD=$RPC_PASSWORD
APP_PORT=$APP_PORT
DOMAIN=$DOMAIN
EOF
chmod 600 "$APP_DIR/.installer.env"
chown "$APP_USER:$APP_USER" "$APP_DIR/.installer.env"

cat > "$APP_DIR/ecosystem.config.cjs" <<EOF
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
    env: { NODE_ENV: 'production' }
  }]
};
EOF
chown "$APP_USER:$APP_USER" "$APP_DIR/ecosystem.config.cjs"

info "Configuring PM2 startup"
sudo -u "$APP_USER" env HOME="/home/$APP_USER" pm2 delete "$APP_NAME" >/dev/null 2>&1 || true
sudo -u "$APP_USER" env HOME="/home/$APP_USER" bash -lc "cd '$APP_DIR' && pm2 start ecosystem.config.cjs"
sudo -u "$APP_USER" env HOME="/home/$APP_USER" pm2 save
PM2_BIN="$(command -v pm2)"
cat > /etc/systemd/system/pm2-${APP_USER}.service <<EOF
[Unit]
Description=PM2 process manager for ${APP_USER}
After=network.target docker.service
Requires=docker.service

[Service]
Type=forking
User=${APP_USER}
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PM2_HOME=/home/${APP_USER}/.pm2
PIDFile=/home/${APP_USER}/.pm2/pm2.pid
Restart=on-failure
ExecStart=${PM2_BIN} resurrect
ExecReload=${PM2_BIN} reload all
ExecStop=${PM2_BIN} kill

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now "pm2-${APP_USER}"

info "Configuring Nginx"
SERVER_NAME="${DOMAIN:-_}"
cat > /etc/nginx/sites-available/yerb-multi-explorer <<EOF
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
EOF
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

info "Running health checks"
sleep 5
systemctl is-active --quiet docker && ok "Docker is running"
docker ps --format '{{.Names}}' | grep -qx "$MONGO_CONTAINER" && ok "MongoDB is running"
systemctl is-active --quiet nginx && ok "Nginx is running"
sudo -u "$APP_USER" env HOME="/home/$APP_USER" pm2 describe "$APP_NAME" >/dev/null && ok "Explorer is registered with PM2"

printf '\nInstallation complete.\n'
printf 'Application directory: %s\n' "$APP_DIR"
printf 'PM2 logs: sudo -u %s PM2_HOME=/home/%s/.pm2 pm2 logs %s\n' "$APP_USER" "$APP_USER" "$APP_NAME"
printf 'Health check: sudo yerb-explorer-health\n'
printf 'Update: sudo yerb-explorer-update\n'
if [[ -n "$DOMAIN" ]]; then printf 'Explorer URL: http%s://%s\n' "$([[ "$ENABLE_SSL" =~ ^(y|yes)$ ]] && echo s)" "$DOMAIN"; else printf 'Explorer URL: http://SERVER_IP\n'; fi
warn "Review $APP_DIR/settings.json and enter the RPC/database values expected by this explorer version before indexing."
