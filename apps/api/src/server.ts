import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import { Server as SocketServer } from 'socket.io';
import { config } from './config.js';
import { Asset, AssetEvent, Block, SyncState, Transaction, connectDatabase, enqueueMissingBlocks, redis, rpc } from './core.js';

const app = Fastify({ logger: true, trustProxy: true });
await app.register(cors, { origin: config.CORS_ORIGIN.split(',').map(v => v.trim()) });
await app.register(helmet);
await app.register(rateLimit, { max: 240, timeWindow: '1 minute' });
await app.register(swagger, {
  openapi: { info: { title: 'YERB Multi-Explorer API', version: '0.2.0' } }
});
await app.register(swaggerUi, { routePrefix: '/docs' });

app.get('/api/v1/health', async () => {
  const [height, state] = await Promise.all([
    rpc<number>('getblockcount').catch(() => null),
    SyncState.findOne({ key: 'blocks' }).lean()
  ]);
  return { status: height === null ? 'degraded' : 'ok', chainHeight: height, indexedHeight: state?.height ?? -1, queue: state?.status ?? 'idle' };
});

app.get('/api/v1/dashboard', async () => {
  const [latestBlocks, latestTransactions, assets, assetEvents, sync] = await Promise.all([
    Block.find().sort({ height: -1 }).limit(10).lean(),
    Transaction.find().sort({ blockHeight: -1, _id: -1 }).limit(10).lean(),
    Asset.countDocuments(),
    AssetEvent.find().sort({ blockHeight: -1, _id: -1 }).limit(10).lean(),
    SyncState.findOne({ key: 'blocks' }).lean()
  ]);
  return { latestBlocks, latestTransactions, assetCount: assets, assetEvents, sync };
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
  const [block, transaction, asset] = await Promise.all([
    Block.findOne({ hash: q }).lean(),
    Transaction.findOne({ txid: q }).lean(),
    Asset.findOne({ normalizedName: q.toUpperCase() }).lean()
  ]);
  return { type: 'mixed', results: [block, transaction, asset].filter(Boolean) };
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
