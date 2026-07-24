#!/usr/bin/env bash
set -Eeuo pipefail

YERBAS_USER="${YERBAS_USER:-yerbas}"
YERBAS_HOME="${YERBAS_HOME:-/var/lib/yerbas}"
YERBAS_DATADIR="${YERBAS_DATADIR:-${YERBAS_HOME}/.yerbas}"
YERBAS_CONF="${YERBAS_CONF:-${YERBAS_DATADIR}/yerbas.conf}"
YERBAS_RPC_PORT="${YERBAS_RPC_PORT:-9998}"
YERBAS_RELEASE_API="${YERBAS_RELEASE_API:-https://api.github.com/repos/The-Yerbas-Endeavor/yerbas/releases/latest}"
BOOTSTRAP_RELEASE_API="${BOOTSTRAP_RELEASE_API:-https://api.github.com/repos/The-Yerbas-Endeavor/YERB-Bootstrap/releases/latest}"
BOOTSTRAP_CACHE_DIR="${BOOTSTRAP_CACHE_DIR:-/var/cache/yerbas-bootstrap}"
BOOTSTRAP_DISK_MULTIPLIER="${BOOTSTRAP_DISK_MULTIPLIER:-3}"
YERBAS_ENV_FILE="/etc/yerbas/explorer.env"
INSTALL_BOOTSTRAP="${INSTALL_BOOTSTRAP:-ask}"
FORCE_BOOTSTRAP="${FORCE_BOOTSTRAP:-no}"
KEEP_BOOTSTRAP_ARCHIVE="${KEEP_BOOTSTRAP_ARCHIVE:-ask}"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

human_bytes() {
  local bytes="${1:-0}"
  numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || printf '%s bytes' "$bytes"
}

yes_value() {
  [[ "${1,,}" =~ ^(y|yes|true|1)$ ]]
}

no_value() {
  [[ "${1,,}" =~ ^(n|no|false|0)$ ]]
}

ask_yes_no() {
  local prompt="$1"
  local default_answer="${2:-yes}"
  local answer

  if [[ ! -t 0 ]]; then
    [[ "$default_answer" == yes ]]
    return
  fi

  if [[ "$default_answer" == yes ]]; then
    read -r -p "$prompt [Y/n]: " answer
    answer="${answer:-yes}"
  else
    read -r -p "$prompt [y/N]: " answer
    answer="${answer:-no}"
  fi
  yes_value "$answer"
}

extract_archive() {
  local archive="$1"
  local destination="$2"
  case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$destination" ;;
    *.tar.xz) tar -xJf "$archive" -C "$destination" ;;
    *.tar.zst|*.tzst) tar --zstd -xf "$archive" -C "$destination" ;;
    *.zip) unzip -q "$archive" -d "$destination" ;;
    *) die "Unsupported archive format: $archive" ;;
  esac
}

[[ ${EUID} -eq 0 ]] || die "Run this installer as root."
for command_name in curl jq tar find install openssl systemctl sha256sum numfmt df awk unzip; do
  command -v "$command_name" >/dev/null 2>&1 || die "Required command is missing: $command_name"
done

case "$(dpkg --print-architecture)" in
  amd64) ARCH_REGEX='(x86_64|amd64)' ;;
  arm64) ARCH_REGEX='(aarch64|arm64)' ;;
  *) die "Unsupported architecture: $(dpkg --print-architecture)" ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

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
curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$CORE_ARCHIVE" "$ASSET_URL"
extract_archive "$CORE_ARCHIVE" "$CORE_DIR"

YERBASD_PATH="$(find "$CORE_DIR" -type f -name yerbasd -perm -u+x | head -n 1 || true)"
YERBAS_CLI_PATH="$(find "$CORE_DIR" -type f -name yerbas-cli -perm -u+x | head -n 1 || true)"
[[ -n "$YERBASD_PATH" && -n "$YERBAS_CLI_PATH" ]] || die "The release archive does not contain executable yerbasd and yerbas-cli binaries."

install -m 0755 "$YERBASD_PATH" /usr/local/bin/yerbasd
install -m 0755 "$YERBAS_CLI_PATH" /usr/local/bin/yerbas-cli

id -u "$YERBAS_USER" >/dev/null 2>&1 || useradd --system --home-dir "$YERBAS_HOME" --create-home --shell /usr/sbin/nologin "$YERBAS_USER"
install -d -m 0750 -o "$YERBAS_USER" -g "$YERBAS_USER" "$YERBAS_DATADIR"
install -d -m 0750 /etc/yerbas
install -d -m 0750 "$BOOTSTRAP_CACHE_DIR"

if [[ -f "$YERBAS_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$YERBAS_ENV_FILE"
fi
RPC_USER="${RPC_USER:-explorer_$(openssl rand -hex 8)}"
RPC_PASSWORD="${RPC_PASSWORD:-$(openssl rand -hex 32)}"
RPC_PORT="${RPC_PORT:-$YERBAS_RPC_PORT}"

cat > "$YERBAS_CONF" <<EOF_CONF
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
EOF_CONF
chmod 0600 "$YERBAS_CONF"
chown "$YERBAS_USER:$YERBAS_USER" "$YERBAS_CONF"

BOOTSTRAP_INSTALLED=no
BOOTSTRAP_VERSION=""
BOOTSTRAP_HEIGHT="unknown"
BOOTSTRAP_CREATED="unknown"
BOOTSTRAP_ARCHIVE=""

if [[ ! -d "$YERBAS_DATADIR/blocks" && ! -d "$YERBAS_DATADIR/chainstate" ]] || yes_value "$FORCE_BOOTSTRAP"; then
  info "Checking for the latest Yerbas bootstrap-index"
  BOOTSTRAP_JSON="$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$BOOTSTRAP_RELEASE_API" || true)"
  BOOTSTRAP_URL="$(jq -r '.assets[]? | select((.name | ascii_downcase | contains("bootstrap-index")) and (.name | test("\\.(tar\\.gz|tgz|tar\\.xz|tar\\.zst|tzst|zip)$"; "i"))) | .browser_download_url' <<<"$BOOTSTRAP_JSON" | head -n 1 || true)"
  BOOTSTRAP_NAME="$(jq -r --arg url "$BOOTSTRAP_URL" '.assets[]? | select(.browser_download_url == $url) | .name // empty' <<<"$BOOTSTRAP_JSON" | head -n 1 || true)"
  BOOTSTRAP_BYTES="$(jq -r --arg url "$BOOTSTRAP_URL" '.assets[]? | select(.browser_download_url == $url) | .size // 0' <<<"$BOOTSTRAP_JSON" | head -n 1 || true)"
  BOOTSTRAP_DIGEST="$(jq -r --arg url "$BOOTSTRAP_URL" '.assets[]? | select(.browser_download_url == $url) | .digest // empty' <<<"$BOOTSTRAP_JSON" | head -n 1 || true)"
  BOOTSTRAP_VERSION="$(jq -r '.tag_name // empty' <<<"$BOOTSTRAP_JSON" 2>/dev/null || true)"
  BOOTSTRAP_CREATED="$(jq -r '.published_at // .created_at // "unknown"' <<<"$BOOTSTRAP_JSON" 2>/dev/null || true)"
  BOOTSTRAP_HEIGHT="$(jq -r '(.body // "") | capture("(?i)(block|height)[^0-9]*(?<height>[0-9]+)")?.height // "unknown"' <<<"$BOOTSTRAP_JSON" 2>/dev/null || true)"

  if [[ -n "$BOOTSTRAP_URL" ]]; then
    REQUIRED_BYTES=$(( BOOTSTRAP_BYTES * BOOTSTRAP_DISK_MULTIPLIER ))
    AVAILABLE_BYTES="$(df -PB1 "$YERBAS_HOME" | awk 'NR==2 {print $4}')"
    TOTAL_MEMORY="$(awk '/MemTotal:/ {print $2 * 1024}' /proc/meminfo)"

    printf '\n==============================================================\n'
    printf '                 Yerbas Bootstrap & Indexes\n'
    printf '==============================================================\n\n'
    printf 'A recent bootstrap can dramatically reduce the time required\n'
    printf 'before the explorer becomes fully operational.\n\n'
    printf 'Without bootstrap: initial sync may take many hours or days.\n'
    printf 'With bootstrap: faster sync, pre-built indexes, earlier launch.\n\n'
    printf 'Version       : %s\n' "${BOOTSTRAP_VERSION:-latest}"
    printf 'Block height  : %s\n' "$BOOTSTRAP_HEIGHT"
    printf 'Created       : %s\n' "$BOOTSTRAP_CREATED"
    printf 'Archive       : %s\n' "$BOOTSTRAP_NAME"
    printf 'Download size : %s\n' "$(human_bytes "$BOOTSTRAP_BYTES")"
    printf 'Disk required : approximately %s\n' "$(human_bytes "$REQUIRED_BYTES")"
    printf '\nSystem check\n'
    printf 'Available disk: %s\n' "$(human_bytes "$AVAILABLE_BYTES")"
    printf 'System memory : %s\n' "$(human_bytes "$TOTAL_MEMORY")"
    printf 'Internet      : connected\n\n'

    if (( AVAILABLE_BYTES < REQUIRED_BYTES )); then
      warn "Free disk space is below the estimated bootstrap requirement."
      if [[ -t 0 ]] && ! ask_yes_no "Continue with the bootstrap anyway?" no; then
        INSTALL_BOOTSTRAP=no
      elif [[ ! -t 0 ]]; then
        INSTALL_BOOTSTRAP=no
      fi
    fi

    if [[ "$INSTALL_BOOTSTRAP" == ask ]]; then
      if ask_yes_no "Download and install the latest Yerbas bootstrap-index?" yes; then
        INSTALL_BOOTSTRAP=yes
      else
        INSTALL_BOOTSTRAP=no
      fi
    fi

    if yes_value "$INSTALL_BOOTSTRAP"; then
      BOOTSTRAP_ARCHIVE="$BOOTSTRAP_CACHE_DIR/$BOOTSTRAP_NAME"
      USE_CACHE=no

      if [[ -f "$BOOTSTRAP_ARCHIVE" ]]; then
        CACHED_SIZE="$(stat -c '%s' "$BOOTSTRAP_ARCHIVE")"
        info "Existing bootstrap archive found: $BOOTSTRAP_ARCHIVE ($(human_bytes "$CACHED_SIZE"))"
        if [[ "$BOOTSTRAP_DIGEST" == sha256:* ]]; then
          EXPECTED_SHA="${BOOTSTRAP_DIGEST#sha256:}"
          CACHED_SHA="$(sha256sum "$BOOTSTRAP_ARCHIVE" | awk '{print $1}')"
          if [[ "$CACHED_SHA" == "$EXPECTED_SHA" ]]; then
            ok "Existing cached archive passed SHA-256 verification"
            if ask_yes_no "Reuse the verified cached bootstrap?" yes; then USE_CACHE=yes; fi
          else
            warn "Cached archive checksum is invalid; it will be downloaded again."
            rm -f "$BOOTSTRAP_ARCHIVE"
          fi
        elif ask_yes_no "Reuse the existing cached bootstrap archive?" yes; then
          USE_CACHE=yes
        fi
      fi

      if [[ "$USE_CACHE" != yes ]]; then
        info "Downloading bootstrap-index ${BOOTSTRAP_VERSION:-latest}"
        info "Interrupted downloads are resumed automatically."
        if ! curl -fL --retry 5 --retry-delay 3 --continue-at - --progress-bar -o "$BOOTSTRAP_ARCHIVE" "$BOOTSTRAP_URL"; then
          warn "Bootstrap download failed; continuing with normal network synchronization."
          INSTALL_BOOTSTRAP=no
        fi
      fi

      if yes_value "$INSTALL_BOOTSTRAP"; then
        if [[ "$BOOTSTRAP_DIGEST" == sha256:* ]]; then
          EXPECTED_SHA="${BOOTSTRAP_DIGEST#sha256:}"
          ACTUAL_SHA="$(sha256sum "$BOOTSTRAP_ARCHIVE" | awk '{print $1}')"
          if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
            warn "Bootstrap SHA-256 verification failed."
            if ask_yes_no "Delete the corrupted archive and continue without bootstrap?" yes; then
              rm -f "$BOOTSTRAP_ARCHIVE"
              INSTALL_BOOTSTRAP=no
            else
              die "Refusing to install an unverified bootstrap archive."
            fi
          else
            ok "Bootstrap SHA-256 verified"
          fi
        else
          warn "The release does not provide a SHA-256 digest; archive integrity cannot be cryptographically verified."
          if [[ -t 0 ]] && ! ask_yes_no "Continue with this unverified release asset?" no; then
            INSTALL_BOOTSTRAP=no
          fi
        fi
      fi

      if yes_value "$INSTALL_BOOTSTRAP"; then
        BOOTSTRAP_EXTRACT="$TMP_DIR/bootstrap-extract"
        mkdir -p "$BOOTSTRAP_EXTRACT"
        info "Extracting bootstrap-index"
        extract_archive "$BOOTSTRAP_ARCHIVE" "$BOOTSTRAP_EXTRACT"
        BOOTSTRAP_ROOT="$(find "$BOOTSTRAP_EXTRACT" -type d -name chainstate -printf '%h\n' | head -n 1 || true)"
        [[ -n "$BOOTSTRAP_ROOT" ]] || BOOTSTRAP_ROOT="$(find "$BOOTSTRAP_EXTRACT" -type d -name blocks -printf '%h\n' | head -n 1 || true)"

        if [[ -z "$BOOTSTRAP_ROOT" ]]; then
          warn "Archive did not contain blocks/ or chainstate/; continuing with normal network sync."
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

          if [[ "$KEEP_BOOTSTRAP_ARCHIVE" == ask ]]; then
            if ask_yes_no "Delete the downloaded archive to recover $(human_bytes "$BOOTSTRAP_BYTES")?" yes; then
              KEEP_BOOTSTRAP_ARCHIVE=no
            else
              KEEP_BOOTSTRAP_ARCHIVE=yes
            fi
          fi
          if no_value "$KEEP_BOOTSTRAP_ARCHIVE"; then
            rm -f "$BOOTSTRAP_ARCHIVE"
            ok "Downloaded bootstrap archive removed"
          else
            info "Bootstrap archive retained at $BOOTSTRAP_ARCHIVE"
          fi
        fi
      fi
    else
      warn "Skipping bootstrap download. Yerbas Core will synchronize from the network."
    fi
  else
    warn "No bootstrap-index archive was found; continuing with normal network synchronization."
    [[ -n "$BOOTSTRAP_JSON" ]] && jq -r '.assets[]?.name' <<<"$BOOTSTRAP_JSON" || true
  fi
else
  warn "Existing blockchain data found; skipping bootstrap-index. Set FORCE_BOOTSTRAP=yes to replace it."
fi

cat > "$YERBAS_ENV_FILE" <<EOF_ENV
RPC_HOST=127.0.0.1
RPC_PORT=${RPC_PORT}
RPC_USER=${RPC_USER}
RPC_PASSWORD=${RPC_PASSWORD}
YERBAS_VERSION=${YERBAS_VERSION}
YERBAS_DATADIR=${YERBAS_DATADIR}
YERBAS_CONF=${YERBAS_CONF}
BOOTSTRAP_INSTALLED=${BOOTSTRAP_INSTALLED}
BOOTSTRAP_VERSION=${BOOTSTRAP_VERSION}
BOOTSTRAP_HEIGHT=${BOOTSTRAP_HEIGHT}
BOOTSTRAP_CACHE_DIR=${BOOTSTRAP_CACHE_DIR}
EOF_ENV
chmod 0600 "$YERBAS_ENV_FILE"

cat > /etc/systemd/system/yerbasd.service <<EOF_SERVICE
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
EOF_SERVICE

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
  if [[ "$BOOTSTRAP_INSTALLED" == yes ]]; then
    ok "Yerbas explorer bootstrap-index is loaded"
    CHAIN_INFO="$(sudo -u "$YERBAS_USER" /usr/local/bin/yerbas-cli -conf="$YERBAS_CONF" -datadir="$YERBAS_DATADIR" getblockchaininfo 2>/dev/null || true)"
    CURRENT_BLOCK="$(jq -r '.blocks // "unknown"' <<<"$CHAIN_INFO" 2>/dev/null || true)"
    HEADER_BLOCK="$(jq -r '.headers // "unknown"' <<<"$CHAIN_INFO" 2>/dev/null || true)"
    printf 'Current block : %s\n' "$CURRENT_BLOCK"
    printf 'Network tip   : %s\n' "$HEADER_BLOCK"
    if [[ "$CURRENT_BLOCK" =~ ^[0-9]+$ && "$HEADER_BLOCK" =~ ^[0-9]+$ && "$HEADER_BLOCK" -ge "$CURRENT_BLOCK" ]]; then
      printf 'Blocks remain : %s\n' "$(( HEADER_BLOCK - CURRENT_BLOCK ))"
    fi
  fi
else
  warn "Yerbas Core is running but RPC is not ready yet; initial startup or index validation may still be in progress."
fi

printf '%s\n' "$YERBAS_ENV_FILE"
