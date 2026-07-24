# Official Yerbas Portal

The Yerbas Portal combines the blockchain explorer, network statistics, assets, markets, smartnodes, and future wallet and marketplace functionality in one application.

## Quick Start — Ubuntu 24.04 LTS

Run this from a **normal non-root account with sudo access**. Do not run the command with `sudo`, do not log in as `root`, and do not use `sudo -i`.

```bash
sudo apt update && sudo apt install -y curl

curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh | bash
```

The installer defaults to `explorer2.yerbas.org` and automatically installs:

- Yerbas Core (`yerbasd` and `yerbas-cli`)
- the latest indexed Yerbas blockchain bootstrap
- MongoDB 8 with authenticated localhost access
- Node.js 22 and PM2
- the Yerbas Portal frontend and explorer backend
- Nginx reverse proxy and API rate limiting
- UFW firewall and unattended security updates
- Let's Encrypt HTTPS when DNS is ready
- systemd services, health checks, update tools, and uninstall tools

## Server Requirements

- Ubuntu 24.04 LTS
- AMD64 or ARM64
- at least 45 GB free disk space
- approximately 2 GB RAM minimum; 4 GB or more recommended
- DNS for `explorer2.yerbas.org` pointed to the server before requesting HTTPS
- a normal user account with working sudo access

## Custom Installation Options

Use another domain:

```bash
curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh \
  | DOMAIN=portal.yerbas.org bash
```

Install without HTTPS:

```bash
curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh \
  | ENABLE_SSL=no bash
```

Skip the indexed blockchain bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/The-Yerbas-Endeavor/YERB-Multi-Explorer/main/installer/install-portal.sh \
  | INSTALL_BOOTSTRAP=no bash
```

## After Installation

```bash
sudo yerb-explorer-health
sudo yerb-explorer-update
sudo systemctl status yerbasd --no-pager
sudo systemctl status pm2-yerbexplorer --no-pager
sudo systemctl status mongod --no-pager
sudo systemctl status nginx --no-pager
```

Portal logs:

```bash
sudo -u yerbexplorer env HOME=/home/yerbexplorer PM2_HOME=/home/yerbexplorer/.pm2 \
  pm2 logs yerb-multi-explorer
```

Yerbas Core synchronization status:

```bash
sudo -u yerbas yerbas-cli \
  -conf=/var/lib/yerbas/.yerbas/yerbas.conf \
  -datadir=/var/lib/yerbas/.yerbas \
  getblockchaininfo
```

## Important Paths

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

## Security

Generated Yerbas RPC and MongoDB credentials are stored only in restricted root/service-account files. They are never exposed to the browser.

The Portal does not request or store:

- private keys
- seed phrases
- wallet passwords
- `wallet.dat`
- Yerbas daemon RPC credentials in browser code

The initial wallet integration should remain watch-only until a secure Yerbas wallet extension or local signing bridge is available.

## Detailed Installer Documentation

For manual installation, troubleshooting, bootstrap controls, custom domains, and service operations, see [`installer/README.md`](installer/README.md).

## Credits

This project includes and builds upon the eIquidus/Iquidus explorer codebase and the work of its original contributors. The Yerbas Portal frontend, installer, bootstrap integration, and Yerbas-specific configuration are maintained by The Yerbas Endeavor.
