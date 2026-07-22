# YERB Multi-Explorer

A modern, native Yerbas blockchain explorer built with Node.js 22, TypeScript, Fastify, MongoDB, Redis, Socket.IO, Vue 3, Tailwind CSS, PM2, and Nginx.

This project does not require Docker and does not depend on the legacy Yerbas explorers at runtime.

## Supported installation targets

- Ubuntu 26, AMD64 or ARM64
- Debian 13, AMD64 or ARM64

The application, Node.js, Redis, PM2, Nginx, and Yerbas Core can run natively on both architectures.

> **MongoDB note:** MongoDB Community does not currently publish an officially supported Debian 13 package. On Debian 13, use a MongoDB server on a supported Linux host and set `MONGODB_URI` to that server. A manual MongoDB tarball installation may work, but it is not recommended for production.

## Requirements

- A fully synchronized Yerbas Core node
- 4 CPU cores minimum
- 8 GB RAM minimum
- SSD storage sized for Yerbas Core, MongoDB, indexes, and future growth
- A domain name for public HTTPS deployment
- A non-root sudo user

For ARM64, confirm the machine reports `arm64`:

```bash
uname -m
dpkg --print-architecture
```

Expected output is `aarch64` and `arm64`.

## 1. Update the operating system

These commands are the same on Ubuntu 26 and Debian 13:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y \
  git curl ca-certificates gnupg build-essential \
  nginx redis-server lsb-release
```

Enable Redis and Nginx:

```bash
sudo systemctl enable --now redis-server
sudo systemctl enable --now nginx
```

Verify Redis:

```bash
redis-cli ping
```

Expected response:

```text
PONG
```

## 2. Install Node.js 22

NodeSource supports both AMD64 and ARM64.

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

Verify the installation:

```bash
node --version
npm --version
```

The Node.js version must begin with `v22`.

Install PM2:

```bash
sudo npm install -g pm2
pm2 --version
```

## 3. Install or connect MongoDB

### Ubuntu 26

MongoDB may not yet provide a repository specifically labeled for Ubuntu 26. Use a supported MongoDB 8 installation available for your architecture, or connect the explorer to a MongoDB server running on a supported host.

After MongoDB is available, verify it is listening only on a private interface or localhost.

Example local connection string:

```text
mongodb://127.0.0.1:27017/yerbas_explorer
```

### Debian 13

MongoDB Community does not currently provide an officially supported Debian 13 APT package. The recommended production arrangement is:

```text
Debian 13 explorer server
        |
        | private network
        v
MongoDB 8 on a supported Linux host
```

Example remote connection string:

```text
mongodb://explorer_user:STRONG_PASSWORD@10.0.0.20:27017/yerbas_explorer?authSource=admin
```

Do not expose MongoDB directly to the public internet.

### ARM64

Use an ARM64 MongoDB build on a supported ARM64 operating system, or connect the ARM64 explorer server to a separate supported MongoDB host.

The explorer itself requires no architecture-specific code changes.

## 4. Configure Yerbas Core

The explorer requires a fully synchronized Yerbas Core node with RPC and indexes enabled.

Edit:

```bash
nano ~/.yerbas/yerbas.conf
```

Add or confirm:

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

Restart Yerbas Core after changing index settings. A reindex may be required:

```bash
yerbas-cli stop
yerbasd -daemon -reindex
```

Do not expose port `8766` publicly.

Verify RPC access:

```bash
yerbas-cli getblockchaininfo
yerbas-cli getnetworkinfo
```

## 5. Create an explorer user

```bash
sudo adduser --disabled-password --gecos "" yerbexplorer
sudo mkdir -p /var/www/yerb-explorer
sudo chown -R yerbexplorer:yerbexplorer /var/www/yerb-explorer
```

Switch to the explorer user:

```bash
sudo -iu yerbexplorer
```

## 6. Clone the explorer

```bash
cd /var/www/yerb-explorer
git clone https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git .
```

For the current modernization branch before it is merged:

```bash
git checkout agent/modern-yerbas-explorer
```

## 7. Configure the environment

```bash
cp .env.example .env
nano .env
```

Minimum production configuration:

```env
NODE_ENV=production
API_HOST=127.0.0.1
API_PORT=3001

MONGODB_URI=mongodb://127.0.0.1:27017/yerbas_explorer
REDIS_URL=redis://127.0.0.1:6379

YERB_RPC_URL=http://127.0.0.1:8766
YERB_RPC_USER=CHANGE_THIS_USERNAME
YERB_RPC_PASSWORD=CHANGE_THIS_TO_A_LONG_RANDOM_PASSWORD

SYNC_BATCH_SIZE=25
CORS_ORIGIN=https://explorer.yerbas.org
```

For a remote MongoDB server, replace `MONGODB_URI` with its private connection string.

Protect the environment file:

```bash
chmod 600 .env
```

## 8. Install and build

```bash
npm ci
npm run typecheck
npm run build
```

The compiled frontend is created in:

```text
apps/web/dist
```

The compiled API and indexer are created under:

```text
apps/api/dist
```

## 9. Start with PM2

```bash
pm2 start ecosystem.config.cjs
pm2 save
```

Create the system startup service:

```bash
pm2 startup systemd -u yerbexplorer --hp /home/yerbexplorer
```

PM2 prints one command beginning with `sudo`. Exit the explorer account, run that command, then save again:

```bash
exit
sudo -iu yerbexplorer pm2 save
```

Check application status:

```bash
sudo -iu yerbexplorer pm2 status
sudo -iu yerbexplorer pm2 logs --lines 100
```

## 10. Configure Nginx

Create the site configuration:

```bash
sudo nano /etc/nginx/sites-available/explorer.yerbas.org
```

Use this configuration and replace the domain when needed:

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name explorer.yerbas.org;

    root /var/www/yerb-explorer/apps/web/dist;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /socket.io/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /docs {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/explorer.yerbas.org \
  /etc/nginx/sites-enabled/explorer.yerbas.org
sudo nginx -t
sudo systemctl reload nginx
```

## 11. Enable HTTPS

Install Certbot:

```bash
sudo apt install -y certbot python3-certbot-nginx
```

Request the certificate:

```bash
sudo certbot --nginx -d explorer.yerbas.org
```

Test renewal:

```bash
sudo certbot renew --dry-run
```

## 12. Verify the explorer

Check the API locally:

```bash
curl http://127.0.0.1:3001/api/v1/health
```

Check the public API:

```bash
curl https://explorer.yerbas.org/api/v1/health
```

Open:

```text
https://explorer.yerbas.org
https://explorer.yerbas.org/docs
```

The health response should report the Yerbas chain height, indexed height, and queue status.

## Updating

```bash
sudo -iu yerbexplorer
cd /var/www/yerb-explorer
git pull
npm ci
npm run typecheck
npm run build
pm2 restart ecosystem.config.cjs --update-env
pm2 save
exit
sudo systemctl reload nginx
```

## Common commands

```bash
sudo -iu yerbexplorer pm2 status
sudo -iu yerbexplorer pm2 logs yerb-explorer-api
sudo -iu yerbexplorer pm2 logs yerb-explorer-indexer
sudo systemctl status redis-server
sudo systemctl status nginx
sudo nginx -t
redis-cli ping
```

## Troubleshooting

### Node.js is not version 22

```bash
node --version
sudo apt remove -y nodejs
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

### Redis connection fails

```bash
sudo systemctl restart redis-server
redis-cli ping
```

### Yerbas RPC authentication fails

Confirm that `.env` and `~/.yerbas/yerbas.conf` contain the same RPC username, password, URL, and port.

### MongoDB connection fails

Confirm the MongoDB server is running, the account has access to `yerbas_explorer`, and any firewall permits port `27017` only from the explorer server's private address.

### Nginx returns 502 Bad Gateway

```bash
sudo -iu yerbexplorer pm2 status
curl http://127.0.0.1:3001/api/v1/health
sudo tail -n 100 /var/log/nginx/error.log
```

### ARM64 dependency build fails

Confirm the architecture and compiler tools:

```bash
dpkg --print-architecture
node --version
gcc --version
sudo apt install -y build-essential python3 make g++
rm -rf node_modules
npm ci
```

## Security

- Keep Yerbas RPC bound to localhost.
- Keep Redis private and bound to localhost.
- Keep MongoDB private and require authentication.
- Never commit `.env`.
- Use a dedicated unprivileged account for the explorer.
- Permit public access only to ports 80 and 443.
- Protect administrative API routes before public deployment.
- Back up MongoDB before migrations or full reindex operations.

## API

```text
GET  /api/v1/health
GET  /api/v1/dashboard
GET  /api/v1/coin
GET  /api/v1/blocks
GET  /api/v1/blocks/:height-or-hash
GET  /api/v1/transactions/:txid
GET  /api/v1/assets
GET  /api/v1/assets/:name
GET  /api/v1/network/history
GET  /api/v1/richlist
GET  /api/v1/search?q=
POST /api/v1/admin/sync
GET  /docs
```

## License

Use is subject to the repository license and the policies of The Yerbas Endeavor.
