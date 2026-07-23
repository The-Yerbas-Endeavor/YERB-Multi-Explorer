#!/usr/bin/env bash
set -Eeuo pipefail

YERBAS_USER="${YERBAS_USER:-yerbas}"
YERBAS_HOME="${YERBAS_HOME:-/var/lib/yerbas}"
YERBAS_DATADIR="${YERBAS_DATADIR:-${YERBAS_HOME}/.yerbas}"
YERBAS_CONF="${YERBAS_CONF:-${YERBAS_DATADIR}/yerbas.conf}"
YERBAS_RPC_PORT="${YERBAS_RPC_PORT:-9998}"
YERBAS_RELEASE_API="https://api.github.com/repos/The-Yerbas-Endeavor/yerbas/releases/latest"
BOOTSTRAP_RELEASE_API="https://api.github.com/repos/The-Yerbas-Endeavor/YERB-Bootstrap/releases/latest"
YERBAS_ENV_FILE="/etc/yerbas/explorer.env"
INSTALL_BOOTSTRAP="${INSTALL_BOOTSTRAP:-yes}"
FORCE_BOOTSTRAP="${FORCE_BOOTSTRAP:-no}"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "Run this installer as root."
for command_name in curl jq tar find install openssl systemctl sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || die "Required command is missing: $command_name"
done

case "$(dpkg --print-architecture)" in
  amd64) ARCH_REGEX='(x86_64|amd64)' ;;
  arm64) ARCH_REGEX='(aarch64|arm64)' ;;
  *) die "Unsupported architecture: $(dpkg --print-architecture)" ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

extract_archive() {
  local archive="$1"
  local destination="$2"
  case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$destination" ;;
    *.tar.xz) tar -xJf "$archive" -C "$destination" ;;
    *.tar.zst|*.tzst) tar --zstd -xf "$archive" -C "$destination" ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || die "unzip is required for $archive"
      unzip -q "$archive" -d "$destination"
      ;;
    *) die "Unsupported archive format: $archive" ;;
  esac
}

info "Finding latest Yerbas Core release"
RELEASE_JSON="$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$YERBAS_RELEASE_API")"
YERBAS_VERSION="$(jq -r '.tag_name // empty' <<<"$RELEASE_JSON")"
[[ -n "$YERBAS_VERSION" ]] || die "GitHub did not return a published Yerbas release."

ASSET_URL="$(jq -r '.assets[].browser_download_url' <<<"$RELEASE_JSON" \
  | grep -Ei "$ARCH_REGEX" \
  | grep -Ei 'linux|ubuntu' \
  | grep -Eiv 'debug|symbols|source|src|checksum|sha256|qt|windows|win|mac|darwin' \
  | grep -Ei '\.(tar\.gz|tgz|tar\.xz|tar\.zst|tzst|zip)$' \
  | head -n 1 || true)"

if [[ -z "$ASSET_URL" ]]; then
  ASSET_URL="$(jq -r '.assets[].browser_download_url' <<<"$RELEASE_JSON" \
    | grep -Ei "$ARCH_REGEX" \
    | grep -Eiv 'debug|symbols|source|src|checksum|sha256|windows|win|mac|darwin' \
    | grep -Ei '\.(tar\.gz|tgz|tar\.xz|tar\.zst|tzst|zip)$' \
    | head -n 1 || true)"
fi

[[ -n "$ASSET_URL" ]] || {
  jq -r '.assets[].name' <<<"$RELEASE_JSON" >&2
  die "No suitable Linux Yerbas release archive was found for $(dpkg --print-architecture)."
}

info "Installing Yerbas Core ${YERBAS_VERSION}"
CORE_DIR="$TMP_DIR/core"
mkdir -p "$CORE_DIR"
CORE_ARCHIVE="$TMP_DIR/$(basename "${ASSET_URL%%\?*}")"
curl -fL --retry 3 --retry-delay 2 -o "$CORE_ARCHIVE" "$ASSET_URL"
extract_archive "$CORE_ARCHIVE" "$CORE_DIR"

YERBASD_PATH="$(find "$CORE_DIR" -type f -name yerbasd -perm -u+x | head -n 1 || true)"
YERBAS_CLI_PATH="$(find "$CORE_DIR" -type f -name yerbas-cli -perm -u+x | head -n 1 || true)"
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

BOOTSTRAP_INSTALLED=no
if [[ "${INSTALL_BOOTSTRAP,,}" =~ ^(y|yes|true|1)$ ]]; then
  if [[ -d "$YERBAS_DATADIR/blocks" || -d "$YERBAS_DATADIR/chainstate" ]] && [[ ! "${FORCE_BOOTSTRAP,,}" =~ ^(y|yes|true|1)$ ]]; then
    warn "Existing blockchain data found; skipping bootstrap-index. Set FORCE_BOOTSTRAP=yes to replace it."
  else
    info "Finding latest explorer bootstrap-index"
    BOOTSTRAP_JSON="$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$BOOTSTRAP_RELEASE_API" || true)"
    BOOTSTRAP_URL="$(jq -r '.assets[]? | select((.name | ascii_downcase | contains("bootstrap-index")) and (.name | test("\\.(tar\\.gz|tgz|tar\\.xz|tar\\.zst|tzst|zip)$"; "i"))) | .browser_download_url' <<<"$BOOTSTRAP_JSON" | head -n 1 || true)"
    BOOTSTRAP_DIGEST="$(jq -r --arg url "$BOOTSTRAP_URL" '.assets[]? | select(.browser_download_url == $url) | .digest // empty' <<<"$BOOTSTRAP_JSON" | head -n 1 || true)"
    BOOTSTRAP_VERSION="$(jq -r '.tag_name // empty' <<<"$BOOTSTRAP_JSON" 2>/dev/null || true)"

    if [[ -n "$BOOTSTRAP_URL" ]]; then
      info "Downloading bootstrap-index ${BOOTSTRAP_VERSION:-latest}"
      BOOTSTRAP_DIR="$TMP_DIR/bootstrap"
      BOOTSTRAP_EXTRACT="$TMP_DIR/bootstrap-extract"
      mkdir -p "$BOOTSTRAP_DIR" "$BOOTSTRAP_EXTRACT"
      BOOTSTRAP_ARCHIVE="$BOOTSTRAP_DIR/$(basename "${BOOTSTRAP_URL%%\?*}")"
      curl -fL --retry 3 --retry-delay 3 -o "$BOOTSTRAP_ARCHIVE" "$BOOTSTRAP_URL"

      if [[ "$BOOTSTRAP_DIGEST" == sha256:* ]]; then
        EXPECTED_SHA="${BOOTSTRAP_DIGEST#sha256:}"
        ACTUAL_SHA="$(sha256sum "$BOOTSTRAP_ARCHIVE" | awk '{print $1}')"
        [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || die "bootstrap-index SHA-256 verification failed."
        ok "bootstrap-index SHA-256 verified"
      else
        warn "GitHub release did not provide a SHA-256 digest for the bootstrap asset."
      fi

      extract_archive "$BOOTSTRAP_ARCHIVE" "$BOOTSTRAP_EXTRACT"
      BOOTSTRAP_ROOT="$(find "$BOOTSTRAP_EXTRACT" -type d -name chainstate -printf '%h\n' | head -n 1 || true)"
      [[ -n "$BOOTSTRAP_ROOT" ]] || BOOTSTRAP_ROOT="$(find "$BOOTSTRAP_EXTRACT" -type d -name blocks -printf '%h\n' | head -n 1 || true)"

      if [[ -z "$BOOTSTRAP_ROOT" ]]; then
        warn "bootstrap-index archive did not contain blocks/ or chainstate/; continuing with normal network sync."
      else
        systemctl stop yerbasd >/dev/null 2>&1 || true
        for item in blocks chainstate indexes evodb llmq database; do
          if [[ -e "$BOOTSTRAP_ROOT/$item" ]]; then
            rm -rf "$YERBAS_DATADIR/$item"
            cp -a "$BOOTSTRAP_ROOT/$item" "$YERBAS_DATADIR/$item"
          fi
        done
        for item in peers.dat banlist.dat mncache.dat mnpayments.dat netfulfilled.dat governance.dat fee_estimates.dat; do
          [[ -f "$BOOTSTRAP_ROOT/$item" ]] && cp -a "$BOOTSTRAP_ROOT/$item" "$YERBAS_DATADIR/$item"
        done
        rm -f "$YERBAS_DATADIR/.lock"
        chown -R "$YERBAS_USER:$YERBAS_USER" "$YERBAS_DATADIR"
        BOOTSTRAP_INSTALLED=yes
        ok "Explorer bootstrap-index installed into $YERBAS_DATADIR"
      fi
    else
      warn "No bootstrap-index archive was found in the latest YERB-Bootstrap release; continuing with normal network sync."
      if [[ -n "$BOOTSTRAP_JSON" ]]; then
        info "Available bootstrap assets:"
        jq -r '.assets[]?.name' <<<"$BOOTSTRAP_JSON" || true
      fi
    fi
  fi
fi

cat > "$YERBAS_ENV_FILE" <<EOF
RPC_HOST=127.0.0.1
RPC_PORT=${RPC_PORT}
RPC_USER=${RPC_USER}
RPC_PASSWORD=${RPC_PASSWORD}
YERBAS_VERSION=${YERBAS_VERSION}
YERBAS_DATADIR=${YERBAS_DATADIR}
YERBAS_CONF=${YERBAS_CONF}
BOOTSTRAP_INSTALLED=${BOOTSTRAP_INSTALLED}
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
for _ in $(seq 1 90); do
  if sudo -u "$YERBAS_USER" /usr/local/bin/yerbas-cli -conf="$YERBAS_CONF" -datadir="$YERBAS_DATADIR" getblockchaininfo >/dev/null 2>&1; then
    RPC_READY=true
    break
  fi
  sleep 2
done

if [[ "$RPC_READY" == true ]]; then
  ok "Yerbas Core ${YERBAS_VERSION} is running and RPC is ready"
  [[ "$BOOTSTRAP_INSTALLED" == yes ]] && ok "Yerbas explorer bootstrap-index is loaded"
else
  warn "Yerbas Core is running but RPC is not ready yet; initial startup or index validation may still be in progress."
fi

printf '%s\n' "$YERBAS_ENV_FILE"
