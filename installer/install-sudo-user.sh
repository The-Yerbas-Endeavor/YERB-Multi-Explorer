#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -ne 0 ]] || die "Run this launcher as your normal sudo-enabled user, not as root and not with sudo."
command -v sudo >/dev/null 2>&1 || die "sudo is required."
command -v python3 >/dev/null 2>&1 || die "python3 is required."

INSTALLER_USER="$(id -un)"
INSTALLER_UID="$(id -u)"
INSTALLER_HOME="${HOME}"
export INSTALLER_USER INSTALLER_UID INSTALLER_HOME

info "Checking sudo access for ${INSTALLER_USER}"
sudo -v || die "This account does not have working sudo privileges."

# Ubuntu 26 commonly mounts /tmp as a small RAM-backed tmpfs. Bootstrap
# archives and their extracted blockchain data must use the root disk instead.
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
path.write_text(text, encoding="utf-8")
PY

info "Starting privileged installation as ${INSTALLER_USER} via sudo"
sudo --preserve-env=INSTALLER_USER,INSTALLER_UID,INSTALLER_HOME,BRANCH,APP_PORT,MONGO_VERSION,MONGO_DB,MONGO_USER,INSTALL_BOOTSTRAP,FORCE_BOOTSTRAP,KEEP_BOOTSTRAP_ARCHIVE,TMPDIR,INSTALLER_WORK_ROOT \
  bash "$TMP_DIR/install.sh"

ok "Installation completed for sudo user ${INSTALLER_USER}"
