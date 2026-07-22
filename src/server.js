import http from 'node:http';
import { createApp } from './app.js';
import { config } from './config/index.js';
import { connectDatabase, disconnectDatabase } from './db/mongoose.js';

async function main() {
  await connectDatabase();

  const app = createApp();
  const server = http.createServer(app);

  server.listen(config.port, config.host, () => {
    console.log(`${config.appName} listening on http://${config.host}:${config.port}`);
  });

  const shutdown = async (signal) => {
    console.log(`Received ${signal}; shutting down.`);
    server.close(async () => {
      await disconnectDatabase();
      process.exit(0);
    });

    setTimeout(() => process.exit(1), 10000).unref();
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((error) => {
  console.error('Failed to start explorer:', error);
  process.exit(1);
});
