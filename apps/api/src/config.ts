import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  API_HOST: z.string().default('127.0.0.1'),
  API_PORT: z.coerce.number().int().positive().default(3001),
  MONGODB_URI: z.string().default('mongodb://127.0.0.1:27017/yerbas_explorer'),
  REDIS_URL: z.string().default('redis://127.0.0.1:6379'),
  YERB_RPC_URL: z.string().url().default('http://127.0.0.1:8766'),
  YERB_RPC_USER: z.string().min(1),
  YERB_RPC_PASSWORD: z.string().min(1),
  SYNC_BATCH_SIZE: z.coerce.number().int().min(1).max(1000).default(25),
  CORS_ORIGIN: z.string().default('http://localhost:5173')
});

export const config = schema.parse(process.env);
