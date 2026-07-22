#!/usr/bin/env bash
set -Eeuo pipefail

# YERB Multi-Explorer native installer for Ubuntu 26 Server.
#
# Non-interactive example:
#   sudo env \
#     DOMAIN=explorer.example.org \
#     YERB_RPC_USER=explorer \
#     YERB_RPC_PASSWORD='replace-me' \
#     MONGODB_URI='mongodb://127.0.0.1:27017/yerbas_explorer' \
#     ENABLE_HTTPS=1 \
#     bash scripts/install-ubuntu26.sh

readonly REPO_URL="${REPO_URL:-https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git}"
readonly REPO_BRANCH="${REPO_BRANCH:-main}"
readonly APP_USER="${APP_USER:-yerbexplorer}"
readonly APP_GROUP="${APP_GROUP:-$APP_USER}"
readonly APP_HOME="${APP_HOME:-/home/$APP_USER}"
readonly INSTALL_DIR="${INSTALL_DIR:-/var/www/yerb-explorer}"
readonly API_HOST="${API_HOST:-127.0.0.1}"
readonly API_PORT="${API_PORT:-3001}"
readonly REDIS_URL="${REDIS_URL:-redis://127.0.0.1:6379}"
readonly YERB_RPC_URL="${YERB_RPC_URL:-http://127.0.0.1:8766}"
readonly SYNC_BATCH_SIZE="${SYNC_BATCH_SIZE:-25}"
readonly ENABLE_HTTPS="${ENABLE_HTTPS:-0}"
readonly CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
readonly SKIP_TYPECHECK="${SKIP_TYPECHECK:-0}"

DOMAIN="${DOMAIN:-}"
MONGODB_URI="${MONGODB_URI:-mongodb://127.0.0.1:27017/yerbas_explorer}"
YERB_RPC_USER="${YERB_RPC_USER:-}"
YERB_RPC_PASSWORD="${YERB_RPC_PASSWORD:-}"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

on_error() {
  local exit_code=$?
  printf '\n\033[1;31mInstallation failed near line %s (exit %s).\033[0m\n' "${BASH_LINENO[0]}" "$exit_code" >&2
  printf 'Review: journalctl -u nginx --no-pager -n 100\n' >&2
  printf 'Review: sudo -iu %s pm2 logs --lines 100\n' "$APP_USER" >&2
  exit "$exit_code"
}
trap on_error ERR

require_root() {
  [[ ${EUID} -eq 0 ]] || die "Run this installer with sudo or as root."
}

check_platform() {
  [[ -r /etc/os-release ]] || die "Unable to identify the operating system."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == "ubuntu" ]] || die "This installer supports Ubuntu Server only."
  [[ ${VERSION_ID:-} == 26.* ]] || die "Ubuntu 26.x is required; detected ${PRETTY_NAME:-unknown}."
  case "$(dpkg --print-architecture)" in
    amd64|arm64) ;;
    *) die "Only amd64 and arm64 are supported." ;;
  esac
}

prompt_if_needed() {
  if [[ -t 0 ]]; then
    if [[ -z "$DOMAIN" ]]; then
      read -r -p "Explorer domain (for example explorer.yerbas.org): " DOMAIN
    fi
    if [[ -z "$YERB_RPC_USER" ]]; then
      read -r -p "Yerbas RPC username: " YERB_RPC_USER
    fi
    if [[ -z "$YERB_RPC_PASSWORD" ]]; then
      read -r -s -p "Yerbas RPC password: " YERB_RPC_PASSWORD
      printf '\n'
    fi
    read -r -p "MongoDB URI [$MONGODB_URI]: " input_mongodb
    MONGODB_URI="${input_mongodb:-$MONGODB_URI}"
  fi

  [[ -n "$DOMAIN" ]] || die "DOMAIN is required. Pass DOMAIN=explorer.example.org."
  [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "DOMAIN contains unsupported characters."
  [[ -n "$YERB_RPC_USER" ]] || die "YERB_RPC_USER is required."
  [[ -n "$YERB_RPC_PASSWORD" ]] || die "YERB_RPC_PASSWORD is required."
  [[ "$API_PORT" =~ ^[0-9]+$ ]] || die "API_PORT must be numeric."
  [[ "$SYNC_BATCH_SIZE" =~ ^[0-9]+$ ]] || die "SYNC_BATCH_SIZE must be numeric."
}

install_system_packages() {
  log "Updating Ubuntu and installing system packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates curl git gnupg sudo build-essential \
    nginx redis-server lsb-release certbot python3-certbot-nginx

  systemctl enable --now redis-server nginx
  redis-cli ping | grep -qx PONG || die "Redis did not return PONG."
}

install_node() {
  local install_node=1
  if command -v node >/dev/null 2>&1; then
    [[ "$(node --version)" == v22.* ]] && install_node=0
  fi

  if [[ $install_node -eq 1 ]]; then
    log "Installing Node.js 22"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  fi

  [[ "$(node --version)" == v22.* ]] || die "Node.js 22 is required; detected $(node --version)."
  npm install --global pm2
}

create_app_user() {
  log "Creating the dedicated explorer account"
  if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd --create-home --home-dir "$APP_HOME" --shell /bin/bash "$APP_USER"
  fi
  install -d -o "$APP_USER" -g "$APP_GROUP" -m 0755 "$INSTALL_DIR"
}

deploy_source() {
  log "Cloning or updating YERB Multi-Explorer"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    sudo -u "$APP_USER" git -C "$INSTALL_DIR" fetch --prune origin
    sudo -u "$APP_USER" git -C "$INSTALL_DIR" checkout "$REPO_BRANCH"
    sudo -u "$APP_USER" git -C "$INSTALL_DIR" reset --hard "origin/$REPO_BRANCH"
  elif [[ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    die "$INSTALL_DIR is not empty and is not a Git checkout."
  else
    sudo -u "$APP_USER" git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
}

write_environment() {
  log "Writing the production environment"
  local cors_origin="https://$DOMAIN"
  [[ "$ENABLE_HTTPS" == "1" ]] || cors_origin="http://$DOMAIN"

  install -o "$APP_USER" -g "$APP_GROUP" -m 0600 /dev/null "$INSTALL_DIR/.env"
  cat > "$INSTALL_DIR/.env" <<EOF
NODE_ENV=production
API_HOST=$API_HOST
API_PORT=$API_PORT

MONGODB_URI=$MONGODB_URI
REDIS_URL=$REDIS_URL

YERB_RPC_URL=$YERB_RPC_URL
YERB_RPC_USER=$YERB_RPC_USER
YERB_RPC_PASSWORD=$YERB_RPC_PASSWORD

SYNC_BATCH_SIZE=$SYNC_BATCH_SIZE
CORS_ORIGIN=$cors_origin
EOF
  chown "$APP_USER:$APP_GROUP" "$INSTALL_DIR/.env"
  chmod 0600 "$INSTALL_DIR/.env"
}

build_application() {
  log "Installing dependencies and building the explorer"
  sudo -u "$APP_USER" -H bash -lc "cd '$INSTALL_DIR' && npm ci"
  if [[ "$SKIP_TYPECHECK" != "1" ]]; then
    sudo -u "$APP_USER" -H bash -lc "cd '$INSTALL_DIR' && npm run typecheck"
  fi
  sudo -u "$APP_USER" -H bash -lc "cd '$INSTALL_DIR' && npm run build"
  [[ -f "$INSTALL_DIR/apps/api/dist/server.js" ]] || die "API build output is missing."
  [[ -f "$INSTALL_DIR/apps/web/dist/index.html" ]] || die "Web build output is missing."
}

configure_pm2() {
  log "Starting the API and indexer with PM2"
  sudo -u "$APP_USER" -H bash -lc "cd '$INSTALL_DIR' && pm2 delete yerb-explorer-api yerb-explorer-indexer >/dev/null 2>&1 || true"
  sudo -u "$APP_USER" -H bash -lc "cd '$INSTALL_DIR' && pm2 start ecosystem.config.cjs --update-env"
  sudo -u "$APP_USER" -H pm2 save

  env PATH="$PATH:/usr/bin:/usr/local/bin" pm2 startup systemd -u "$APP_USER" --hp "$APP_HOME" >/dev/null
  systemctl daemon-reload
  systemctl enable "pm2-$APP_USER"
  systemctl restart "pm2-$APP_USER"
}

configure_nginx() {
  log "Configuring Nginx for $DOMAIN"
  cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;
    root $INSTALL_DIR/apps/web/dist;
    index index.html;

    client_max_body_size 2m;

    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /socket.io/ {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /docs {
        proxy_pass http://127.0.0.1:$API_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

  ln -sfn "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx
}

configure_https() {
  [[ "$ENABLE_HTTPS" == "1" ]] || return 0
  log "Requesting a Let's Encrypt certificate"

  local certbot_args=(--nginx --non-interactive --agree-tos --redirect -d "$DOMAIN")
  if [[ -n "$CERTBOT_EMAIL" ]]; then
    certbot_args+=(--email "$CERTBOT_EMAIL")
  else
    certbot_args+=(--register-unsafely-without-email)
  fi
  certbot "${certbot_args[@]}"
  certbot renew --dry-run
}

verify_installation() {
  log "Verifying services"
  systemctl is-active --quiet redis-server || die "Redis is not active."
  systemctl is-active --quiet nginx || die "Nginx is not active."
  systemctl is-active --quiet "pm2-$APP_USER" || die "PM2 startup service is not active."

  local api_url="http://127.0.0.1:$API_PORT/api/v1/health"
  local attempts=30
  until curl --fail --silent --show-error "$api_url" >/tmp/yerb-explorer-health.json; do
    attempts=$((attempts - 1))
    [[ $attempts -gt 0 ]] || {
      sudo -u "$APP_USER" -H pm2 logs --lines 100 --nostream || true
      die "The API did not become healthy. Verify MongoDB and Yerbas RPC connectivity."
    }
    sleep 2
  done

  cat /tmp/yerb-explorer-health.json
  printf '\n'
}

print_summary() {
  local scheme=http
  [[ "$ENABLE_HTTPS" == "1" ]] && scheme=https

  log "Installation complete"
  cat <<EOF
Explorer:        $scheme://$DOMAIN
API health:      $scheme://$DOMAIN/api/v1/health
API docs:        $scheme://$DOMAIN/docs
Install path:    $INSTALL_DIR
Service account: $APP_USER

Useful commands:
  sudo -iu $APP_USER pm2 status
  sudo -iu $APP_USER pm2 logs --lines 100
  sudo nginx -t
  sudo systemctl status nginx redis-server pm2-$APP_USER
EOF
}

main() {
  require_root
  check_platform
  prompt_if_needed
  install_system_packages
  install_node
  create_app_user
  deploy_source
  write_environment
  build_application
  configure_pm2
  configure_nginx
  configure_https
  verify_installation
  print_summary
}

main "$@"
