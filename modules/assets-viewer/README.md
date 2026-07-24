# Yerbas Asset Explorer

A lightweight, self-hosted asset explorer for the Yerbas blockchain.

The explorer reads asset data from a local Yerbas Core RPC node, stores indexed data in SQLite, and serves a responsive PHP interface and JSON API through Nginx.

## Features

- Browse and search Yerbas assets
- Asset supply, units, type, IPFS status, and reissuability
- Holder counts and holder balance pages
- SQLite-backed asset index for fast page loads
- Recent asset issue, transfer, and reissue activity
- Paginated JSON API
- Automatic synchronization with a systemd timer
- Responsive dark/light interface
- Live RPC fallback when cached data is unavailable

## Requirements

Recommended server:

- Ubuntu 22.04 or newer
- Nginx
- PHP 8.1 or newer
- PHP-FPM
- PHP cURL extension
- PHP SQLite extension
- Git
- A fully synchronized Yerbas Core node with asset indexes enabled

The Yerbas daemon and explorer may run on the same server. Keeping RPC bound to `127.0.0.1` is strongly recommended.

## 1. Configure Yerbas Core

Edit the Yerbas configuration file:

```bash
nano ~/.yerbas/yerbas.conf
```

Example configuration:

```ini
server=1
daemon=1
listen=1

rpcuser=CHANGE_THIS_RPC_USERNAME
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

Restart Yerbas Core after changing the configuration:

```bash
yerbas-cli stop
yerbasd -daemon
```

Confirm that RPC is listening locally:

```bash
sudo ss -lntp | grep 8766
```

Test the node:

```bash
yerbas-cli getblockchaininfo
yerbas-cli listassets
```

Do not expose port `8766` publicly.

## 2. Install server packages

```bash
sudo apt update
sudo apt install -y \
  nginx \
  git \
  php-fpm \
  php-curl \
  php-sqlite3 \
  sqlite3
```

Check the installed PHP version and FPM socket:

```bash
php -v
ls -l /run/php/
```

Examples include:

```text
/run/php/php8.1-fpm.sock
/run/php/php8.3-fpm.sock
```

Use the socket that exists on your server in the Nginx configuration below.

## 3. Clone the explorer

```bash
sudo mkdir -p /var/www
cd /var/www
sudo git clone https://github.com/The-Yerbas-Endeavor/Yerbas-Assets-Viewer.git
sudo chown -R "$USER":www-data /var/www/Yerbas-Assets-Viewer
cd /var/www/Yerbas-Assets-Viewer
```

## 4. Configure the explorer

Edit:

```bash
nano /var/www/Yerbas-Assets-Viewer/config.php
```

Set the RPC values to match `yerbas.conf`:

```php
<?php
$cfg['rpcUsername'] = 'CHANGE_THIS_RPC_USERNAME';
$cfg['rpcPassword'] = 'CHANGE_THIS_TO_A_LONG_RANDOM_PASSWORD';
$cfg['rpcHostIP'] = '127.0.0.1';
$cfg['rpcHostPort'] = 8766;
$cfg['rpcURL'] = '';

$cfg['theme'] = 'w3css';
$cfg['wordFilter'] = '';
$cfg['filterReplaceChar'] = '&hearts;';

$cfg['databasePath'] = __DIR__ . '/storage/assets.sqlite';
$cfg['assetsPerPage'] = 50;
$cfg['activityInitialBlocks'] = 500;
?>
```

Important:

- `rpcUsername` must match `rpcuser`.
- `rpcPassword` must match `rpcpassword`.
- Use `127.0.0.1` when Yerbas Core runs on the same server.
- Keep `rpcURL` empty.
- Never commit production RPC credentials to GitHub.

## 5. Configure Nginx

Create the site configuration:

```bash
sudo nano /etc/nginx/sites-available/assetsviewer.yerbas.org
```

Example:

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name assetsviewer.yerbas.org;

    root /var/www/Yerbas-Assets-Viewer;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }

    location ^~ /storage/ {
        deny all;
    }

    location ^~ /src/ {
        deny all;
    }

    location ^~ /scripts/ {
        deny all;
    }

    location ^~ /deploy/ {
        deny all;
    }

    location ^~ /docs/ {
        deny all;
    }

    location ~ /\. {
        deny all;
    }

    access_log /var/log/nginx/assetsviewer-access.log;
    error_log /var/log/nginx/assetsviewer-error.log;
}
```

Replace `php8.1-fpm.sock` with the PHP-FPM socket installed on your server.

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/assetsviewer.yerbas.org \
  /etc/nginx/sites-enabled/assetsviewer.yerbas.org

sudo nginx -t
sudo systemctl reload nginx
```

If the default Nginx site conflicts with this host, remove it:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

## 6. Prepare SQLite storage

```bash
cd /var/www/Yerbas-Assets-Viewer

sudo mkdir -p storage
sudo chown -R www-data:www-data storage
sudo chmod 775 storage

sudo chmod +x scripts/run-sync.sh
sudo chmod +x scripts/sync-assets.php
sudo chmod +x scripts/sync-activity.php
```

Run the first synchronization:

```bash
sudo -u www-data ./scripts/run-sync.sh
```

The first asset synchronization queries metadata and holder counts for every asset and may take longer than later incremental runs.

Confirm that the database was created:

```bash
ls -lh storage/
```

## 7. Install automatic synchronization

Copy the included systemd units:

```bash
sudo cp deploy/yerbas-assets-sync.service /etc/systemd/system/
sudo cp deploy/yerbas-assets-sync.timer /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now yerbas-assets-sync.timer
```

Run an immediate synchronization:

```bash
sudo systemctl start yerbas-assets-sync.service
```

Check status and logs:

```bash
systemctl status yerbas-assets-sync.timer --no-pager
sudo journalctl -u yerbas-assets-sync.service -n 100 --no-pager
```

Follow synchronization logs live:

```bash
sudo journalctl -u yerbas-assets-sync.service -f
```

## 8. Test the explorer

Test Nginx locally:

```bash
curl -I -H 'Host: assetsviewer.yerbas.org' http://127.0.0.1/
```

Test the API status endpoint:

```bash
curl -s \
  -H 'Host: assetsviewer.yerbas.org' \
  'http://127.0.0.1/api/?resource=status'
```

Test indexed assets:

```bash
curl -s \
  -H 'Host: assetsviewer.yerbas.org' \
  'http://127.0.0.1/api/?resource=assets&per_page=5'
```

Test recent activity:

```bash
curl -s \
  -H 'Host: assetsviewer.yerbas.org' \
  'http://127.0.0.1/api/?resource=activity&limit=10'
```

Open the site:

```text
http://assetsviewer.yerbas.org/
```

## 9. Enable HTTPS

After DNS points to the server, install Certbot:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d assetsviewer.yerbas.org
```

Test automatic renewal:

```bash
sudo certbot renew --dry-run
```

## API examples

### Cache and synchronization status

```text
/api/?resource=status
```

### Network statistics

```text
/api/?resource=stats
```

### Paginated assets

```text
/api/?resource=assets
/api/?resource=assets&page=2&per_page=25
/api/?resource=assets&q=YERB
/api/?resource=assets&type=Unique
```

### Exact asset lookup

```text
/api/?resource=asset&name=ASSET_NAME
```

### Recent activity

```text
/api/?resource=activity&limit=25
/api/?resource=activity&asset=ASSET_NAME
```

### Unified search

```text
/api/?resource=search&q=YERB
```

## Updating the explorer

Because `config.php` contains local production settings, back it up before pulling updates:

```bash
cd /var/www/Yerbas-Assets-Viewer
cp config.php /tmp/yerbas-assets-config.php

git restore config.php
git pull --rebase origin main

cp /tmp/yerbas-assets-config.php config.php
sudo chmod +x scripts/run-sync.sh scripts/sync-assets.php scripts/sync-activity.php
sudo -u www-data ./scripts/run-sync.sh

sudo systemctl restart php-fpm
sudo systemctl reload nginx
```

On systems where the PHP-FPM service includes a version number, restart that service instead, for example:

```bash
sudo systemctl restart php8.1-fpm
```

## Troubleshooting

### `Unable to connect` or `unknown RPC error`

Verify the explorer configuration:

```bash
sudo -u www-data php -r '
require "config.php";
var_dump($cfg["rpcHostIP"], $cfg["rpcHostPort"]);
'
```

Expected host:

```text
127.0.0.1
```

Test RPC directly:

```bash
curl -sS \
  --user 'RPC_USERNAME:RPC_PASSWORD' \
  --data-binary '{"jsonrpc":"1.0","id":"test","method":"listassets","params":[]}' \
  -H 'Content-Type: application/json' \
  -w '\nHTTP status: %{http_code}\n' \
  http://127.0.0.1:8766/
```

### PHP-FPM socket error

List available sockets:

```bash
ls -l /run/php/
```

Update `fastcgi_pass` in the Nginx server block to use the socket that exists.

### SQLite permission error

```bash
sudo chown -R www-data:www-data /var/www/Yerbas-Assets-Viewer/storage
sudo chmod 775 /var/www/Yerbas-Assets-Viewer/storage
```

### Git refuses to pull because of local changes

Check:

```bash
git status
```

Preserve the production config and restore generated script changes:

```bash
cp config.php /tmp/yerbas-assets-config.php
git restore config.php scripts/run-sync.sh scripts/sync-assets.php scripts/sync-activity.php
git pull --rebase origin main
cp /tmp/yerbas-assets-config.php config.php
```

### Nginx logs

```bash
sudo tail -n 100 /var/log/nginx/assetsviewer-error.log
sudo tail -n 100 /var/log/nginx/assetsviewer-access.log
```

### Sync service logs

```bash
sudo journalctl -u yerbas-assets-sync.service -n 100 --no-pager
```

## Security notes

- Never expose the Yerbas RPC port to the public internet.
- Use a long random RPC password.
- Keep RPC bound to `127.0.0.1` when possible.
- Do not commit production `config.php` credentials.
- Block direct web access to `storage`, `src`, `scripts`, `deploy`, and `docs`.
- Keep Ubuntu, Nginx, PHP, and Yerbas Core updated.
- Use HTTPS for the public site.

## Project layout

```text
Yerbas-Assets-Viewer/
├── api/                 JSON API
├── deploy/              systemd service and timer
├── docs/                additional documentation
├── scripts/             asset and activity synchronization
├── src/                 SQLite database layer
├── storage/             generated SQLite database
├── theme/               web interface templates and styles
├── config.php           local RPC and explorer configuration
├── index.php             web entry point
├── rpc.php               Yerbas JSON-RPC client
└── yerbassetsviewer.php  application controller
```

## License

See the source files and repository history for applicable licensing information.

## Links

- Yerbas website: https://yerbas.org/
- Yerbas block explorer: https://explorer.yerbas.org/
- Yerbas Core: https://github.com/The-Yerbas-Endeavor/yerbas
