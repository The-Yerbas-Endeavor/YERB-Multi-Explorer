# Ubuntu 26.04 Installer

Production installer for YERB Multi-Explorer on Ubuntu 26.04 LTS.

## Required account model

The installer is designed to be launched by a **normal non-root Linux user with sudo privileges**.

Do not sign in as `root`, use `sudo -i`, or run the user-facing launcher with `sudo`. The launcher validates the current account, confirms sudo access, records the invoking user, and elevates only the privileged installation process.

The installer creates separate locked-down service accounts for Yerbas Core and the explorer. Your login account is not used to run either production service.

## What it installs

- Yerbas Core and an optional indexed blockchain bootstrap
- Node.js 22 and npm
- PM2 with a systemd startup service
- Native MongoDB 8 bound to `127.0.0.1`
- Nginx reverse proxy and API rate limiting
- Optional Let's Encrypt TLS
- UFW firewall and unattended security updates
- Dedicated `yerbas` and `yerbexplorer` service accounts
- Update, health-check, and uninstall commands

**No Docker or container runtime is installed or used.**

## Install

Log in with your ordinary sudo-enabled account:

```bash
git clone https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git
cd YERB-Multi-Explorer
chmod +x installer/install-sudo-user.sh
bash installer/install-sudo-user.sh
```

Do **not** use either of these forms:

```bash
sudo bash installer/install-sudo-user.sh
sudo -i
```

The launcher will ask for your sudo password when privileged work begins.

It also converts the repository's commented `settings.json.template` into strict JSON before `jq` applies the generated MongoDB and Yerbas RPC credentials. No manual `npx json5` conversion is required.

To install another branch:

```bash
BRANCH=feature/modern-dashboard bash installer/install-sudo-user.sh
```

For an unattended bootstrap choice:

```bash
INSTALL_BOOTSTRAP=yes KEEP_BOOTSTRAP_ARCHIVE=no bash installer/install-sudo-user.sh
```

To skip the bootstrap:

```bash
INSTALL_BOOTSTRAP=no bash installer/install-sudo-user.sh
```

## Security and ownership

The invoking sudo user is recorded as `INSTALLER_USER` for logging and future ownership-sensitive operations. Production files remain owned by their dedicated service accounts:

- Yerbas Core service: `yerbas`
- Explorer and PM2 service: `yerbexplorer`
- MongoDB service: `mongodb`
- Nginx service: `www-data`

Secrets are not placed in the invoking user's home directory.

## MongoDB on Ubuntu 26.04

MongoDB 8 currently publishes native Ubuntu packages for Ubuntu 24.04 (`noble`). The installer uses that official native repository on Ubuntu 26.04 and runs MongoDB directly as the `mongod` systemd service. MongoDB listens only on localhost and uses a generated authenticated database user.

Verify it with:

```bash
sudo systemctl status mongod --no-pager
sudo mongosh --quiet --eval 'db.runCommand({ ping: 1 })'
```

## Configuration

The explorer is installed at:

```text
/opt/yerb-multi-explorer
```

The launcher converts `settings.json.template` to strict JSON, and the privileged installer writes the generated MongoDB and Yerbas RPC values to:

```text
/opt/yerb-multi-explorer/settings.json
```

The final file is owned by `yerbexplorer` with mode `0600`.

Generated installer credentials are also stored with service-user-only permissions in:

```text
/opt/yerb-multi-explorer/.installer.env
/etc/yerbas/explorer.env
```

## Operations

Run administrative commands from your normal account with `sudo`:

```bash
sudo yerb-explorer-health
sudo yerb-explorer-update
sudo yerb-explorer-uninstall
```

View application logs:

```bash
sudo -u yerbexplorer env HOME=/home/yerbexplorer PM2_HOME=/home/yerbexplorer/.pm2 \
  pm2 logs yerb-multi-explorer
```

Restart the explorer:

```bash
sudo systemctl restart pm2-yerbexplorer
```

Check Yerbas Core:

```bash
sudo systemctl status yerbasd --no-pager
sudo -u yerbas yerbas-cli \
  -conf=/var/lib/yerbas/.yerbas/yerbas.conf \
  -datadir=/var/lib/yerbas/.yerbas \
  getblockchaininfo
```

Run initial indexing when needed:

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
| Yerbas data | `/var/lib/yerbas/.yerbas` |
| Yerbas environment | `/etc/yerbas/explorer.env` |
| Nginx site | `/etc/nginx/sites-available/yerb-multi-explorer` |
| Installer log | `/var/log/yerb-multi-explorer-install.log` |
| PM2 state | `/home/yerbexplorer/.pm2` |
| MongoDB data | `/var/lib/mongodb` |
| MongoDB configuration | `/etc/mongod.conf` |
| Bootstrap cache | `/var/cache/yerbas-bootstrap` |
| Update backups | `/var/backups/yerb-multi-explorer` |

## Notes

- Always launch installation from a normal sudo-enabled account.
- The launcher refuses direct root execution.
- The privileged installer still runs as root internally because package installation, systemd, Nginx, UFW, and `/opt` changes require it.
- The installer applies the Express-compatible regular-expression wildcard route when it finds the legacy `app.get('*', ...)` form.
- The npm major-version notice can be ignored; the application is installed using the Node.js 22 toolchain selected by the installer.
