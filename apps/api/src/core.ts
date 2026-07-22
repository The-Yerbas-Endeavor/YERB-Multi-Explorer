import mongoose, { Schema } from 'mongoose';
import IORedis from 'ioredis';
import { Queue } from 'bullmq';
import { config } from './config.js';

export const redis = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
export const blockQueue = new Queue('yerbas-blocks', { connection: redis });

export async function connectDatabase(): Promise<void> {
  await mongoose.connect(config.MONGODB_URI, { autoIndex: config.NODE_ENV !== 'production' });
}

const BlockSchema = new Schema({
  height: { type: Number, required: true, unique: true, index: true }, hash: { type: String, required: true, unique: true, index: true },
  previousHash: String, nextHash: String, time: { type: Date, required: true, index: true }, confirmations: Number,
  difficulty: Number, size: Number, weight: Number, version: Number, nonce: Number, chainwork: String,
  txCount: Number, txids: [String], reward: Number, fees: Number, raw: Schema.Types.Mixed
}, { timestamps: true });

const TransactionSchema = new Schema({
  txid: { type: String, required: true, unique: true, index: true }, blockHeight: { type: Number, index: true },
  blockHash: { type: String, index: true }, time: { type: Date, index: true }, confirmations: Number, size: Number,
  virtualSize: Number, lockTime: Number, valueIn: Number, valueOut: Number, fees: Number,
  vin: [Schema.Types.Mixed], vout: [Schema.Types.Mixed], assetEvents: [Schema.Types.Mixed], raw: Schema.Types.Mixed
}, { timestamps: true });

const AddressSchema = new Schema({
  address: { type: String, required: true, unique: true, index: true }, balance: { type: Number, default: 0, index: true },
  received: { type: Number, default: 0 }, sent: { type: Number, default: 0 }, txCount: { type: Number, default: 0 },
  assetBalances: { type: Map, of: Number, default: {} }, lastSeenHeight: Number
}, { timestamps: true });

const AssetSchema = new Schema({
  name: { type: String, required: true, unique: true, index: true }, normalizedName: { type: String, required: true, index: true },
  amount: Number, units: Number, reissuable: Boolean, hasIpfs: Boolean, ipfsHash: String, verifierString: String,
  restricted: Boolean, ownerAddress: String, issuanceTxid: String, issuanceHeight: Number,
  holderCount: { type: Number, default: 0 }, transferCount: { type: Number, default: 0 }, metadata: Schema.Types.Mixed
}, { timestamps: true });

const AssetEventSchema = new Schema({
  asset: { type: String, required: true, index: true },
  type: { type: String, enum: ['issue', 'reissue', 'transfer', 'burn', 'freeze', 'unfreeze'], index: true },
  txid: { type: String, required: true, index: true }, blockHeight: { type: Number, required: true, index: true },
  time: { type: Date, index: true }, from: String, to: String, amount: Number, data: Schema.Types.Mixed
}, { timestamps: true });

const SyncStateSchema = new Schema({
  key: { type: String, required: true, unique: true }, height: { type: Number, default: -1 }, hash: String,
  status: { type: String, default: 'idle' }, error: String
}, { timestamps: true });

const NetworkSnapshotSchema = new Schema({
  capturedAt: { type: Date, required: true, index: true }, height: Number, difficulty: Number, networkHashrate: Number,
  connections: Number, peerCount: Number, mempoolTransactions: Number, mempoolBytes: Number, chainSize: Number,
  circulatingSupply: Number, blockTime: Number, blockReward: Number, activeSmartnodes: Number, totalSmartnodes: Number,
  lockedCollateral: Number
}, { timestamps: true });
NetworkSnapshotSchema.index({ capturedAt: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 365 * 3 });

const MarketSnapshotSchema = new Schema({
  capturedAt: { type: Date, required: true, index: true }, exchange: { type: String, required: true, index: true },
  pair: { type: String, required: true, index: true }, price: Number, bid: Number, ask: Number, high24h: Number,
  low24h: Number, volume24h: Number, volumeQuote24h: Number
}, { timestamps: true });
MarketSnapshotSchema.index({ exchange: 1, pair: 1, capturedAt: -1 });

export const Block = mongoose.model('Block', BlockSchema);
export const Transaction = mongoose.model('Transaction', TransactionSchema);
export const Address = mongoose.model('Address', AddressSchema);
export const Asset = mongoose.model('Asset', AssetSchema);
export const AssetEvent = mongoose.model('AssetEvent', AssetEventSchema);
export const SyncState = mongoose.model('SyncState', SyncStateSchema);
export const NetworkSnapshot = mongoose.model('NetworkSnapshot', NetworkSnapshotSchema);
export const MarketSnapshot = mongoose.model('MarketSnapshot', MarketSnapshotSchema);

let rpcId = 0;
export async function rpc<T>(method: string, params: unknown[] = []): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);
  try {
    const auth = Buffer.from(`${config.YERB_RPC_USER}:${config.YERB_RPC_PASSWORD}`).toString('base64');
    const response = await fetch(config.YERB_RPC_URL, {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Basic ${auth}` },
      body: JSON.stringify({ jsonrpc: '1.0', id: ++rpcId, method, params }), signal: controller.signal
    });
    if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
    const body = await response.json() as { result: T; error?: { message?: string } };
    if (body.error) throw new Error(body.error.message || `RPC ${method} failed`);
    return body.result;
  } finally {
    clearTimeout(timeout);
  }
}

export async function enqueueMissingBlocks(): Promise<number> {
  const chainHeight = await rpc<number>('getblockcount');
  const state = await SyncState.findOneAndUpdate(
    { key: 'blocks' },
    { $setOnInsert: { height: -1 }, $set: { status: 'queuing', error: null } },
    { upsert: true, new: true }
  );
  let added = 0;
  const upper = Math.min(chainHeight, state.height + config.SYNC_BATCH_SIZE);
  for (let height = state.height + 1; height <= upper; height += 1) {
    await blockQueue.add('index-block', { height }, {
      jobId: `block:${height}`,
      removeOnComplete: true,
      removeOnFail: true,
      attempts: 5,
      backoff: { type: 'exponential', delay: 2000 }
    });
    added += 1;
  }
  await SyncState.updateOne({ key: 'blocks' }, { status: 'queued' });
  return added;
}
