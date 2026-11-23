import { newDb } from 'pg-mem';
import { createApp } from './app.js';
import { setPool } from './db/pool.js';
import { initDatabase } from './db/init.js';

export async function createInMemoryPgPool() {
  const db = newDb({ autoCreateForeignKeyIndices: true });
  const adapter = db.adapters.createPg();
  const pool = new adapter.Pool();
  setPool(pool);
  await initDatabase(pool);
  return pool;
}

if (process.argv[1]?.endsWith('demo.js')) {
  const PORT = Number(process.env.PORT || 8080);
  createInMemoryPgPool()
    .then(() => {
      const app = createApp();
      app.listen(PORT, () => {
        console.log(`DocenteUTP API (demo PostgreSQL en memoria) en http://localhost:${PORT}`);
      });
    })
    .catch((err) => {
      console.error('Error iniciando modo demo:', err);
      process.exit(1);
    });
}
