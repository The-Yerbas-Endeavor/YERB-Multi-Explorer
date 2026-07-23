#!/usr/bin/env bash
set -u
APP_USER="yerbexplorer"
APP_NAME="yerb-multi-explorer"
APP_PORT="${APP_PORT:-3001}"
failed=0

if systemctl is-active --quiet mongod; then echo '[OK] MongoDB service'; else echo '[FAIL] MongoDB service'; failed=1; fi
if mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>/dev/null | grep -q '^1$'; then echo '[OK] MongoDB ping'; else echo '[FAIL] MongoDB ping'; failed=1; fi
if systemctl is-active --quiet nginx; then echo '[OK] Nginx service'; else echo '[FAIL] Nginx service'; failed=1; fi
if sudo -u "$APP_USER" env HOME="/home/$APP_USER" pm2 describe "$APP_NAME" 2>/dev/null | grep -q 'online'; then echo '[OK] Explorer PM2 process'; else echo '[FAIL] Explorer PM2 process'; failed=1; fi
if curl -fsS --max-time 10 "http://127.0.0.1:${APP_PORT}/" >/dev/null; then echo '[OK] Explorer HTTP'; else echo '[FAIL] Explorer HTTP'; failed=1; fi
if curl -fsS --max-time 10 "http://127.0.0.1:${APP_PORT}/ext/getsummary" >/dev/null; then echo '[OK] Explorer summary API'; else echo '[WARN] Summary API unavailable (RPC/indexing may not be configured yet)'; fi
exit "$failed"
