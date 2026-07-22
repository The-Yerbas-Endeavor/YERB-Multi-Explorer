# YERB Multi-Explorer

A modern, native explorer built specifically for the Yerbas blockchain.

This is a new codebase. It does not embed, import, redirect to, or require the legacy Yerbas explorers at runtime.

## Technology

- Node.js 22
- TypeScript
- Fastify
- MongoDB
- Redis and BullMQ
- Socket.IO live events
- Vue 3
- Tailwind CSS 4
- PM2 process composition
- Docker Compose for MongoDB, Redis, API, indexer, and web deployment

## Five-phase implementation

### Phase 1: data architecture

MongoDB models are included for:

- blocks
- transactions
- addresses
- assets
- asset activity
- synchronization state

The schema is designed to expand with asset holders, smartnodes, market history, mempool state, peers, rich lists, charts, and governance data.

### Phase 2: explorer API

The Fastify API currently includes:

```text
GET  /api/v1/health
GET  /api/v1/dashboard
GET  /api/v1/blocks
GET  /api/v1/blocks/:height-or-hash
GET  /api/v1/transactions/:txid
GET  /api/v1/assets
GET  /api/v1/assets/:name
GET  /api/v1/search?q=
POST /api/v1/admin/sync
GET  /docs
```

OpenAPI documentation is served at `/docs`.

### Phase 3: application pages

The Vue application establishes the visual system and dashboard for:

- dashboard
- block explorer
- transaction explorer
- address explorer
- asset explorer
- smartnodes
- network
- markets
- charts
- search
- API documentation

The current dashboard includes live network status, chain and indexed heights, recent blocks, recent transactions, asset activity, synchronization progress, and global search.

### Phase 4: indexing engine

The indexer uses Redis and BullMQ instead of cron-only synchronization.

Implemented behavior:

- resumes from persisted synchronization state
- queues blocks in configurable batches
- prevents duplicate block jobs with deterministic job IDs
- retries failed jobs with exponential backoff
- indexes blocks and transactions
- detects native asset events exposed by Yerbas RPC transaction data
- upserts asset definitions and activity
- publishes live explorer events through Redis
- shuts down safely under PM2 or Docker

The exact Yerbas asset-event decoder may require adjustment to match the final RPC transaction payload produced by the deployed Yerbas Core version. Raw block and transaction payloads are retained to make decoder upgrades and reindexing possible.

### Phase 5: live frontend and deployment

The Vue 3 and Tailwind frontend receives live block events through Socket.IO. PM2 runs the API and indexer as separate managed processes. Docker Compose supplies a complete service layout.

## Repository layout

```text
YERB-Multi-Explorer/
├── apps/
│   ├── api/
│   │   ├── src/
│   │   │   ├── config.ts
│   │   │   ├── core.ts
│   │   │   ├── server.ts
│   │   │   └── workers/indexer.ts
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── web/
│       ├── src/
│       │   ├── App.vue
│       │   ├── main.ts
│       │   └── styles.css
│       ├── index.html
│       ├── package.json
│       └── vite.config.ts
├── .env.example
├── docker-compose.yml
├── ecosystem.config.cjs
└── package.json
```

## Yerbas Core requirements

The explorer requires a fully synchronized Yerbas Core node with RPC enabled and the indexes needed by address and asset queries.

Example `yerbas.conf`:

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

Do not expose the RPC port publicly.

## Local development

Requirements:

- Node.js 22
- MongoDB 8
- Redis 7
- synchronized Yerbas Core RPC

Clone and configure:

```bash
git clone https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git
cd YERB-Multi-Explorer
cp .env.example .env
nano .env
npm install
```

Start MongoDB and Redis, then run:

```bash
npm run dev
```

Frontend:

```text
http://127.0.0.1:5173
```

API:

```text
http://127.0.0.1:3001
```

API documentation:

```text
http://127.0.0.1:3001/docs
```

## Build and validate

```bash
npm install
npm run typecheck
npm run build
```

## PM2 deployment

Build the applications:

```bash
npm ci
npm run build
```

Start the API and indexer:

```bash
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup
```

Inspect processes and logs:

```bash
pm2 status
pm2 logs yerb-explorer-api
pm2 logs yerb-explorer-indexer
```

The compiled Vue frontend is located in:

```text
apps/web/dist
```

Serve that directory through Nginx and proxy `/api/` and `/socket.io/` to `127.0.0.1:3001`.

## Docker Compose deployment

Create the production environment file:

```bash
cp .env.example .env
nano .env
```

Start the stack:

```bash
docker compose up -d
```

View service status and logs:

```bash
docker compose ps
docker compose logs -f api
docker compose logs -f web
```

The compose stack binds the API and frontend to localhost so Nginx can be the only public entry point.

## Initial synchronization

The API automatically queues missing blocks in small batches. The dedicated indexer consumes those jobs and stores indexed results.

Monitor synchronization:

```bash
curl http://127.0.0.1:3001/api/v1/health
```

Example response:

```json
{
  "status": "ok",
  "chainHeight": 1500000,
  "indexedHeight": 1499950,
  "queue": "indexed"
}
```

## Production work still required

This branch establishes all five phases as an integrated, runnable architecture. Before declaring the explorer production-complete, the following Yerbas-specific modules should be expanded and tested against a real node:

- exact asset issue, reissue, transfer, restricted asset, qualifier, and tag decoding
- address balance and address transaction indexing
- chain reorganization rollback and replay
- mempool ingestion
- smartnode indexing
- holder snapshots and historical ownership
- market adapters
- peer and network analytics
- chart aggregation
- admin authentication for synchronization controls
- integration tests using captured Yerbas RPC fixtures
- hardened Nginx and Ubuntu 26 installer

## Security

- Keep Yerbas RPC bound to localhost.
- Keep MongoDB and Redis private.
- Replace all example credentials.
- Protect administrative API routes before public deployment.
- Put Nginx and HTTPS in front of the API and frontend.
- Back up MongoDB before schema migrations or full reindex operations.

## License

Use is subject to the repository license and the policies of The Yerbas Endeavor.
