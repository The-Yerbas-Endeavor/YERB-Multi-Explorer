# Ubuntu 26 one-click installation

This installer deploys YERB Multi-Explorer natively on Ubuntu 26 Server. It does not use Docker.

## Prerequisites

Before running it, have these services available:

- a synchronized Yerbas Core node with RPC enabled
- MongoDB reachable from the explorer server
- a domain pointed to the server
- ports 80 and 443 allowed through the firewall

Recommended Yerbas Core settings:

```ini
server=1
daemon=1
rpcuser=CHANGE_THIS_USERNAME
rpcpassword=CHANGE_THIS_TO_A_LONG_RANDOM_PASSWORD
rpcport=8766
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
addressindex=1
assetindex=1
spentindex=1
timestampindex=1
txindex=1
```

## Interactive installation

Download the installer and run it. It prompts for the domain, Yerbas RPC credentials, and MongoDB URI.

```bash
curl -fsSLO https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/scripts/install-ubuntu26.sh
sudo bash install-ubuntu26.sh
```

## Fully unattended installation

```bash
curl -fsSLO https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/scripts/install-ubuntu26.sh

sudo env \
  DOMAIN=explorer.yerbas.org \
  YERB_RPC_USER=explorer \
  YERB_RPC_PASSWORD='CHANGE_THIS_TO_A_LONG_RANDOM_PASSWORD' \
  MONGODB_URI='mongodb://127.0.0.1:27017/yerbas_explorer' \
  ENABLE_HTTPS=1 \
  CERTBOT_EMAIL='admin@yerbas.org' \
  bash install-ubuntu26.sh
```

Do not place real credentials in shell history on a shared system. An interactive run is safer when other users can inspect process arguments or history.

## What the installer does

The script:

- verifies Ubuntu 26 on AMD64 or ARM64
- installs Node.js 22, Redis, Nginx, Certbot, compiler tools, and PM2
- creates the unprivileged `yerbexplorer` service account
- clones or updates the repository in `/var/www/yerb-explorer`
- writes a protected production `.env`
- installs dependencies, typechecks, and builds the API and Vue frontend
- starts the API and indexer under PM2
- creates and enables the PM2 systemd startup service
- writes and enables the Nginx virtual host
- optionally requests and tests a Let's Encrypt certificate
- checks Redis, Nginx, PM2, and the API health endpoint

## Options

| Variable | Default | Purpose |
|---|---|---|
| `DOMAIN` | required | Public explorer hostname |
| `YERB_RPC_USER` | required | Yerbas Core RPC username |
| `YERB_RPC_PASSWORD` | required | Yerbas Core RPC password |
| `MONGODB_URI` | `mongodb://127.0.0.1:27017/yerbas_explorer` | MongoDB connection string |
| `YERB_RPC_URL` | `http://127.0.0.1:8766` | Yerbas Core RPC endpoint |
| `ENABLE_HTTPS` | `0` | Set to `1` to run Certbot |
| `CERTBOT_EMAIL` | empty | Let's Encrypt account email |
| `INSTALL_DIR` | `/var/www/yerb-explorer` | Application directory |
| `APP_USER` | `yerbexplorer` | Service account |
| `API_PORT` | `3001` | Local Fastify port |
| `SYNC_BATCH_SIZE` | `25` | Blocks queued per synchronization pass |
| `REPO_BRANCH` | `main` | Branch installed or updated |
| `SKIP_TYPECHECK` | `0` | Set to `1` only for emergency troubleshooting |

## Updating an existing installation

The installer is rerunnable. It fetches the selected branch, resets the application checkout to the remote branch, rebuilds, restarts PM2, and revalidates the services.

Back up `.env` before changing installation variables. The installer rewrites `.env` from the supplied values on every run.

## Service checks

```bash
sudo -iu yerbexplorer pm2 status
sudo -iu yerbexplorer pm2 logs --lines 100
curl http://127.0.0.1:3001/api/v1/health
sudo nginx -t
sudo systemctl status nginx redis-server pm2-yerbexplorer
```

## HTTPS notes

Set `ENABLE_HTTPS=1` only after the domain resolves publicly to the server. Certbot can fail when DNS has not propagated, ports 80 or 443 are blocked, or the Let's Encrypt issuance rate limit has been reached.
