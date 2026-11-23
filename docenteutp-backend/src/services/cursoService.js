import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { parsePositiveInt } from '../utils/validators.js';
import { aResponse } from './docenteService.js';

export async function listar(q = '') {
  const texto = String(q || '').trim().toLowerCase();
  const res = texto
    ? await query(
        `SELECT id, codigo, nombre
         FROM cursos
         WHERE LOWER(nombre) LIKE '%' || $1 || '%' OR LOWER(codigo) LIKE '%' || $1 || '%'
         ORDER BY codigo ASC`,
        [texto]
      )
    : await query('SELECT id, codigo, nombre FROM cursos ORDER BY codigo ASC');

  return res.rows.map((c) => ({
    id: Number(c.id),
    codigo: c.codigo,
    nombre: c.nombre,
  }));
}

export async function docentesDelCurso(cursoIdParam) {
  const cursoId = parsePositiveInt(cursoIdParam, 'cursoId');
  const existe = await query('SELECT id FROM cursos WHERE id = $1', [cursoId]);
  if (existe.rows.length === 0) {
    throw new ApiError(404, 'Curso no encontrado');
  }

  const res = await query(
    `SELECT d.*
     FROM docente_curso dc
     JOIN docentes d ON d.id = dc.docente_id
     WHERE dc.curso_id = $1
     ORDER BY d.nombre ASC`,
    [cursoId]
  );

  return Promise.all(res.rows.map((d) => aResponse(d)));
}
