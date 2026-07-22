import { Worker } from 'bullmq';
import { Asset, AssetEvent, Block, SyncState, Transaction, connectDatabase, redis, rpc } from '../core.js';

type RawBlock = {
  hash: string;
  height: number;
  confirmations?: number;
  previousblockhash?: string;
  nextblockhash?: string;
  time: number;
  difficulty?: number;
  size?: number;
  tx: Array<string | Record<string, unknown>>;
};

async function indexAssetEvents(tx: Record<string, any>, block: RawBlock): Promise<void> {
  const events = Array.isArray(tx.asset_events) ? tx.asset_events : [];
  for (const event of events) {
    if (!event?.asset || !event?.type) continue;
    await AssetEvent.updateOne(
      { txid: tx.txid, asset: event.asset, type: event.type, to: event.to ?? null },
      { $setOnInsert: { asset: event.asset, type: event.type, txid: tx.txid, blockHeight: block.height, time: new Date(block.time * 1000), from: event.from, to: event.to, amount: event.amount, data: event } },
      { upsert: true }
    );

    if (event.type === 'issue' || event.type === 'reissue') {
      await Asset.findOneAndUpdate(
        { name: event.asset },
        { $set: { normalizedName: String(event.asset).toUpperCase(), amount: event.amount, units: event.units, reissuable: event.reissuable, hasIpfs: Boolean(event.ipfs_hash), ipfsHash: event.ipfs_hash, issuanceTxid: tx.txid, issuanceHeight: block.height, metadata: event } },
        { upsert: true }
      );
    }
  }
}

async function findCommonAncestor(startHeight: number): Promise<{ height: number; hash?: string }> {
  for (let height = startHeight; height >= 0; height -= 1) {
    const indexed = await Block.findOne({ height }).select({ hash: 1 }).lean();
    if (!indexed) continue;
    const canonicalHash = await rpc<string>('getblockhash', [height]);
    if (indexed.hash === canonicalHash) return { height, hash: canonicalHash };
  }
  return { height: -1 };
}

async function rollbackToCommonAncestor(startHeight: number): Promise<number> {
  const ancestor = await findCommonAncestor(startHeight);
  const rollbackHeight = ancestor.height + 1;

  await Promise.all([
    Block.deleteMany({ height: { $gte: rollbackHeight } }),
    Transaction.deleteMany({ blockHeight: { $gte: rollbackHeight } }),
    AssetEvent.deleteMany({ blockHeight: { $gte: rollbackHeight } }),
    Asset.deleteMany({ issuanceHeight: { $gte: rollbackHeight } })
  ]);

  await SyncState.updateOne(
    { key: 'blocks' },
    { height: ancestor.height, hash: ancestor.hash, status: 'reorg', error: null },
    { upsert: true }
  );
  await redis.publish('explorer:events', JSON.stringify({ type: 'reorg', rollbackHeight, ancestorHeight: ancestor.height, ancestorHash: ancestor.hash ?? null }));
  return ancestor.height;
}

async function ensureExpectedHeight(height: number): Promise<void> {
  const state = await SyncState.findOne({ key: 'blocks' }).lean();
  const expected = (state?.height ?? -1) + 1;
  if (height !== expected) throw new Error(`Out-of-order block job: received ${height}, expected ${expected}`);
}

async function ensureCanonicalParent(block: RawBlock): Promise<void> {
  if (block.height === 0) return;
  const parent = await Block.findOne({ height: block.height - 1 }).select({ hash: 1 }).lean();
  if (!parent || parent.hash !== block.previousblockhash) {
    await rollbackToCommonAncestor(block.height - 1);
    throw new Error(`Chain reorganization detected before block ${block.height}; canonical replay queued`);
  }
}

await connectDatabase();

const worker = new Worker(
  'yerbas-blocks',
  async job => {
    const height = Number(job.data.height);
    await ensureExpectedHeight(height);

    const hash = await rpc<string>('getblockhash', [height]);
    const block = await rpc<RawBlock>('getblock', [hash, 2]);
    await ensureCanonicalParent(block);

    const txids: string[] = [];
    for (const entry of block.tx) {
      const tx = typeof entry === 'string' ? await rpc<Record<string, any>>('getrawtransaction', [entry, true]) : entry as Record<string, any>;
      const txid = String(tx.txid);
      txids.push(txid);
      await Transaction.updateOne(
        { txid },
        { $set: { blockHeight: height, blockHash: hash, time: new Date(block.time * 1000), confirmations: block.confirmations, size: tx.size, virtualSize: tx.vsize, lockTime: tx.locktime, vin: tx.vin ?? [], vout: tx.vout ?? [], assetEvents: tx.asset_events ?? [], raw: tx } },
        { upsert: true }
      );
      await indexAssetEvents(tx, block);
    }

    await Block.updateOne(
      { height },
      { $set: { hash, previousHash: block.previousblockhash, nextHash: block.nextblockhash, time: new Date(block.time * 1000), confirmations: block.confirmations, difficulty: block.difficulty, size: block.size, txCount: txids.length, txids, raw: block } },
      { upsert: true }
    );
    await SyncState.updateOne({ key: 'blocks', height: height - 1 }, { height, hash, status: 'indexed', error: null }, { upsert: height === 0 });
    await redis.publish('explorer:events', JSON.stringify({ type: 'block', height, hash, txCount: txids.length }));
    return { height, hash, txCount: txids.length };
  },
  { connection: redis, concurrency: 1 }
);

worker.on('failed', async (job, error) => {
  await SyncState.updateOne({ key: 'blocks' }, { status: 'error', error: error.message }, { upsert: true });
  console.error({ jobId: job?.id, error }, 'Indexer job failed');
});

const shutdown = async () => {
  await worker.close();
  await redis.quit();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
