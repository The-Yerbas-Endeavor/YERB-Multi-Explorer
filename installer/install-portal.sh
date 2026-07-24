#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="${REPOSITORY:-The-Yerbas-Endeavor/YERB-Multi-Explorer}"
BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-explorer2.yerbas.org}"
ENABLE_SSL="${ENABLE_SSL:-yes}"
INSTALL_BOOTSTRAP="${INSTALL_BOOTSTRAP:-yes}"
KEEP_BOOTSTRAP_ARCHIVE="${KEEP_BOOTSTRAP_ARCHIVE:-no}"
WORK_ROOT="${WORK_ROOT:-/var/tmp/yerbas-portal-installer}"
MIN_DISK_GB="${MIN_DISK_GB:-45}"
MIN_MEMORY_MB="${MIN_MEMORY_MB:-1900}"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -ne 0 ]] || die "Run this as your normal sudo-enabled user, not root and not with sudo."
for command_name in sudo curl tar openssl awk df uname; do
  command -v "$command_name" >/dev/null 2>&1 || die "Required command is missing: $command_name"
done
[[ -r /etc/os-release ]] || die "/etc/os-release is missing."

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || \
  die "Ubuntu 24.04 LTS is required. Detected: ${PRETTY_NAME:-unknown}."

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
  amd64|arm64|x86_64|aarch64) ;;
  *) die "Unsupported architecture: $ARCH" ;;
esac

KERNEL_RELEASE="$(uname -r)"
KERNEL_VERSION="${KERNEL_RELEASE%%-*}"
if command -v dpkg >/dev/null 2>&1 && dpkg --compare-versions "$KERNEL_VERSION" ge 6.19; then
  die "Kernel ${KERNEL_VERSION} is incompatible with MongoDB 8. Use Ubuntu 24.04 with a kernel older than 6.19."
fi

AVAILABLE_GB="$(df -Pk /var/tmp | awk 'NR==2 {print int($4/1024/1024)}')"
MEMORY_MB="$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)"
(( AVAILABLE_GB >= MIN_DISK_GB )) || \
  die "At least ${MIN_DISK_GB} GB free is required; ${AVAILABLE_GB} GB is available."
if (( MEMORY_MB < MIN_MEMORY_MB )); then
  warn "Only ${MEMORY_MB} MB RAM is available. Installation may work, but 4 GB or more is recommended."
fi

[[ "$DOMAIN" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]] || die "Invalid domain: $DOMAIN"
[[ "$ENABLE_SSL" =~ ^(y|yes|n|no)$ ]] || die "ENABLE_SSL must be yes or no."

printf '\n==============================================================\n'
printf '             Official Yerbas Portal Installer\n'
printf '==============================================================\n\n'
printf 'Operating system : %s\n' "$PRETTY_NAME"
printf 'Kernel           : %s\n' "$KERNEL_RELEASE"
printf 'Architecture     : %s\n' "$ARCH"
printf 'Free disk        : %s GB\n' "$AVAILABLE_GB"
printf 'Memory           : %s MB\n' "$MEMORY_MB"
printf 'Portal domain    : %s\n' "$DOMAIN"
printf 'Source branch    : %s\n' "$BRANCH"
printf 'HTTPS            : %s\n\n' "$ENABLE_SSL"

info "Checking sudo access"
sudo -v || die "This account does not have working sudo privileges."

sudo install -d -m 1777 "$WORK_ROOT"
TMP_DIR="$(mktemp -d "$WORK_ROOT/download.XXXXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

ARCHIVE="$TMP_DIR/source.tar.gz"
SOURCE_DIR="$TMP_DIR/source"
ANSWERS="$TMP_DIR/answers.txt"
mkdir -p "$SOURCE_DIR"

info "Downloading ${REPOSITORY}:${BRANCH}"
curl -fL --retry 5 --retry-delay 3 \
  "https://github.com/${REPOSITORY}/archive/refs/heads/${BRANCH}.tar.gz" \
  -o "$ARCHIVE"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$SOURCE_DIR"

for required_file in install-sudo-user.sh install.sh install-yerbas-core.sh jsonc-to-json.py; do
  [[ -f "$SOURCE_DIR/installer/$required_file" ]] || die "Downloaded source is missing installer/$required_file"
done
chmod +x "$SOURCE_DIR/installer/install-sudo-user.sh"

RPC_USER="${RPC_USER:-yerbasrpc}"
RPC_PASSWORD="${RPC_PASSWORD:-$(openssl rand -hex 32)}"
MONGO_PASSWORD="${MONGO_PASSWORD:-$(openssl rand -hex 32)}"

printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "$DOMAIN" "$RPC_USER" "$RPC_PASSWORD" "$RPC_PASSWORD" \
  "$MONGO_PASSWORD" "$MONGO_PASSWORD" "$ENABLE_SSL" > "$ANSWERS"
chmod 0600 "$ANSWERS"

info "Installing Core, bootstrap, MongoDB, Portal, PM2, Nginx, firewall, and HTTPS"
export BRANCH INSTALL_BOOTSTRAP KEEP_BOOTSTRAP_ARCHIVE
export INSTALLER_WORK_ROOT="$WORK_ROOT"
(
  cd "$SOURCE_DIR"
  bash installer/install-sudo-user.sh < "$ANSWERS"
)

PUBLIC_URL="http://${DOMAIN}"
[[ "$ENABLE_SSL" =~ ^(y|yes)$ ]] && PUBLIC_URL="https://${DOMAIN}"

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
printf 'Restricted credential files:\n'
printf '  /etc/yerbas/explorer.env\n'
printf '  /opt/yerb-multi-explorer/.installer.env\n\n'
ok "The official Yerbas Portal installation finished successfully."
