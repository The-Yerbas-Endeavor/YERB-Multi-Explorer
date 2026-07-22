import compression from 'compression';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { config } from './config/index.js';
import { apiRouter } from './routes/api.js';

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.set('view engine', 'pug');
  app.set('views', new URL('./views', import.meta.url).pathname);

  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(compression());
  app.use(morgan(config.env === 'production' ? 'combined' : 'dev'));
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: false }));
  app.use('/static', express.static(new URL('../public', import.meta.url).pathname, {
    immutable: config.env === 'production',
    maxAge: config.env === 'production' ? '1d' : 0
  }));

  app.get('/', (_req, res) => {
    res.render('index', {
      title: config.appName,
      appName: config.appName
    });
  });

  app.use('/api/v1', apiRouter);

  app.use((_req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  app.use((error, _req, res, _next) => {
    console.error(error);
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
}
