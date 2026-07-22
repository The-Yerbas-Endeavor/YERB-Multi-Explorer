#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPLORER_REMOTE="explorer-yerb"
ASSETS_REMOTE="yerbas-assets"
EXPLORER_URL="https://github.com/The-Yerbas-Endeavor/explorer-YERB.git"
ASSETS_URL="https://github.com/The-Yerbas-Endeavor/Yerbas-Assets-Viewer.git"

if [[ -e apps/explorer || -e apps/assets ]]; then
  echo "apps/explorer or apps/assets already exists; refusing to overwrite." >&2
  exit 1
fi

mkdir -p apps

git remote get-url "$EXPLORER_REMOTE" >/dev/null 2>&1 || git remote add "$EXPLORER_REMOTE" "$EXPLORER_URL"
git remote get-url "$ASSETS_REMOTE" >/dev/null 2>&1 || git remote add "$ASSETS_REMOTE" "$ASSETS_URL"

git fetch "$EXPLORER_REMOTE" master
git fetch "$ASSETS_REMOTE" main

git subtree add --prefix=apps/explorer "$EXPLORER_REMOTE" master
git subtree add --prefix=apps/assets "$ASSETS_REMOTE" main

echo "Imported explorer-YERB into apps/explorer"
echo "Imported Yerbas-Assets-Viewer into apps/assets"
