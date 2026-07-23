#!/usr/bin/env bash
set -Eeuo pipefail
APP_USER="yerbexplorer"
APP_NAME="yerb-multi-explorer"
APP_DIR="/opt/yerb-multi-explorer"
[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
read -r -p "Remove YERB Multi-Explorer services and files? [y/N]: " answer
[[ "${answer,,}" =~ ^(y|yes)$ ]] || exit 0
sudo -u "$APP_USER" env HOME="/home/$APP_USER" pm2 delete "$APP_NAME" >/dev/null 2>&1 || true
sudo -u "$APP_USER" env HOME="/home/$APP_USER" pm2 save >/dev/null 2>&1 || true
systemctl disable --now "pm2-${APP_USER}" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/pm2-${APP_USER}.service"
rm -f /etc/nginx/sites-enabled/yerb-multi-explorer /etc/nginx/sites-available/yerb-multi-explorer
nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
read -r -p "Also purge native MongoDB packages and delete /var/lib/mongodb? [y/N]: " delete_db
if [[ "${delete_db,,}" =~ ^(y|yes)$ ]]; then
  systemctl disable --now mongod >/dev/null 2>&1 || true
  apt-get purge -y 'mongodb-org*' || true
  rm -rf /var/lib/mongodb /var/log/mongodb
  rm -f /etc/apt/sources.list.d/mongodb-org-*.list /etc/apt/keyrings/mongodb-server-*.gpg
fi
rm -rf "$APP_DIR"
rm -f /usr/local/sbin/yerb-explorer-update /usr/local/sbin/yerb-explorer-health /usr/local/sbin/yerb-explorer-uninstall
systemctl daemon-reload
userdel -r "$APP_USER" >/dev/null 2>&1 || true
echo "YERB Multi-Explorer removed. Nginx, Node.js, PM2, and firewall packages were left installed."
