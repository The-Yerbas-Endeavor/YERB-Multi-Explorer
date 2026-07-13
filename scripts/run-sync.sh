#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${ROOT}/storage/sync.lock"

mkdir -p "${ROOT}/storage"
exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
  echo "Asset sync is already running."
  exit 0
fi

exec /usr/bin/php "${ROOT}/scripts/sync-assets.php"
