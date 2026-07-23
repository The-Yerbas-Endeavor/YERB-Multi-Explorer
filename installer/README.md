# Ubuntu 26.04 Installer

Production installer for YERB Multi-Explorer on Ubuntu 26.04 LTS.

## What it installs

- Node.js 22 and npm
- PM2 with a systemd startup service
- MongoDB 8 in a persistent Docker container bound to localhost
- Nginx reverse proxy and API rate limiting
- Optional Let's Encrypt TLS
- UFW firewall and unattended security updates
- Dedicated `yerbexplorer` service account
- Update, health-check, and uninstall commands

## Install

```bash
sudo bash installer/install.sh
```

The installer asks for the explorer domain and Yerbas RPC connection details. It clones the repository to `/opt/yerb-multi-explorer` and installs the selected branch (`main` by default).

To install another branch:

```bash
sudo BRANCH=feature/modern-dashboard bash installer/install.sh
```

## Important configuration step

The repository's settings template is copied to `/opt/yerb-multi-explorer/settings.json` when available. Review that file and enter the RPC and MongoDB fields expected by the explorer version before running the indexer.

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
| MongoDB volume | `yerb-mongodb-data` |
| Update backups | `/var/backups/yerb-multi-explorer` |

## Notes

MongoDB runs in Docker to avoid depending on whether a native MongoDB repository currently publishes Ubuntu 26.04 packages. Node.js 22 is installed from NodeSource's `nodistro` repository. The installer also applies the Express-compatible regular-expression wildcard route when it finds the legacy `app.get('*', ...)` form.
