import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { parsePositiveInt, validarDificultad, validarRating } from '../utils/validators.js';
import { redondear } from './docenteService.js';

function obtenerIniciales(nombre) {
  if (!nombre) return 'EU';
  const partes = nombre.trim().split(/\s+/);
  if (partes.length === 1) return partes[0].slice(0, 2).toUpperCase();
  return (partes[0][0] + partes[partes.length - 1][0]).toUpperCase();
}

function mapResena(row) {
  const dominio = Number(row.dominio);
  const claridad = Number(row.claridad);
  const empatia = Number(row.empatia);
  const promedio = redondear((dominio + claridad + empatia) / 3);
  return {
    id: Number(row.id),
    docenteId: Number(row.docente_id),
    docenteNombre: row.docente_nombre,
    cursoNombre: row.curso_nombre,
    calificacion: promedio,
    dominio,
    claridad,
    empatia,
    dificultad: row.dificultad,
    comentario: row.comentario,
    estado: row.estado,
    fecha: row.fecha,
    autorIniciales: obtenerIniciales(row.usuario_nombre),
  };
}

const SELECT_BASE = `
  SELECT r.id, r.docente_id, d.nombre AS docente_nombre, c.nombre AS curso_nombre,
         u.nombre AS usuario_nombre,
         r.dominio, r.claridad, r.empatia, r.dificultad, r.comentario, r.estado, r.fecha
  FROM resenas r
  JOIN docentes d ON d.id = r.docente_id
  JOIN cursos c ON c.id = r.curso_id
  JOIN usuarios u ON u.id = r.usuario_id
`;

export async function publicar(body) {
  const usuarioId = parsePositiveInt(body.usuarioId, 'usuarioId');
  const docenteId = parsePositiveInt(body.docenteId, 'docenteId');
  const cursoId = parsePositiveInt(body.cursoId, 'cursoId');
  const dominio = validarRating(body.dominio, 'dominio');
  const claridad = validarRating(body.claridad, 'claridad');
  const empatia = validarRating(body.empatia, 'empatia');
  const dificultad = validarDificultad(body.dificultad);

  const comentario = typeof body.comentario === 'string' ? body.comentario.trim() : '';
  if (comentario.length < 30 || comentario.length > 500) {
    throw new ApiError(400, 'El comentario debe tener entre 30 y 500 caracteres');
  }

  const uRes = await query('SELECT id FROM usuarios WHERE id = $1', [usuarioId]);
  if (uRes.rows.length === 0) {
    throw new ApiError(401, 'Usuario no verificado');
  }
  const dRes = await query('SELECT id FROM docentes WHERE id = $1', [docenteId]);
  if (dRes.rows.length === 0) {
    throw new ApiError(404, 'Docente no encontrado');
  }
  const cRes = await query('SELECT id FROM cursos WHERE id = $1', [cursoId]);
  if (cRes.rows.length === 0) {
    throw new ApiError(404, 'Curso no encontrado');
  }

  const dupRes = await query(
    'SELECT id FROM resenas WHERE usuario_id = $1 AND docente_id = $2 AND curso_id = $3',
    [usuarioId, docenteId, cursoId]
  );
  if (dupRes.rows.length > 0) {
    throw new ApiError(409, 'Ya enviaste una reseña para este docente y curso');
  }

  const inserted = await query(
    `INSERT INTO resenas (usuario_id, docente_id, curso_id, dominio, claridad, empatia, dificultad, comentario, estado)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'PENDIENTE')
     RETURNING id`,
    [usuarioId, docenteId, cursoId, dominio, claridad, empatia, dificultad, comentario]
  );

  const full = await query(`${SELECT_BASE} WHERE r.id = $1`, [inserted.rows[0].id]);
  return mapResena(full.rows[0]);
}

export async function listarPorDocente(docenteIdParam) {
  const docenteId = parsePositiveInt(docenteIdParam, 'docenteId');
  const res = await query(
    `${SELECT_BASE} WHERE r.docente_id = $1 AND r.estado = 'APROBADA' ORDER BY r.fecha DESC`,
    [docenteId]
  );
  return res.rows.map(mapResena);
}

export async function listarPorUsuario(usuarioIdParam) {
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');
  const res = await query(
    `${SELECT_BASE} WHERE r.usuario_id = $1 ORDER BY r.fecha DESC`,
    [usuarioId]
  );
  return res.rows.map(mapResena);
}

export async function eliminar(idParam, usuarioIdParam) {
  const id = parsePositiveInt(idParam, 'id');
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');

  const res = await query('SELECT id, usuario_id FROM resenas WHERE id = $1', [id]);
  if (res.rows.length === 0) {
    throw new ApiError(404, 'Reseña no encontrada');
  }
  if (Number(res.rows[0].usuario_id) !== usuarioId) {
    throw new ApiError(403, 'Solo puedes eliminar tus propias reseñas');
  }
  await query('DELETE FROM resenas WHERE id = $1', [id]);
}

export async function listarPendientes() {
  const res = await query(
    `${SELECT_BASE} WHERE r.estado = 'PENDIENTE' ORDER BY r.fecha ASC`
  );
  return res.rows.map(mapResena);
}

export async function cambiarEstado(idParam, aprobar) {
  const id = parsePositiveInt(idParam, 'id');
  const res = await query('SELECT id, estado FROM resenas WHERE id = $1', [id]);
  if (res.rows.length === 0) {
    throw new ApiError(404, 'Reseña no encontrada');
  }
  if (res.rows[0].estado !== 'PENDIENTE') {
    throw new ApiError(409, 'La reseña ya fue revisada');
  }
  const nuevoEstado = aprobar ? 'APROBADA' : 'RECHAZADA';
  await query('UPDATE resenas SET estado = $1 WHERE id = $2', [nuevoEstado, id]);
}
