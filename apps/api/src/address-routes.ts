import type { FastifyInstance } from 'fastify';
import { Address, AddressTransaction, Utxo } from './core.js';

function pageValues(query: { page?: string; limit?: string }): { page: number; limit: number } {
  return {
    page: Math.max(1, Number(query.page ?? 1)),
    limit: Math.min(100, Math.max(1, Number(query.limit ?? 25)))
  };
}

export async function registerAddressRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/v1/addresses/:address', async (request, reply) => {
    const address = (request.params as { address: string }).address;
    const [item, unspentCount] = await Promise.all([
      Address.findOne({ address }).lean(),
      Utxo.countDocuments({ address, spent: false })
    ]);
    if (!item) return reply.code(404).send({ error: 'Address not found' });
    return { ...item, unspentCount };
  });

  app.get('/api/v1/addresses/:address/transactions', async request => {
    const address = (request.params as { address: string }).address;
    const query = request.query as { page?: string; limit?: string };
    const { page, limit } = pageValues(query);
    const [items, total] = await Promise.all([
      AddressTransaction.find({ address })
        .sort({ blockHeight: -1, _id: -1 })
        .skip((page - 1) * limit)
        .limit(limit)
        .lean(),
      AddressTransaction.countDocuments({ address })
    ]);
    return { address, page, limit, total, items };
  });

  app.get('/api/v1/addresses/:address/utxos', async request => {
    const address = (request.params as { address: string }).address;
    const query = request.query as { page?: string; limit?: string; includeSpent?: string };
    const { page, limit } = pageValues(query);
    const includeSpent = String(query.includeSpent ?? 'false').toLowerCase() === 'true';
    const filter = includeSpent ? { address } : { address, spent: false };
    const [items, total, value] = await Promise.all([
      Utxo.find(filter)
        .sort({ createdHeight: -1, txid: 1, vout: 1 })
        .skip((page - 1) * limit)
        .limit(limit)
        .lean(),
      Utxo.countDocuments(filter),
      Utxo.aggregate([{ $match: filter }, { $group: { _id: null, value: { $sum: '$value' } } }])
    ]);
    return { address, includeSpent, page, limit, total, value: Number(value[0]?.value ?? 0), items };
  });
}
