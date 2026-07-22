# YERB Multi-Explorer

A modern, native Yerbas blockchain explorer built with Node.js 22, TypeScript, Fastify, MongoDB, Redis, Socket.IO, Vue 3, Tailwind CSS, PM2, and Nginx.

Docker is not required.

## Recommended platform

**Ubuntu 26 LTS on AMD64 is the primary and recommended installation target.**

Also supported:

- Ubuntu 26 LTS ARM64
- Debian 13 AMD64
- Debian 13 ARM64

The main installation guide below is written for Ubuntu 26. Debian 13 and ARM64 differences are documented near the end.

## Requirements

- Fully synchronized Yerbas Core node
- 4 CPU cores minimum
- 8 GB RAM minimum
- SSD storage
- Domain name for HTTPS
- Non-root sudo user

## Ubuntu 26 installation

### 1. Update the server

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
redis-cli ping
```

Expected Redis response:

```text
PONG
```

### 2. Install Node.js 22 and PM2

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pm2
```

Verify:

```bash
node --version
npm --version
pm2 --version
```

The Node.js version must begin with `v22`.

### 3. Install or connect MongoDB

Use MongoDB 8 on a supported Ubuntu host or connect to a private MongoDB server.

Example local connection string:

```text
mongodb://127.0.0.1:27017/yerbas_explorer
```

Example remote connection string:

```text
mongodb://explorer_user:STRONG_PASSWORD@10.0.0.20:27017/yerbas_explorer?authSource=admin
```

Do not expose MongoDB to the public internet.

### 4. Configure Yerbas Core

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

Verify RPC access:

```bash
yerbas-cli getblockchaininfo
yerbas-cli getnetworkinfo
```

Never expose RPC port `8766` publicly.

### 5. Create the explorer account

```bash
sudo adduser --disabled-password --gecos "" yerbexplorer
sudo mkdir -p /var/www/yerb-explorer
sudo chown -R yerbexplorer:yerbexplorer /var/www/yerb-explorer
sudo -iu yerbexplorer
```

### 6. Clone the repository

```bash
cd /var/www/yerb-explorer
git clone https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git .
```

### 7. Configure the environment

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

Protect the file:

```bash
chmod 600 .env
```

### 8. Install and build

```bash
npm ci
npm run typecheck
npm run build
```

Build output:

```text
apps/web/dist
apps/api/dist
```

### 9. Start with PM2

```bash
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup systemd -u yerbexplorer --hp /home/yerbexplorer
```

PM2 prints a command beginning with `sudo`. Run that command, then save the process list again:

```bash
exit
sudo -iu yerbexplorer pm2 save
```

Check status:

```bash
sudo -iu yerbexplorer pm2 status
sudo -iu yerbexplorer pm2 logs --lines 100
```

### 10. Configure Nginx

Create:

```bash
sudo nano /etc/nginx/sites-available/explorer.yerbas.org
```

Use:

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

### 11. Enable HTTPS

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d explorer.yerbas.org
sudo certbot renew --dry-run
```

### 12. Verify the explorer

```bash
curl http://127.0.0.1:3001/api/v1/health
curl https://explorer.yerbas.org/api/v1/health
```

Open:

```text
https://explorer.yerbas.org
https://explorer.yerbas.org/docs
```

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

## Debian 13 installation

Use the Ubuntu 26 procedure for Node.js 22, Redis, PM2, Nginx, Yerbas Core, the explorer build, and HTTPS.

The main difference is MongoDB: MongoDB Community may not provide an officially supported Debian 13 APT package. For production, connect the Debian 13 explorer server to MongoDB 8 running on a supported private host.

## ARM64 installation

The same Ubuntu 26 instructions work on ARM64 systems such as Ampere, AWS Graviton, Oracle ARM, and supported Raspberry Pi hardware.

Confirm the architecture:

```bash
uname -m
dpkg --print-architecture
```

Expected output:

```text
aarch64
arm64
```

Use ARM64 builds of Node.js, MongoDB, and Yerbas Core. The explorer source does not require architecture-specific changes.

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

Confirm that `.env` and `~/.yerbas/yerbas.conf` use the same RPC username, password, URL, and port.

### MongoDB connection fails

Confirm that MongoDB is running, authentication is correct, and port `27017` is reachable only over localhost or a private network.

### Nginx returns 502

```bash
sudo -iu yerbexplorer pm2 status
curl http://127.0.0.1:3001/api/v1/health
sudo tail -n 100 /var/log/nginx/error.log
```

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

## Security

- Keep Yerbas RPC bound to localhost.
- Keep Redis private and bound to localhost.
- Keep MongoDB private and require authentication.
- Never commit `.env`.
- Use the dedicated `yerbexplorer` account.
- Expose only ports 80 and 443 publicly.
- Protect administrative API routes before production use.

## License

Use is subject to the repository license and the policies of The Yerbas Endeavor.
