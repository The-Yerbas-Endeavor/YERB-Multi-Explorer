module.exports = {
  apps: [
    {
      name: 'yerb-explorer-api',
      cwd: './apps/api',
      script: 'dist/server.js',
      instances: 'max',
      exec_mode: 'cluster',
      autorestart: true,
      max_memory_restart: '1G',
      env: { NODE_ENV: 'production' }
    },
    {
      name: 'yerb-explorer-indexer',
      cwd: './apps/api',
      script: 'dist/workers/indexer.js',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_memory_restart: '2G',
      env: { NODE_ENV: 'production' }
    }
  ]
};
