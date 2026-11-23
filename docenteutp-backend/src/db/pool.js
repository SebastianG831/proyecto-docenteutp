import pg from 'pg';

const { Pool } = pg;

let activePool = null;

export function getPool() {
  if (!activePool) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error('DATABASE_URL no está configurada. Define DATABASE_URL en tu archivo .env.');
    }
    activePool = new Pool({
      connectionString,
      ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : false,
    });
  }
  return activePool;
}

export function setPool(customPool) {
  activePool = customPool;
}

export async function query(text, params = []) {
  return getPool().query(text, params);
}

export async function closePool() {
  if (activePool && typeof activePool.end === 'function') {
    await activePool.end();
  }
  activePool = null;
}
