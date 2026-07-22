import 'dotenv/config';

const required = ['MONGODB_URI', 'YERB_RPC_URL', 'YERB_RPC_USER', 'YERB_RPC_PASSWORD'];
const missing = required.filter((name) => !process.env[name]);

if (missing.length > 0) {
  throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
}

export const config = Object.freeze({
  env: process.env.NODE_ENV ?? 'development',
  host: process.env.HOST ?? '127.0.0.1',
  port: Number.parseInt(process.env.PORT ?? '3001', 10),
  appName: process.env.APP_NAME ?? 'YERB Multi-Explorer',
  publicUrl: process.env.PUBLIC_URL ?? 'http://localhost:3001',
  mongodbUri: process.env.MONGODB_URI,
  rpc: {
    url: process.env.YERB_RPC_URL,
    user: process.env.YERB_RPC_USER,
    password: process.env.YERB_RPC_PASSWORD,
    timeoutMs: Number.parseInt(process.env.YERB_RPC_TIMEOUT_MS ?? '10000', 10)
  }
});
