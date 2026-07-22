import { config } from '../config/index.js';

let requestId = 0;

export async function rpcCall(method, params = []) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.rpc.timeoutMs);

  try {
    const response = await fetch(config.rpc.url, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${config.rpc.user}:${config.rpc.password}`).toString('base64')}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        jsonrpc: '1.0',
        id: ++requestId,
        method,
        params
      }),
      signal: controller.signal
    });

    if (!response.ok) {
      throw new Error(`Yerbas RPC HTTP ${response.status}`);
    }

    const payload = await response.json();
    if (payload.error) {
      const error = new Error(payload.error.message ?? 'Yerbas RPC error');
      error.code = payload.error.code;
      throw error;
    }

    return payload.result;
  } finally {
    clearTimeout(timeout);
  }
}

export const yerbasRpc = Object.freeze({
  getBlockchainInfo: () => rpcCall('getblockchaininfo'),
  getNetworkInfo: () => rpcCall('getnetworkinfo'),
  getBlockHash: (height) => rpcCall('getblockhash', [height]),
  getBlock: (hash, verbosity = 2) => rpcCall('getblock', [hash, verbosity]),
  getRawTransaction: (txid, verbose = true) => rpcCall('getrawtransaction', [txid, verbose]),
  getAssetData: (assetName) => rpcCall('getassetdata', [assetName]),
  listAssets: (filter = '*', verbose = true, count = 100, start = 0) =>
    rpcCall('listassets', [filter, verbose, count, start])
});
