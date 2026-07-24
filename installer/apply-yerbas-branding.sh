#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/yerb-multi-explorer}"
APP_USER="${APP_USER:-yerbexplorer}"
SETTINGS_FILE="${SETTINGS_FILE:-$APP_DIR/settings.json}"

[[ ${EUID} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
[[ -d "$APP_DIR" ]] || { echo "Application directory not found: $APP_DIR" >&2; exit 1; }

# Replace user-facing legacy coin branding while leaving internal theme paths,
# upstream credits, dependencies, and repository history untouched.
for directory in views locale lib public/js; do
  [[ -d "$APP_DIR/$directory" ]] || continue
  while IFS= read -r -d '' file; do
    sed -i \
      -e 's/EXOR/YERB/g' \
      -e 's/Exor/Yerbas/g' \
      "$file"
  done < <(find "$APP_DIR/$directory" -type f \
    \( -name '*.js' -o -name '*.json' -o -name '*.pug' -o -name '*.ejs' -o -name '*.html' -o -name '*.txt' \) \
    -print0)
done

if [[ -f "$SETTINGS_FILE" ]]; then
  tmp_file="$(mktemp)"
  jq '
    .coin.name = "Yerbas"
    | .coin.symbol = "YERB"
    | .shared_pages.page_title = "Yerbas Portal"
  ' "$SETTINGS_FILE" > "$tmp_file"
  jq empty "$tmp_file"
  install -m 0600 -o "$APP_USER" -g "$APP_USER" "$tmp_file" "$SETTINGS_FILE"
  rm -f "$tmp_file"
fi

# Correct common generated/static branding files without renaming the internal
# Exor theme directory, which would break existing stylesheet URLs.
for file in "$APP_DIR/public/manifest.json" "$APP_DIR/package.json"; do
  [[ -f "$file" ]] || continue
  sed -i -e 's/EXOR/YERB/g' -e 's/Exor/Yerbas/g' "$file"
done

chown -R "$APP_USER:$APP_USER" "$APP_DIR/views" "$APP_DIR/locale" "$APP_DIR/public/js" 2>/dev/null || true

echo "Yerbas branding applied: native asset YERB, coin Yerbas, title Yerbas Portal."
