import 'dotenv/config';
import { createApp } from './app.js';
import { initDatabase } from './db/init.js';
import { closePool, getPool } from './db/pool.js';

const PORT = Number(process.env.PORT || 8080);

async function start() {
  const pool = getPool();
  await pool.query('SELECT 1');

  if (process.env.AUTO_INIT_DB === 'true') {
    await initDatabase(pool);
  }

  const app = createApp();
  const server = app.listen(PORT, () => {
    console.log(`DocenteUTP API escuchando en http://localhost:${PORT}`);
  });

  const shutdown = async () => {
    server.close(async () => {
      await closePool();
      process.exit(0);
    });
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

start().catch((err) => {
  console.error('No se pudo iniciar el servidor:', err.message);
  process.exit(1);
});
