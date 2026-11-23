import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import authRoutes from './routes/auth.routes.js';
import docentesRoutes from './routes/docentes.routes.js';
import cursosRoutes from './routes/cursos.routes.js';
import resenasRoutes from './routes/resenas.routes.js';
import guardadosRoutes from './routes/guardados.routes.js';
import adminRoutes from './routes/admin.routes.js';
import { errorHandler } from './utils/errors.js';
import { query } from './db/pool.js';

export function createApp() {
  const app = express();

  const allowedOrigins = (process.env.CORS_ORIGINS || 'http://localhost:5173,http://localhost:4200')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);

  app.use(helmet());
  app.use(
    cors({
      origin: (origin, cb) => {
        if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
          return cb(null, true);
        }
        return cb(null, false);
      },
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization'],
    })
  );
  app.use(express.json());

  app.get('/api/health', async (_req, res, next) => {
    try {
      await query('SELECT 1');
      res.json({ ok: true, service: 'docenteutp-backend', database: 'postgresql' });
    } catch (err) {
      next(err);
    }
  });

  app.use('/api/auth', authRoutes);
  app.use('/api/docentes', docentesRoutes);
  app.use('/api/cursos', cursosRoutes);
  app.use('/api/resenas', resenasRoutes);
  app.use('/api/guardados', guardadosRoutes);
  app.use('/api/admin', adminRoutes);

  app.use((_req, res) => {
    res.status(404).json({ mensaje: 'Ruta no encontrada' });
  });

  app.use(errorHandler);
  return app;
}
