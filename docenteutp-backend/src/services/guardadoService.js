import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { parsePositiveInt } from '../utils/validators.js';
import { aResponse } from './docenteService.js';

export async function listar(usuarioIdParam) {
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');
  const res = await query(
    `SELECT d.*
     FROM docentes_guardados dg
     JOIN docentes d ON d.id = dg.docente_id
     WHERE dg.usuario_id = $1
     ORDER BY dg.fecha DESC`,
    [usuarioId]
  );
  return Promise.all(res.rows.map((d) => aResponse(d)));
}

export async function guardar(usuarioIdParam, docenteIdParam) {
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');
  const docenteId = parsePositiveInt(docenteIdParam, 'docenteId');

  const uRes = await query('SELECT id FROM usuarios WHERE id = $1', [usuarioId]);
  if (uRes.rows.length === 0) {
    throw new ApiError(401, 'Usuario no verificado');
  }
  const dRes = await query('SELECT id FROM docentes WHERE id = $1', [docenteId]);
  if (dRes.rows.length === 0) {
    throw new ApiError(404, 'Docente no encontrado');
  }

  await query(
    `INSERT INTO docentes_guardados (usuario_id, docente_id)
     VALUES ($1, $2)
     ON CONFLICT (usuario_id, docente_id) DO NOTHING`,
    [usuarioId, docenteId]
  );
}

export async function quitar(usuarioIdParam, docenteIdParam) {
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');
  const docenteId = parsePositiveInt(docenteIdParam, 'docenteId');
  await query(
    'DELETE FROM docentes_guardados WHERE usuario_id = $1 AND docente_id = $2',
    [usuarioId, docenteId]
  );
}
