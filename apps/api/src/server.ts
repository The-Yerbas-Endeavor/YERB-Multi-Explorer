import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import { Server as SocketServer } from 'socket.io';
import { config } from './config.js';
import { registerAddressRoutes } from './address-routes.js';
import {
  Address,
  Asset,
  AssetEvent,
  Block,
  MarketSnapshot,
  NetworkSnapshot,
  SyncState,
  Transaction,
  Utxo,
  connectDatabase,
  enqueueMissingBlocks,
  redis,
  rpc
} from './core.js';

const app = Fastify({ logger: true, trustProxy: true });
await app.register(cors, { origin: config.CORS_ORIGIN.split(',').map(v => v.trim()) });
await app.register(helmet);
await app.register(rateLimit, { max: 240, timeWindow: '1 minute' });
await app.register(swagger, {
  openapi: { info: { title: 'YERB Multi-Explorer API', version: '0.4.0' } }
});
await app.register(swaggerUi, { routePrefix: '/docs' });

async function safeRpc<T>(method: string, params: unknown[] = []): Promise<T | null> {
  try { return await rpc<T>(method, params); } catch { return null; }
}

app.get('/api/v1/health', async () => {
  const [height, state, addresses, unspentOutputs] = await Promise.all([
    safeRpc<number>('getblockcount'),
    SyncState.findOne({ key: 'blocks' }).lean(),
    Address.countDocuments(),
    Utxo.countDocuments({ spent: false })
  ]);
  return {
    status: height === null ? 'degraded' : 'ok',
    chainHeight: height,
    indexedHeight: state?.height ?? -1,
    queue: state?.status ?? 'idle',
    addresses,
    unspentOutputs
  };
});

app.get('/api/v1/coin', async () => {
  const [blockchain, mining, network, mempool, txoutset, peers, smartnodes, latestMarket, sync, indexedBlocks, indexedTransactions, assetCount, addressCount, utxoCount] = await Promise.all([
    safeRpc<any>('getblockchaininfo'),
    safeRpc<any>('getmininginfo'),
    safeRpc<any>('getnetworkinfo'),
    safeRpc<any>('getmempoolinfo'),
    safeRpc<any>('gettxoutsetinfo'),
    safeRpc<any[]>('getpeerinfo'),
    safeRpc<any>('smartnodelist', ['status']),
    MarketSnapshot.findOne().sort({ capturedAt: -1 }).lean(),
    SyncState.findOne({ key: 'blocks' }).lean(),
    Block.countDocuments(),
    Transaction.countDocuments(),
    Asset.countDocuments(),
    Address.countDocuments(),
    Utxo.countDocuments({ spent: false })
  ]);

  const smartnodeValues = smartnodes && typeof smartnodes === 'object' ? Object.values(smartnodes) : [];
  const activeSmartnodes = smartnodeValues.filter(value => String(value).toUpperCase().includes('ENABLED')).length;
  const totalSmartnodes = smartnodeValues.length;
  const circulatingSupply = Number(txoutset?.total_amount ?? txoutset?.total_coin ?? 0) || null;
  const price = Number(latestMarket?.price ?? 0) || null;
  const marketCap = price && circulatingSupply ? price * circulatingSupply : null;
  const tipTime = await Block.findOne().sort({ height: -1 }).select({ time: 1 }).lean();

  return {
    identity: {
      name: 'Yerbas', ticker: 'YERB', type: 'Proof of Work + Smartnodes', algorithm: 'GhostRider',
      consensus: 'PoW + deterministic smartnodes', maxSupply: 420000000, targetBlockTimeSeconds: 60, assetLayer: true
    },
    chain: {
      height: blockchain?.blocks ?? mining?.blocks ?? null,
      headers: blockchain?.headers ?? null,
      bestBlockHash: blockchain?.bestblockhash ?? null,
      difficulty: mining?.difficulty ?? blockchain?.difficulty ?? null,
      networkHashrate: mining?.networkhashps ?? null,
      verificationProgress: blockchain?.verificationprogress ?? null,
      chainwork: blockchain?.chainwork ?? null,
      chainSize: blockchain?.size_on_disk ?? null,
      pruned: blockchain?.pruned ?? false,
      tipTime: tipTime?.time ?? null
    },
    supply: {
      circulating: circulatingSupply,
      max: 420000000,
      percentMined: circulatingSupply ? (circulatingSupply / 420000000) * 100 : null,
      remaining: circulatingSupply ? 420000000 - circulatingSupply : null,
      marketCap,
      fullyDilutedValue: price ? price * 420000000 : null
    },
    market: latestMarket ? {
      exchange: latestMarket.exchange, pair: latestMarket.pair, price: latestMarket.price, bid: latestMarket.bid,
      ask: latestMarket.ask, high24h: latestMarket.high24h, low24h: latestMarket.low24h,
      volume24h: latestMarket.volume24h, updatedAt: latestMarket.capturedAt
    } : null,
    network: {
      connections: network?.connections ?? peers?.length ?? null,
      inbound: network?.connections_in ?? null,
      outbound: network?.connections_out ?? null,
      protocolVersion: network?.protocolversion ?? null,
      walletVersion: network?.version ?? null,
      subversion: network?.subversion ?? null,
      relayFee: network?.relayfee ?? null,
      peerCount: peers?.length ?? null,
      mempoolTransactions: mempool?.size ?? null,
      mempoolBytes: mempool?.bytes ?? null,
      mempoolUsage: mempool?.usage ?? null
    },
    smartnodes: {
      active: totalSmartnodes ? activeSmartnodes : null,
      total: totalSmartnodes || null,
      collateral: null,
      lockedSupply: null,
      roiAnnual: null
    },
    indexer: {
      indexedHeight: sync?.height ?? -1,
      status: sync?.status ?? 'idle',
      indexedBlocks,
      indexedTransactions,
      indexedAssets: assetCount,
      indexedAddresses: addressCount,
      unspentOutputs: utxoCount
    }
  };
});

app.get('/api/v1/dashboard', async () => {
  const [latestBlocks, latestTransactions, assets, assetEvents, sync, richList] = await Promise.all([
    Block.find().sort({ height: -1 }).limit(10).lean(),
    Transaction.find().sort({ blockHeight: -1, _id: -1 }).limit(10).lean(),
    Asset.countDocuments(),
    AssetEvent.find().sort({ blockHeight: -1, _id: -1 }).limit(10).lean(),
    SyncState.findOne({ key: 'blocks' }).lean(),
    Address.find({ balance: { $gt: 0 } }).sort({ balance: -1 }).limit(10).select({ address: 1, balance: 1 }).lean()
  ]);
  return { latestBlocks, latestTransactions, assetCount: assets, assetEvents, sync, richList };
});

app.get('/api/v1/network/history', async request => {
  const hours = Math.min(24 * 365, Math.max(1, Number((request.query as { hours?: string }).hours ?? 24)));
  const since = new Date(Date.now() - hours * 60 * 60 * 1000);
  return NetworkSnapshot.find({ capturedAt: { $gte: since } }).sort({ capturedAt: 1 }).lean();
});

app.get('/api/v1/richlist', async request => {
  const limit = Math.min(500, Math.max(1, Number((request.query as { limit?: string }).limit ?? 100)));
  const [items, aggregate] = await Promise.all([
    Address.find({ balance: { $gt: 0 } }).sort({ balance: -1 }).limit(limit).select({ address: 1, balance: 1, received: 1, sent: 1, txCount: 1 }).lean(),
    Address.aggregate([{ $match: { balance: { $gt: 0 } } }, { $group: { _id: null, total: { $sum: '$balance' }, addresses: { $sum: 1 } } }])
  ]);
  const total = Number(aggregate[0]?.total ?? 0);
  return { total, addresses: Number(aggregate[0]?.addresses ?? 0), items: items.map((item, index) => ({ ...item, rank: index + 1, percent: total ? (Number(item.balance) / total) * 100 : 0 })) };
});

app.get('/api/v1/blocks', async request => {
  const query = request.query as { page?: string; limit?: string };
  const page = Math.max(1, Number(query.page ?? 1));
  const limit = Math.min(100, Math.max(1, Number(query.limit ?? 25)));
  const [items, total] = await Promise.all([
    Block.find().sort({ height: -1 }).skip((page - 1) * limit).limit(limit).lean(),
    Block.countDocuments()
  ]);
  return { page, limit, total, items };
});

app.get('/api/v1/blocks/:id', async (request, reply) => {
  const id = (request.params as { id: string }).id;
  const item = /^\d+$/.test(id) ? await Block.findOne({ height: Number(id) }).lean() : await Block.findOne({ hash: id }).lean();
  if (!item) return reply.code(404).send({ error: 'Block not found' });
  return item;
});

app.get('/api/v1/transactions/:txid', async (request, reply) => {
  const item = await Transaction.findOne({ txid: (request.params as { txid: string }).txid }).lean();
  if (!item) return reply.code(404).send({ error: 'Transaction not found' });
  return item;
});

await registerAddressRoutes(app);

app.get('/api/v1/assets', async request => {
  const query = request.query as { q?: string; page?: string; limit?: string };
  const page = Math.max(1, Number(query.page ?? 1));
  const limit = Math.min(100, Math.max(1, Number(query.limit ?? 25)));
  const filter = query.q ? { normalizedName: { $regex: query.q.toUpperCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&') } } : {};
  const [items, total] = await Promise.all([
    Asset.find(filter).sort({ name: 1 }).skip((page - 1) * limit).limit(limit).lean(),
    Asset.countDocuments(filter)
  ]);
  return { page, limit, total, items };
});

app.get('/api/v1/assets/:name', async (request, reply) => {
  const name = decodeURIComponent((request.params as { name: string }).name);
  const asset = await Asset.findOne({ normalizedName: name.toUpperCase() }).lean();
  if (!asset) return reply.code(404).send({ error: 'Asset not found' });
  const activity = await AssetEvent.find({ asset: asset.name }).sort({ blockHeight: -1 }).limit(100).lean();
  return { asset, activity };
});

app.get('/api/v1/search', async request => {
  const q = String((request.query as { q?: string }).q ?? '').trim();
  if (!q) return { type: 'empty', results: [] };
  if (/^\d+$/.test(q)) {
    const block = await Block.findOne({ height: Number(q) }).lean();
    if (block) return { type: 'block', results: [block] };
  }
  const [block, transaction, address, asset] = await Promise.all([
    Block.findOne({ hash: q }).lean(),
    Transaction.findOne({ txid: q }).lean(),
    Address.findOne({ address: q }).lean(),
    Asset.findOne({ normalizedName: q.toUpperCase() }).lean()
  ]);
  return { type: 'mixed', results: [block, transaction, address, asset].filter(Boolean) };
});

app.post('/api/v1/admin/sync', async () => ({ queued: await enqueueMissingBlocks() }));

await connectDatabase();
const io = new SocketServer(app.server, { cors: { origin: config.CORS_ORIGIN.split(',') }, path: '/socket.io' });
const subscriber = redis.duplicate();
await subscriber.subscribe('explorer:events');
subscriber.on('message', (_channel, message) => {
  try { io.emit('explorer:event', JSON.parse(message)); } catch { app.log.warn('Invalid explorer event'); }
});

setInterval(() => enqueueMissingBlocks().catch(error => app.log.error(error)), 5000).unref();
await enqueueMissingBlocks().catch(error => app.log.warn(error));
await app.listen({ host: config.API_HOST, port: config.API_PORT });

const shutdown = async () => {
  await subscriber.quit();
  await redis.quit();
  await app.close();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
