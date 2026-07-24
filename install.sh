#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-/opt/yerb-multi-explorer}"
APP_USER="${APP_USER:-yerbexplorer}"
INNER_INSTALLER="$ROOT_DIR/installer/install.sh"
JSON_CLEANER="$ROOT_DIR/installer/strip-json-comments.py"

[[ ${EUID} -eq 0 ]] || {
  echo "Run the unified installer with sudo." >&2
  exit 1
}

if [[ -z "${BRANCH:-}" ]]; then
  BRANCH=$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)
  BRANCH="${BRANCH:-portal-integration}"
fi
export BRANCH

[[ -f "$INNER_INSTALLER" ]] || {
  echo "Missing installer: $INNER_INSTALLER" >&2
  exit 1
}
[[ -f "$JSON_CLEANER" ]] || {
  echo "Missing JSON cleaner: $JSON_CLEANER" >&2
  exit 1
}

# Keep the legacy installer usable while correcting two known assumptions:
# 1. Ubuntu 24.04 is a supported target.
# 2. settings.json.template contains comments and must be converted to strict JSON
#    before jq can safely update it.
python3 - "$INNER_INSTALLER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old_version = '[[ "${VERSION_ID:-}" == "26.04" ]] || warn "Designed for Ubuntu 26.04; detected ${PRETTY_NAME:-unknown}."'
new_version = '''case "${VERSION_ID:-}" in
  "24.04"|"26.04") ;;
  *) die "Unsupported Ubuntu version: ${PRETTY_NAME:-unknown}. Supported versions are Ubuntu 24.04 and 26.04." ;;
esac'''
if old_version in text:
    text = text.replace(old_version, new_version, 1)

old_copy = '''  if [[ -f "$APP_DIR/settings.json.template" ]]; then
    cp "$APP_DIR/settings.json.template" "$APP_DIR/settings.json"'''
new_copy = '''  if [[ -f "$APP_DIR/settings.json.template" ]]; then
    python3 "$SCRIPT_DIR/strip-json-comments.py" \\
      "$APP_DIR/settings.json.template" "$APP_DIR/settings.json" || \\
      die "Unable to convert settings.json.template into strict JSON."'''
if old_copy in text:
    text = text.replace(old_copy, new_copy, 1)

if 'Designed for Ubuntu 26.04' in text:
    raise SystemExit("Unable to patch Ubuntu version handling in installer/install.sh")
if 'cp "$APP_DIR/settings.json.template" "$APP_DIR/settings.json"' in text:
    raise SystemExit("Unable to patch settings template handling in installer/install.sh")

path.write_text(text, encoding="utf-8")
PY

chmod 0755 "$INNER_INSTALLER" "$JSON_CLEANER"

echo "Installing the unified Yerbas Portal from branch: $BRANCH"
"$INNER_INSTALLER"

[[ -x "$APP_DIR/installer/integrate-assets.sh" ]] || chmod 0755 "$APP_DIR/installer/integrate-assets.sh"
APP_DIR="$APP_DIR" APP_USER="$APP_USER" bash "$APP_DIR/installer/integrate-assets.sh"

systemctl is-active --quiet nginx
systemctl is-active --quiet "pm2-${APP_USER}"
systemctl is-active --quiet yerbas-assets-sync.timer

curl -fsS --max-time 10 http://127.0.0.1/assets/ >/dev/null

echo
echo "Unified Yerbas Portal installation complete."
echo "Explorer and Assets are installed together under: $APP_DIR"
echo "Assets module: $APP_DIR/modules/assets-viewer"
echo "Assets URL: /assets/"
