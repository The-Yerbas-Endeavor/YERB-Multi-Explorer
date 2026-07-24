# Official Yerbas Portal Installer

Production installer for the Yerbas Portal on **Ubuntu 24.04 LTS**.

It installs and configures the complete portal stack without Docker:

- Yerbas Core (`yerbasd` and `yerbas-cli`)
- latest indexed Yerbas blockchain bootstrap
- MongoDB 8 with authenticated localhost access
- Node.js 22 and PM2
- the latest Yerbas Portal frontend and explorer backend
- Nginx reverse proxy and API rate limiting
- optional Let's Encrypt HTTPS
- UFW firewall and unattended security updates
- systemd services, update command, health check, and uninstall command

## Required server

- Ubuntu 24.04 LTS
- normal non-root account with sudo access
- AMD64 or ARM64
- at least 45 GB free disk space
- approximately 2 GB RAM minimum; 4 GB or more recommended
- DNS pointed to the server before requesting HTTPS

The installer must be run as your normal sudo-enabled account. Do not use `sudo -i` and do not run the public launcher as root.

## One-command installation

The official portal domain defaults to `explorer2.yerbas.org`:

```bash
curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh | bash
```

The script asks only for the account's sudo password. It automatically generates secure Yerbas RPC and MongoDB credentials, downloads the current source, loads the blockchain bootstrap, configures services, requests HTTPS, and performs final health checks.

### Use another domain

```bash
curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh \
  | DOMAIN=portal.yerbas.org bash
```

### Install without HTTPS

```bash
curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh \
  | ENABLE_SSL=no bash
```

### Skip the blockchain bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh \
  | INSTALL_BOOTSTRAP=no bash
```

## Manual interactive installation

For advanced installations where credentials and options should be entered manually:

```bash
git clone https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git
cd YERB-Multi-Explorer
chmod +x installer/install-sudo-user.sh
bash installer/install-sudo-user.sh
```

## What the automatic installer does

1. Verifies Ubuntu 24.04, architecture, kernel compatibility, memory, disk space, required commands, and sudo access.
2. Downloads the selected repository branch into `/var/tmp/yerbas-portal-installer`.
3. Generates 256-bit URL-safe RPC and MongoDB passwords.
4. Installs Yerbas Core and creates the locked-down `yerbas` service account.
5. Downloads and verifies the latest explorer bootstrap-index release.
6. Installs MongoDB 8, creates the authenticated explorer database user, and binds MongoDB to localhost.
7. Installs Node.js 22 and PM2.
8. clones the Portal into `/opt/yerb-multi-explorer`, installs locked dependencies, and generates `settings.json`.
9. Creates the `yerbexplorer` service account and PM2 systemd unit.
10. Configures Nginx, UFW, unattended upgrades, and optional Let's Encrypt HTTPS.
11. Installs administrative commands and verifies Core, MongoDB, PM2, Nginx, and HTTP health.

## Operations

```bash
sudo yerb-explorer-health
sudo yerb-explorer-update
sudo yerb-explorer-uninstall
sudo systemctl status yerbasd --no-pager
sudo systemctl status pm2-yerbexplorer --no-pager
```

Portal logs:

```bash
sudo -u yerbexplorer env HOME=/home/yerbexplorer PM2_HOME=/home/yerbexplorer/.pm2 \
  pm2 logs yerb-multi-explorer
```

Core synchronization status:

```bash
sudo -u yerbas yerbas-cli \
  -conf=/var/lib/yerbas/.yerbas/yerbas.conf \
  -datadir=/var/lib/yerbas/.yerbas \
  getblockchaininfo
```

## Important paths

| Purpose | Path |
|---|---|
| Portal application | `/opt/yerb-multi-explorer` |
| Yerbas blockchain data | `/var/lib/yerbas/.yerbas` |
| Yerbas RPC environment | `/etc/yerbas/explorer.env` |
| Portal environment | `/opt/yerb-multi-explorer/.installer.env` |
| Nginx configuration | `/etc/nginx/sites-available/yerb-multi-explorer` |
| Installer log | `/var/log/yerb-multi-explorer-install.log` |
| PM2 state | `/home/yerbexplorer/.pm2` |
| MongoDB data | `/var/lib/mongodb` |
| Bootstrap cache | `/var/cache/yerbas-bootstrap` |
| Update backups | `/var/backups/yerb-multi-explorer` |

Credentials are stored only in root/service-account-readable files. The browser is never given Yerbas RPC credentials, MongoDB credentials, private keys, seed phrases, or `wallet.dat` access.
