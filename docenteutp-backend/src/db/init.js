import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import 'dotenv/config';
import { closePool, getPool } from './pool.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SQL_DIR = path.resolve(__dirname, '../../sql');

export async function initDatabase(pool = getPool()) {
  const schemaSql = await fs.readFile(path.join(SQL_DIR, 'schema.sql'), 'utf8');
  const seedSql = await fs.readFile(path.join(SQL_DIR, 'seed.sql'), 'utf8');
  await pool.query(schemaSql);
  await pool.query(seedSql);
}

const isDirectExecution = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectExecution) {
  initDatabase()
    .then(async () => {
      console.log('Base de datos PostgreSQL inicializada y poblada correctamente.');
      await closePool();
    })
    .catch(async (err) => {
      console.error('Error al inicializar PostgreSQL:', err);
      await closePool();
      process.exit(1);
    });
}
