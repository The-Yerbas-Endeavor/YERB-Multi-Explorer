#!/usr/bin/env bash
set -u
APP_USER="yerbexplorer"
APP_NAME="yerb-multi-explorer"
APP_PORT="${APP_PORT:-3001}"
failed=0
check() { if "$@" >/dev/null 2>&1; then printf '[OK] %s\n' "$1"; else printf '[FAIL] %s\n' "$1"; failed=1; fi; }
check systemctl is-active --quiet docker
check systemctl is-active --quiet nginx
if docker ps --format '{{.Names}}' | grep -qx yerb-mongodb; then echo '[OK] MongoDB container'; else echo '[FAIL] MongoDB container'; failed=1; fi
if sudo -u "$APP_USER" env HOME="/home/$APP_USER" pm2 describe "$APP_NAME" 2>/dev/null | grep -q 'online'; then echo '[OK] Explorer PM2 process'; else echo '[FAIL] Explorer PM2 process'; failed=1; fi
if curl -fsS --max-time 10 "http://127.0.0.1:${APP_PORT}/" >/dev/null; then echo '[OK] Explorer HTTP'; else echo '[FAIL] Explorer HTTP'; failed=1; fi
if curl -fsS --max-time 10 "http://127.0.0.1:${APP_PORT}/ext/getsummary" >/dev/null; then echo '[OK] Explorer summary API'; else echo '[WARN] Summary API unavailable (RPC/indexing may not be configured yet)'; fi
exit "$failed"
