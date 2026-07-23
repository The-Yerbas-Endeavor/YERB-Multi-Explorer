# Ubuntu 26.04 Installer

Production installer for YERB Multi-Explorer on Ubuntu 26.04 LTS.

## What it installs

- Node.js 22 and npm
- PM2 with a systemd startup service
- Native MongoDB 8 service bound to `127.0.0.1`
- Nginx reverse proxy and API rate limiting
- Optional Let's Encrypt TLS
- UFW firewall and unattended security updates
- Dedicated `yerbexplorer` service account
- Update, health-check, and uninstall commands

**No Docker or container runtime is installed or used.**

## Install

```bash
sudo bash installer/install.sh
```

The installer asks for the explorer domain and Yerbas RPC connection details. It clones the repository to `/opt/yerb-multi-explorer` and installs the selected branch (`main` by default).

To install another branch:

```bash
sudo BRANCH=feature/modern-dashboard bash installer/install.sh
```

## MongoDB on Ubuntu 26.04

MongoDB 8 currently publishes native Ubuntu packages for Ubuntu 24.04 (`noble`). The installer uses that official native repository on Ubuntu 26.04 and runs MongoDB directly as the `mongod` systemd service. MongoDB is configured to listen only on localhost.

Verify it with:

```bash
systemctl status mongod
mongosh --quiet --eval 'db.runCommand({ ping: 1 })'
```

## Important configuration step

The repository's settings template is copied to `/opt/yerb-multi-explorer/settings.json` when available. Review that file and enter the RPC and MongoDB fields expected by the explorer version before running the indexer.

Use this local MongoDB connection unless the explorer schema requires separate fields:

```text
mongodb://127.0.0.1:27017/explorerdb
```

RPC answers are stored with root/service-user-only permissions in:

```text
/opt/yerb-multi-explorer/.installer.env
```

They are not automatically forced into `settings.json` because settings schemas can change between explorer releases.

## Operations

```bash
sudo yerb-explorer-health
sudo yerb-explorer-update
sudo yerb-explorer-uninstall
```

View application logs:

```bash
sudo -u yerbexplorer PM2_HOME=/home/yerbexplorer/.pm2 pm2 logs yerb-multi-explorer
```

Restart the explorer:

```bash
sudo -u yerbexplorer PM2_HOME=/home/yerbexplorer/.pm2 pm2 restart yerb-multi-explorer
```

Run initial indexing after `settings.json` is configured:

```bash
cd /opt/yerb-multi-explorer
sudo -u yerbexplorer npm run sync-blocks
sudo -u yerbexplorer npm run sync-peers
sudo -u yerbexplorer npm run sync-masternodes
sudo -u yerbexplorer npm run sync-markets
```

## Paths

| Purpose | Path |
|---|---|
| Explorer | `/opt/yerb-multi-explorer` |
| Nginx site | `/etc/nginx/sites-available/yerb-multi-explorer` |
| Installer log | `/var/log/yerb-multi-explorer-install.log` |
| PM2 state | `/home/yerbexplorer/.pm2` |
| MongoDB data | `/var/lib/mongodb` |
| MongoDB configuration | `/etc/mongod.conf` |
| Update backups | `/var/backups/yerb-multi-explorer` |

## Notes

The installer applies the Express-compatible regular-expression wildcard route when it finds the legacy `app.get('*', ...)` form. It does not install Docker, Podman, containerd, or any container-based dependency.
