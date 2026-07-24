#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${ROOT}/storage/sync.lock"

mkdir -p "${ROOT}/storage"
exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
  echo "Yerbas explorer sync is already running."
  exit 0
fi

/usr/bin/php "${ROOT}/scripts/sync-assets.php"
/usr/bin/php "${ROOT}/scripts/sync-activity.php"
