import { Router } from 'express';
import mongoose from 'mongoose';
import { Block } from '../models/block.js';
import { Asset } from '../models/asset.js';
import { yerbasRpc } from '../services/yerbas-rpc.js';

export const apiRouter = Router();

apiRouter.get('/health', async (_req, res) => {
  const database = mongoose.connection.readyState === 1 ? 'up' : 'down';
  let rpc = 'up';
  let chain = null;

  try {
    chain = await yerbasRpc.getBlockchainInfo();
  } catch {
    rpc = 'down';
  }

  const healthy = database === 'up' && rpc === 'up';
  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'ok' : 'degraded',
    database,
    rpc,
    chain: chain ? {
      blocks: chain.blocks,
      headers: chain.headers,
      bestBlockHash: chain.bestblockhash,
      verificationProgress: chain.verificationprogress
    } : null
  });
});

apiRouter.get('/blocks', async (req, res, next) => {
  try {
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit ?? '20', 10), 1), 100);
    const blocks = await Block.find().sort({ height: -1 }).limit(limit).lean();
    res.json({ data: blocks });
  } catch (error) {
    next(error);
  }
});

apiRouter.get('/blocks/:height', async (req, res, next) => {
  try {
    const height = Number.parseInt(req.params.height, 10);
    if (!Number.isInteger(height) || height < 0) {
      return res.status(400).json({ error: 'Invalid block height' });
    }

    const block = await Block.findOne({ height }).lean();
    if (!block) return res.status(404).json({ error: 'Block not indexed' });
    return res.json({ data: block });
  } catch (error) {
    return next(error);
  }
});

apiRouter.get('/assets', async (req, res, next) => {
  try {
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit ?? '50', 10), 1), 100);
    const skip = Math.max(Number.parseInt(req.query.skip ?? '0', 10), 0);
    const query = req.query.q ? { name: { $regex: String(req.query.q), $options: 'i' } } : {};
    const [assets, total] = await Promise.all([
      Asset.find(query).sort({ name: 1 }).skip(skip).limit(limit).lean(),
      Asset.countDocuments(query)
    ]);
    res.json({ data: assets, pagination: { total, skip, limit } });
  } catch (error) {
    next(error);
  }
});

apiRouter.get('/assets/:name', async (req, res, next) => {
  try {
    const asset = await Asset.findOne({ name: req.params.name }).lean();
    if (!asset) return res.status(404).json({ error: 'Asset not indexed' });
    return res.json({ data: asset });
  } catch (error) {
    return next(error);
  }
});
