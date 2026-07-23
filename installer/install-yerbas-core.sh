#!/usr/bin/env bash
set -Eeuo pipefail

YERBAS_USER="${YERBAS_USER:-yerbas}"
YERBAS_HOME="${YERBAS_HOME:-/var/lib/yerbas}"
YERBAS_DATADIR="${YERBAS_DATADIR:-${YERBAS_HOME}/.yerbas}"
YERBAS_CONF="${YERBAS_CONF:-${YERBAS_DATADIR}/yerbas.conf}"
YERBAS_RPC_PORT="${YERBAS_RPC_PORT:-9998}"
YERBAS_RELEASE_API="https://api.github.com/repos/The-Yerbas-Endeavor/yerbas/releases/latest"
YERBAS_ENV_FILE="/etc/yerbas/explorer.env"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "Run this installer as root."
for command_name in curl jq tar find install openssl systemctl; do
  command -v "$command_name" >/dev/null 2>&1 || die "Required command is missing: $command_name"
done

case "$(dpkg --print-architecture)" in
  amd64) ARCH_REGEX='(x86_64|amd64)' ;;
  arm64) ARCH_REGEX='(aarch64|arm64)' ;;
  *) die "Unsupported architecture: $(dpkg --print-architecture)" ;;
esac

info "Finding latest Yerbas Core release"
RELEASE_JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$YERBAS_RELEASE_API")"
YERBAS_VERSION="$(jq -r '.tag_name // empty' <<<"$RELEASE_JSON")"
[[ -n "$YERBAS_VERSION" ]] || die "GitHub did not return a published Yerbas release."

ASSET_URL="$(jq -r '.assets[].browser_download_url' <<<"$RELEASE_JSON" \
  | grep -Ei "$ARCH_REGEX" \
  | grep -Ei 'linux|ubuntu' \
  | grep -Eiv 'debug|symbols|source|src|checksum|sha256|qt|windows|win|mac|darwin' \
  | grep -Ei '\.(tar\.gz|tgz|tar\.xz|zip)$' \
  | head -n 1 || true)"

if [[ -z "$ASSET_URL" ]]; then
  ASSET_URL="$(jq -r '.assets[].browser_download_url' <<<"$RELEASE_JSON" \
    | grep -Ei "$ARCH_REGEX" \
    | grep -Eiv 'debug|symbols|source|src|checksum|sha256|windows|win|mac|darwin' \
    | grep -Ei '\.(tar\.gz|tgz|tar\.xz|zip)$' \
    | head -n 1 || true)"
fi

[[ -n "$ASSET_URL" ]] || {
  jq -r '.assets[].name' <<<"$RELEASE_JSON" >&2
  die "No suitable Linux Yerbas release archive was found for $(dpkg --print-architecture)."
}

info "Installing Yerbas Core ${YERBAS_VERSION}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ARCHIVE_PATH="$TMP_DIR/$(basename "${ASSET_URL%%\?*}")"
curl -fL --retry 3 --retry-delay 2 -o "$ARCHIVE_PATH" "$ASSET_URL"

case "$ARCHIVE_PATH" in
  *.tar.gz|*.tgz) tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR" ;;
  *.tar.xz) tar -xJf "$ARCHIVE_PATH" -C "$TMP_DIR" ;;
  *.zip)
    command -v unzip >/dev/null 2>&1 || die "unzip is required for the selected release archive."
    unzip -q "$ARCHIVE_PATH" -d "$TMP_DIR"
    ;;
  *) die "Unsupported Yerbas release archive: $ARCHIVE_PATH" ;;
esac

YERBASD_PATH="$(find "$TMP_DIR" -type f -name yerbasd -perm -u+x | head -n 1 || true)"
YERBAS_CLI_PATH="$(find "$TMP_DIR" -type f -name yerbas-cli -perm -u+x | head -n 1 || true)"
[[ -n "$YERBASD_PATH" && -n "$YERBAS_CLI_PATH" ]] || die "The release archive does not contain executable yerbasd and yerbas-cli binaries."

install -m 0755 "$YERBASD_PATH" /usr/local/bin/yerbasd
install -m 0755 "$YERBAS_CLI_PATH" /usr/local/bin/yerbas-cli

id -u "$YERBAS_USER" >/dev/null 2>&1 || useradd --system --home-dir "$YERBAS_HOME" --create-home --shell /usr/sbin/nologin "$YERBAS_USER"
install -d -m 0750 -o "$YERBAS_USER" -g "$YERBAS_USER" "$YERBAS_DATADIR"
install -d -m 0750 /etc/yerbas

if [[ -f "$YERBAS_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$YERBAS_ENV_FILE"
fi
RPC_USER="${RPC_USER:-explorer_$(openssl rand -hex 8)}"
RPC_PASSWORD="${RPC_PASSWORD:-$(openssl rand -hex 32)}"
RPC_PORT="${RPC_PORT:-$YERBAS_RPC_PORT}"

cat > "$YERBAS_CONF" <<EOF
server=1
daemon=0
listen=1
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=${RPC_PORT}
rpcuser=${RPC_USER}
rpcpassword=${RPC_PASSWORD}
txindex=1
addressindex=1
timestampindex=1
spentindex=1
EOF
chmod 0600 "$YERBAS_CONF"
chown "$YERBAS_USER:$YERBAS_USER" "$YERBAS_CONF"

cat > "$YERBAS_ENV_FILE" <<EOF
RPC_HOST=127.0.0.1
RPC_PORT=${RPC_PORT}
RPC_USER=${RPC_USER}
RPC_PASSWORD=${RPC_PASSWORD}
YERBAS_VERSION=${YERBAS_VERSION}
YERBAS_DATADIR=${YERBAS_DATADIR}
YERBAS_CONF=${YERBAS_CONF}
EOF
chmod 0600 "$YERBAS_ENV_FILE"

cat > /etc/systemd/system/yerbasd.service <<EOF
[Unit]
Description=Yerbas Core daemon
Documentation=https://github.com/The-Yerbas-Endeavor/yerbas
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${YERBAS_USER}
Group=${YERBAS_USER}
ExecStart=/usr/local/bin/yerbasd -conf=${YERBAS_CONF} -datadir=${YERBAS_DATADIR} -printtoconsole
ExecStop=/usr/local/bin/yerbas-cli -conf=${YERBAS_CONF} -datadir=${YERBAS_DATADIR} stop
Restart=on-failure
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=180
LimitNOFILE=65536
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now yerbasd
systemctl is-active --quiet yerbasd || die "Yerbas Core failed to start. Check: journalctl -u yerbasd -n 100 --no-pager -l"

info "Waiting for Yerbas RPC"
RPC_READY=false
for _ in $(seq 1 60); do
  if sudo -u "$YERBAS_USER" /usr/local/bin/yerbas-cli -conf="$YERBAS_CONF" -datadir="$YERBAS_DATADIR" getblockchaininfo >/dev/null 2>&1; then
    RPC_READY=true
    break
  fi
  sleep 2
done

if [[ "$RPC_READY" == true ]]; then
  ok "Yerbas Core ${YERBAS_VERSION} is running and RPC is ready"
else
  warn "Yerbas Core is running but RPC is not ready yet; initial startup or synchronization may still be in progress."
fi

printf '%s\n' "$YERBAS_ENV_FILE"
