import { Worker } from 'bullmq';
import {
  Address, AddressTransaction, Asset, AssetEvent, Block, SyncState, Transaction, Utxo,
  connectDatabase, redis, rpc
} from '../core.js';

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

type AddressDelta = { received: number; sent: number; inputCount: number; outputCount: number };

function outputAddress(output: Record<string, any>): string | null {
  const script = output.scriptPubKey ?? {};
  if (typeof script.address === 'string' && script.address) return script.address;
  if (Array.isArray(script.addresses) && typeof script.addresses[0] === 'string') return script.addresses[0];
  return null;
}

function addDelta(map: Map<string, AddressDelta>, address: string, values: Partial<AddressDelta>): void {
  const current = map.get(address) ?? { received: 0, sent: 0, inputCount: 0, outputCount: 0 };
  current.received += values.received ?? 0;
  current.sent += values.sent ?? 0;
  current.inputCount += values.inputCount ?? 0;
  current.outputCount += values.outputCount ?? 0;
  map.set(address, current);
}

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

async function rebuildAddress(address: string): Promise<void> {
  const [utxoTotals, txStats] = await Promise.all([
    Utxo.aggregate([
      { $match: { address } },
      { $group: {
        _id: null,
        received: { $sum: '$value' },
        balance: { $sum: { $cond: ['$spent', 0, '$value'] } },
        sent: { $sum: { $cond: ['$spent', '$value', 0] } },
        firstSeenHeight: { $min: '$createdHeight' },
        lastOutputHeight: { $max: '$createdHeight' },
        lastSpendHeight: { $max: '$spentHeight' }
      } }
    ]),
    AddressTransaction.aggregate([
      { $match: { address } },
      { $group: { _id: null, txCount: { $sum: 1 }, firstSeenHeight: { $min: '$blockHeight' }, lastSeenHeight: { $max: '$blockHeight' } } }
    ])
  ]);
  const outputs = utxoTotals[0];
  const history = txStats[0];
  if (!outputs && !history) {
    await Address.deleteOne({ address });
    return;
  }
  await Address.updateOne(
    { address },
    { $set: {
      balance: Number(outputs?.balance ?? 0), received: Number(outputs?.received ?? 0), sent: Number(outputs?.sent ?? 0),
      txCount: Number(history?.txCount ?? 0), firstSeenHeight: history?.firstSeenHeight ?? outputs?.firstSeenHeight,
      lastSeenHeight: history?.lastSeenHeight ?? Math.max(outputs?.lastOutputHeight ?? -1, outputs?.lastSpendHeight ?? -1)
    } },
    { upsert: true }
  );
}

async function indexAddressState(tx: Record<string, any>, block: RawBlock): Promise<{ valueIn: number; valueOut: number; fees: number }> {
  const txid = String(tx.txid);
  const time = new Date(block.time * 1000);
  const deltas = new Map<string, AddressDelta>();
  let valueIn = 0;
  let valueOut = 0;
  const coinbase = Array.isArray(tx.vin) && tx.vin.some((input: any) => input?.coinbase != null);

  for (let vin = 0; vin < (tx.vin ?? []).length; vin += 1) {
    const input = tx.vin[vin];
    if (input?.coinbase != null || typeof input?.txid !== 'string' || !Number.isInteger(Number(input?.vout))) continue;
    const previous = await Utxo.findOneAndUpdate(
      { txid: input.txid, vout: Number(input.vout), spent: false },
      { $set: { spent: true, spentByTxid: txid, spentVin: vin, spentHeight: block.height, spentBlockHash: block.hash, spentTime: time } },
      { new: true }
    ).lean();
    if (!previous) throw new Error(`Missing or already-spent UTXO ${input.txid}:${input.vout} while indexing ${txid}`);
    const value = Number(previous.value ?? 0);
    valueIn += value;
    addDelta(deltas, String(previous.address), { sent: value, inputCount: 1 });
  }

  for (let index = 0; index < (tx.vout ?? []).length; index += 1) {
    const output = tx.vout[index] as Record<string, any>;
    const value = Number(output.value ?? 0);
    valueOut += value;
    const address = outputAddress(output);
    if (!address) continue;
    await Utxo.updateOne(
      { txid, vout: Number(output.n ?? index) },
      { $setOnInsert: {
        txid, vout: Number(output.n ?? index), address, value, scriptPubKey: output.scriptPubKey ?? {},
        createdHeight: block.height, createdBlockHash: block.hash, createdTime: time, coinbase, spent: false
      } },
      { upsert: true }
    );
    addDelta(deltas, address, { received: value, outputCount: 1 });
  }

  for (const [address, delta] of deltas) {
    await AddressTransaction.updateOne(
      { address, txid },
      { $set: {
        blockHeight: block.height, blockHash: block.hash, time, received: delta.received, sent: delta.sent,
        net: delta.received - delta.sent, inputCount: delta.inputCount, outputCount: delta.outputCount
      } },
      { upsert: true }
    );
    await Address.updateOne(
      { address },
      {
        $inc: { balance: delta.received - delta.sent, received: delta.received, sent: delta.sent, txCount: 1 },
        $min: { firstSeenHeight: block.height }, $max: { lastSeenHeight: block.height }
      },
      { upsert: true }
    );
  }

  return { valueIn, valueOut, fees: coinbase ? 0 : Math.max(0, valueIn - valueOut) };
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
  const affectedAddresses = new Set<string>([
    ...await Utxo.distinct('address', { $or: [{ createdHeight: { $gte: rollbackHeight } }, { spentHeight: { $gte: rollbackHeight } }] }),
    ...await AddressTransaction.distinct('address', { blockHeight: { $gte: rollbackHeight } })
  ]);

  await Promise.all([
    Block.deleteMany({ height: { $gte: rollbackHeight } }),
    Transaction.deleteMany({ blockHeight: { $gte: rollbackHeight } }),
    AssetEvent.deleteMany({ blockHeight: { $gte: rollbackHeight } }),
    Asset.deleteMany({ issuanceHeight: { $gte: rollbackHeight } }),
    AddressTransaction.deleteMany({ blockHeight: { $gte: rollbackHeight } }),
    Utxo.deleteMany({ createdHeight: { $gte: rollbackHeight } })
  ]);
  await Utxo.updateMany(
    { spentHeight: { $gte: rollbackHeight } },
    { $set: { spent: false }, $unset: { spentByTxid: 1, spentVin: 1, spentHeight: 1, spentBlockHash: 1, spentTime: 1 } }
  );
  for (const address of affectedAddresses) await rebuildAddress(address);

  await SyncState.updateOne(
    { key: 'blocks' },
    { height: ancestor.height, hash: ancestor.hash, status: 'reorg', error: null },
    { upsert: true }
  );
  await redis.publish('explorer:events', JSON.stringify({ type: 'reorg', rollbackHeight, ancestorHeight: ancestor.height, ancestorHash: ancestor.hash ?? null, affectedAddresses: affectedAddresses.size }));
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
    let blockFees = 0;
    let blockReward = 0;
    for (let txIndex = 0; txIndex < block.tx.length; txIndex += 1) {
      const entry = block.tx[txIndex];
      const tx = typeof entry === 'string' ? await rpc<Record<string, any>>('getrawtransaction', [entry, true]) : entry as Record<string, any>;
      const txid = String(tx.txid);
      txids.push(txid);
      const totals = await indexAddressState(tx, block);
      if (txIndex === 0) blockReward = totals.valueOut;
      else blockFees += totals.fees;
      await Transaction.updateOne(
        { txid },
        { $set: {
          blockHeight: height, blockHash: hash, time: new Date(block.time * 1000), confirmations: block.confirmations,
          size: tx.size, virtualSize: tx.vsize, lockTime: tx.locktime, valueIn: totals.valueIn,
          valueOut: totals.valueOut, fees: totals.fees, vin: tx.vin ?? [], vout: tx.vout ?? [],
          assetEvents: tx.asset_events ?? [], raw: tx
        } },
        { upsert: true }
      );
      await indexAssetEvents(tx, block);
    }

    await Block.updateOne(
      { height },
      { $set: {
        hash, previousHash: block.previousblockhash, nextHash: block.nextblockhash,
        time: new Date(block.time * 1000), confirmations: block.confirmations, difficulty: block.difficulty,
        size: block.size, txCount: txids.length, txids, reward: blockReward, fees: blockFees, raw: block
      } },
      { upsert: true }
    );
    const result = await SyncState.updateOne({ key: 'blocks', height: height - 1 }, { height, hash, status: 'indexed', error: null }, { upsert: height === 0 });
    if (result.matchedCount === 0 && result.upsertedCount === 0) throw new Error(`Failed to advance synchronization state to block ${height}`);
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
