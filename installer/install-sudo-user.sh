#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -ne 0 ]] || die "Run this launcher as your normal sudo-enabled user, not as root and not with sudo."
command -v sudo >/dev/null 2>&1 || die "sudo is required."
command -v python3 >/dev/null 2>&1 || die "python3 is required."
[[ -r /etc/os-release ]] || die "Unable to detect the operating system: /etc/os-release is missing."

# shellcheck disable=SC1091
source /etc/os-release
OS_ID="${ID:-unknown}"
OS_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
OS_VERSION="${VERSION_ID:-unknown}"
KERNEL_RELEASE="$(uname -r)"
KERNEL_VERSION="${KERNEL_RELEASE%%-*}"
ARCHITECTURE="$(dpkg --print-architecture 2>/dev/null || uname -m)"

printf '\n==============================================================\n'
printf '              Yerbas Explorer System Check\n'
printf '==============================================================\n\n'
printf 'Operating system : %s\n' "$OS_NAME"
printf 'OS version       : %s\n' "$OS_VERSION"
printf 'Kernel           : %s\n' "$KERNEL_RELEASE"
printf 'Architecture     : %s\n' "$ARCHITECTURE"
printf 'MongoDB target   : %s\n\n' "${MONGO_VERSION:-8.0}"

[[ "$OS_ID" == ubuntu ]] || {
  printf 'Support status   : ✗ Unsupported operating system\n\n'
  die "This installer currently supports Ubuntu 24.04 LTS only."
}

case "$OS_VERSION" in
  24.04)
    printf 'Support status   : ✓ Fully supported\n'
    ok "Ubuntu 24.04 LTS detected. Continuing with installation."
    ;;
  26.04)
    printf 'Support status   : ✗ Not currently supported\n\n'
    printf 'Ubuntu 26.04 uses Linux kernel %s. MongoDB 8.0 cannot run on\n' "$KERNEL_VERSION"
    printf 'Linux kernel 6.19 or newer because of a known MongoDB allocator\n'
    printf 'incompatibility. Docker does not bypass this host-kernel issue.\n\n'
    die "Install the Yerbas explorer on Ubuntu 24.04 LTS."
    ;;
  22.04)
    printf 'Support status   : ⚠ Legacy Ubuntu release\n\n'
    die "Ubuntu 22.04 is not supported by this installer configuration. Use Ubuntu 24.04 LTS."
    ;;
  *)
    printf 'Support status   : ✗ Untested Ubuntu release\n\n'
    die "Ubuntu ${OS_VERSION} is not supported. Use Ubuntu 24.04 LTS."
    ;;
esac

# Protect against a newer incompatible kernel being installed on Ubuntu 24.04.
if dpkg --compare-versions "$KERNEL_VERSION" ge "6.19"; then
  printf '\nKernel status    : ✗ MongoDB-incompatible kernel\n\n'
  die "MongoDB 8.0 cannot run on Linux kernel ${KERNEL_VERSION}. Use Ubuntu 24.04 LTS with a supported kernel older than 6.19."
fi
printf 'Kernel status    : ✓ Compatible with MongoDB 8.0\n\n'

INSTALLER_USER="$(id -un)"
INSTALLER_UID="$(id -u)"
INSTALLER_HOME="${HOME}"
export INSTALLER_USER INSTALLER_UID INSTALLER_HOME

info "Checking sudo access for ${INSTALLER_USER}"
sudo -v || die "This account does not have working sudo privileges."

# Large bootstrap archives and extracted blockchain data must use the root disk,
# not a potentially small RAM-backed /tmp filesystem.
INSTALLER_WORK_ROOT="${INSTALLER_WORK_ROOT:-/var/tmp/yerbas-installer}"
sudo install -d -m 1777 "$INSTALLER_WORK_ROOT"
export TMPDIR="$INSTALLER_WORK_ROOT"

TMP_DIR="$(mktemp -d "$INSTALLER_WORK_ROOT/launcher.XXXXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

cp "$SCRIPT_DIR/install.sh" "$TMP_DIR/install.sh"
cp "$SCRIPT_DIR/install-yerbas-core.sh" "$TMP_DIR/install-yerbas-core.sh"
cp "$SCRIPT_DIR/jsonc-to-json.py" "$TMP_DIR/jsonc-to-json.py"
chmod 0755 "$TMP_DIR/install.sh" "$TMP_DIR/install-yerbas-core.sh" "$TMP_DIR/jsonc-to-json.py"

python3 - "$TMP_DIR/install.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '    cp "$APP_DIR/settings.json.template" "$APP_DIR/settings.json"'
new = '    python3 "$SCRIPT_DIR/jsonc-to-json.py" "$APP_DIR/settings.json.template" "$APP_DIR/settings.json"'
if old not in text:
    raise SystemExit("Unable to locate the settings-template copy step in install.sh")
text = text.replace(old, new, 1)

# The launcher already performs the detailed compatibility check. Replace the
# obsolete Ubuntu 26 warning in the privileged installer with a 24.04 guard.
old_os = '''source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only."
[[ "${VERSION_ID:-}" == "26.04" ]] || warn "Designed for Ubuntu 26.04; detected ${PRETTY_NAME:-unknown}."'''
new_os = '''source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only."
[[ "${VERSION_ID:-}" == "24.04" ]] || die "This installer supports Ubuntu 24.04 LTS only; detected ${PRETTY_NAME:-unknown}."'''
if old_os not in text:
    raise SystemExit("Unable to locate the operating-system check in install.sh")
text = text.replace(old_os, new_os, 1)
path.write_text(text, encoding="utf-8")
PY

# Harden the copied core installer even when an older source copy is present.
# This guarantees large bootstrap extraction never falls back to /tmp.
python3 - "$TMP_DIR/install-yerbas-core.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = text.replace(
    'TMP_DIR="$(mktemp -d)"',
    'INSTALLER_WORK_ROOT="${INSTALLER_WORK_ROOT:-/var/tmp/yerbas-installer}"\n'
    'install -d -m 1777 "$INSTALLER_WORK_ROOT"\n'
    'TMP_DIR="$(mktemp -d "$INSTALLER_WORK_ROOT/core-installer.XXXXXXXX")"',
    1,
)

old_height = 'BOOTSTRAP_HEIGHT="$(jq -r \'(.body // "") | capture("(?i)(block|height)[^0-9]*(?<height>[0-9]+)")?.height // "unknown"\' <<<"$BOOTSTRAP_JSON" 2>/dev/null || true)"'
new_height = 'BOOTSTRAP_HEIGHT="$(jq -r \'[.name, .tag_name, .body, (.assets[]?.name)] | map(select(. != null)) | join(" ") | capture("(?i)(block[ _-]*height|height|block)[^0-9]*(?<height>[0-9]{4,})")?.height // "unknown"\' <<<"$BOOTSTRAP_JSON" 2>/dev/null || true)"'
text = text.replace(old_height, new_height, 1)

text = text.replace(
    'info "Downloading bootstrap-index ${BOOTSTRAP_VERSION:-latest}"\n        info "Interrupted downloads are resumed automatically."',
    'info "Downloading bootstrap-index ${BOOTSTRAP_VERSION:-latest} at block height ${BOOTSTRAP_HEIGHT}"\n'
    '        info "Interrupted downloads are resumed automatically."',
    1,
)

text = text.replace(
    'BOOTSTRAP_EXTRACT="$TMP_DIR/bootstrap-extract"\n        mkdir -p "$BOOTSTRAP_EXTRACT"',
    'BOOTSTRAP_EXTRACT="$TMP_DIR/bootstrap-extract"\n'
    '        mkdir -p "$BOOTSTRAP_EXTRACT"\n'
    '        EXTRACT_AVAILABLE_BYTES="$(df -PB1 "$BOOTSTRAP_EXTRACT" | awk \'NR==2 {print $4}\')"\n'
    '        if (( EXTRACT_AVAILABLE_BYTES < REQUIRED_BYTES )); then\n'
    '          die "Insufficient disk space for bootstrap extraction in $BOOTSTRAP_EXTRACT. Required approximately $(human_bytes "$REQUIRED_BYTES"), available $(human_bytes "$EXTRACT_AVAILABLE_BYTES")."\n'
    '        fi\n'
    '        info "Bootstrap extraction workspace: $BOOTSTRAP_EXTRACT"',
    1,
)

path.write_text(text, encoding="utf-8")
PY

info "Starting privileged installation as ${INSTALLER_USER} via sudo"
sudo --preserve-env=INSTALLER_USER,INSTALLER_UID,INSTALLER_HOME,BRANCH,APP_PORT,MONGO_VERSION,MONGO_DB,MONGO_USER,INSTALL_BOOTSTRAP,FORCE_BOOTSTRAP,KEEP_BOOTSTRAP_ARCHIVE,TMPDIR,INSTALLER_WORK_ROOT \
  bash "$TMP_DIR/install.sh"

ok "Installation completed for sudo user ${INSTALLER_USER}"
