# SQLite cache and JSON API

## Requirements

Install the SQLite PHP extension:

```bash
sudo apt update
sudo apt install php8.1-sqlite3
sudo systemctl restart php8.1-fpm
```

## Configuration

The default database path is:

```text
/var/www/Yerbas-Assets-Viewer/storage/assets.sqlite
```

Optionally set a custom path in `config.php`:

```php
$cfg['databasePath'] = __DIR__ . '/storage/assets.sqlite';
```

## Initialize and test the index

```bash
cd /var/www/Yerbas-Assets-Viewer
chmod +x scripts/run-sync.sh scripts/sync-assets.php
sudo mkdir -p storage
sudo chown -R www-data:www-data storage
sudo -u www-data ./scripts/run-sync.sh
```

The initial run queries metadata and holder counts for every asset, so it is the most expensive run.

## Install the systemd timer

```bash
sudo cp deploy/yerbas-assets-sync.service /etc/systemd/system/
sudo cp deploy/yerbas-assets-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now yerbas-assets-sync.timer
```

Inspect it with:

```bash
systemctl status yerbas-assets-sync.timer --no-pager
sudo journalctl -u yerbas-assets-sync.service -n 100 --no-pager
```

## API endpoints

### List and search assets

```text
/api/?resource=assets
/api/?resource=assets&q=YERB&page=1&per_page=25
/api/?resource=assets&type=Unique
```

### Exact asset lookup

```text
/api/?resource=asset&name=ASSET_NAME
```

### Cache and synchronization status

```text
/api/?resource=status
```

All endpoints return JSON. List responses include pagination metadata.

## Permissions and security

The `storage` directory must be writable by the account running the sync service. The SQLite file is not intended to be downloaded directly. Add this to the Nginx server block:

```nginx
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
```
