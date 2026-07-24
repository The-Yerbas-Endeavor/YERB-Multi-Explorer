#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="${REPOSITORY:-The-Yerbas-Endeavor/YERB-Multi-Explorer}"
BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-explorer2.yerbas.org}"
ENABLE_SSL="${ENABLE_SSL:-yes}"
INSTALL_BOOTSTRAP="${INSTALL_BOOTSTRAP:-yes}"
KEEP_BOOTSTRAP_ARCHIVE="${KEEP_BOOTSTRAP_ARCHIVE:-no}"
INSTALL_ROOT="${INSTALL_ROOT:-/var/tmp/yerbas-portal-installer}"
MIN_DISK_GB="${MIN_DISK_GB:-45}"
MIN_MEMORY_MB="${MIN_MEMORY_MB:-1900}"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -ne 0 ]] || die "Run this installer as your normal sudo-enabled user, not as root and not with sudo."
command -v sudo >/dev/null 2>&1 || die "sudo is required."
command -v curl >/dev/null 2>&1 || die "curl is required."
command -v tar >/dev/null 2>&1 || die "tar is required."
command -v openssl >/dev/null 2>&1 || die "openssl is required."
[[ -r /etc/os-release ]] || die "/etc/os-release is missing."

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] || \
  die "The automatic Yerbas Portal installer requires Ubuntu 24.04 LTS. Detected: ${PRETTY_NAME:-unknown}."

case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
  amd64|arm64|x86_64|aarch64) ;;
  *) die "Unsupported architecture: $(uname -m)" ;;
esac

AVAILABLE_GB="$(df -Pk /var/tmp | awk 'NR==2 {print int($4/1024/1024)}')"
MEMORY_MB="$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)"
(( AVAILABLE_GB >= MIN_DISK_GB )) || die "At least ${MIN_DISK_GB} GB free is required on the root filesystem; ${AVAILABLE_GB} GB is available."
if (( MEMORY_MB < MIN_MEMORY_MB )); then
  warn "Only ${A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]] || die "Invalid DOMAIN value: $DOMAIN"
[[ "$ENABLE_SSL" =~ ^(y|yes|n|no)$ ]] || die "ENABLE_SSL must be yes or no."

printf '\n==============================================================\n'
printf '             Official Yerbas Portal Installer\n'
printf '==============================================================\n\n'
printf 'Operating system : %s\n' "${PRETTY_NAME}"
printf 'Kernel           : %s\n' "$KERNEL_VERSION"
printf 'Architecture     : %s\n' "$(dpkg --print-architecture)"
printf 'Portal domain    : %s\n' "$DOMAIN"
printf 'Source branch    : %s\n' "$BRANCH"
printf 'Blockchain data : bootstrap-index enabled\n'
printf 'TLS certificate  : %s\n\n' "$ENABLE_SSL"

info "Checking sudo access"
sudo -v || die "This account does not have working sudo privileges."

sudo install -d -m 1777 "$WORK_ROOT"
TMP_DIR="$(mktemp -d "$WORK_ROOT/download.XXXXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

ARCHIVE="$TMP_DIR/source.tar.gz"
SOURCE_DIR="$TMP_DIR/source"
mkdir -p "$SOURCE_DIR"

info "Downloading Yerbas Portal source from ${REPOSITORY}:${BRANCH}"
curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/${REPOSITORY}/archive/refs/heads/${BRANCH}.tar.gz" \
  -o "$ARCHIVE"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$SOURCE_DIR"

[[ -x "$SOURCE_DIR/installer/install-sudo-user.sh" ]] || chmod +x "$SOURCE_DIR/installer/install-sudo-user.sh"
[[ -f "$SOURCE_DIR/installer/install.sh" ]] || die "Downloaded source does not contain installer/install.sh."
[[ -f "$SOURCE_DIR/installer/install-yerbas-core.sh" ]] || die "Downloaded source does not contain installer/install-yerbas-core.sh."

RPC_USER="${RPC_USER:-yerbasrpc}"
RPC_PASSWORD="${RPC_PASSWORD:-$(openssl rand -hex 32)}"
MONGO_PASSWORD="${MONGO_PASSWORD:-$(openssl rand -hex 32)}"

ANSWERS="$TMP_DIR/answers.txt"
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$DOMAIN" \
  "$RPC_USER" \
  "$RPC_PASSWORD" \
  "$RPC_PASSWORD" \
  "$MONGO_PASSWORD" \
  "$MONGO_PASSWORD" \
  "$ENABLE_SSL" > "$ANSWERS"
chmod 0600 "$ANSWERS"

info "Installing Yerbas Core, bootstrap, MongoDB, Portal, PM2, Nginx, firewall, and TLS"
export BRANCH INSTALL_BOOTSTRAP KEEP_BOOTSTRAP_ARCHIVE
export INSTALLER_WORK_ROOT="$WORK_ROOT"
(
  cd "$SOURCE_DIR"
  bash installer/install-sudo-user.sh < "$ANSWERS"
)

PORTAL_URL="http://${DOMAIN}"
[[ "$ENABLE_SSL" =~ ^(y|yes)$ ]] && PORTAL_URL="https://${DOMAIN}"

printf '\n==============================================================\n'
printf '              Yerbas Portal Installation Complete\n'
printf '==============================================================\n\n'
printf 'Portal URL      : %s\n' "$PORTAL_URL"
printf 'Application     : /opt/yerb-multi-explorer\n'
printf 'Core service    : yerbasd.service\n'
printf 'Database        =~ ^(y|yes|true|1)$ ]]; then
  PUBLIC_URL="https://${DOMAIN}"
fi

printf '\n==============================================================\n'
printf '             Yerbas Portal Installation Complete\n'
printf '==============================================================\n\n'
printf 'Portal URL       : %s\n' "$PUBLIC_URL"
printf 'Application      : /opt/yerb-multi-explorer\n'
printf 'Health check     : sudo yerb-explorer-health\n'
printf 'Update command   : sudo yerb-explorer-update\n'
printf 'Portal logs      : sudo -u yerbexplorer PM2_HOME=/home/yerbexplorer/.pm2 pm2 logs yerb-multi-explorer\n'
printf 'Core logs        : sudo journalctl -u yerbasd -f\n'
printf 'Install log      : /var/log/yerb-multi-explorer-install.log\n\n'
printf 'Credentials are stored with restricted permissions in:\n'
printf '  /etc/yerbas/explorer.env\n'
printf '  /opt/yerb-multi-explorer/.installer.env\n\n'

ok "The official Yerbas Portal installation finished successfully."
