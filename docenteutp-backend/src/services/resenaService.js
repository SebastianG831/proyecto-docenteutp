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
  const promedio =
    row.calificacion_promedio != null
      ? redondear(row.calificacion_promedio)
      : redondear((dominio + claridad + empatia) / 3);

  return {
    id: Number(row.id),
    docenteId: Number(row.docente_id),
    docenteNombre: row.docente_nombre,
    cursoNombre: row.curso_nombre,
    periodoCodigo: row.periodo_codigo || null,
    calificacion: promedio,
    dominio,
    claridad,
    empatia,
    retroalimentacion: Number(row.retroalimentacion ?? 3),
    organizacion: Number(row.organizacion ?? 3),
    puntualidad: Number(row.puntualidad ?? 4),
    dificultad: row.dificultad,
    horasEstudioSemanal: row.horas_estudio_semanal != null ? Number(row.horas_estudio_semanal) : 4,
    recomienda: row.recomienda != null ? Boolean(row.recomienda) : true,
    asistenciaObligatoria:
      row.asistencia_obligatoria != null ? Boolean(row.asistencia_obligatoria) : true,
    notaObtenida: row.nota_obtenida != null ? Number(row.nota_obtenida) : null,
    comentario: row.comentario,
    estado: row.estado,
    esAnomaliaMl: Boolean(row.es_anomalia_ml),
    motivoRechazo: row.motivo_rechazo || null,
    votosUtiles: Number(row.votos_utiles || 0),
    totalReportes: Number(row.total_reportes || 0),
    fecha: row.fecha,
    autorIniciales: obtenerIniciales(row.usuario_nombre),
  };
}

const SELECT_BASE = `
  SELECT r.id, r.docente_id, d.nombre AS docente_nombre, c.nombre AS curso_nombre,
         p.codigo AS periodo_codigo,
         u.nombre AS usuario_nombre,
         r.dominio, r.claridad, r.empatia,
         r.retroalimentacion, r.organizacion, r.puntualidad,
         r.dificultad, r.horas_estudio_semanal, r.recomienda, r.asistencia_obligatoria, r.nota_obtenida,
         r.calificacion_promedio, r.comentario, r.estado, r.es_anomalia_ml, r.motivo_rechazo, r.fecha,
         COALESCE(v.votos_utiles, 0)::int AS votos_utiles,
         COALESCE(rep.total_reportes, 0)::int AS total_reportes
  FROM resenas r
  JOIN docentes d ON d.id = r.docente_id
  JOIN cursos c ON c.id = r.curso_id
  JOIN usuarios u ON u.id = r.usuario_id
  LEFT JOIN periodos_academicos p ON p.id = r.periodo_id
  LEFT JOIN (
    SELECT resena_id, COUNT(*) FILTER (WHERE es_util = TRUE)::int AS votos_utiles
    FROM resena_votos
    GROUP BY resena_id
  ) v ON v.resena_id = r.id
  LEFT JOIN (
    SELECT resena_id, COUNT(*)::int AS total_reportes
    FROM resena_reportes
    GROUP BY resena_id
  ) rep ON rep.resena_id = r.id
`;

export async function publicar(body) {
  const usuarioId = parsePositiveInt(body.usuarioId, 'usuarioId');
  const docenteId = parsePositiveInt(body.docenteId, 'docenteId');
  const cursoId = parsePositiveInt(body.cursoId, 'cursoId');
  const dominio = validarRating(body.dominio, 'dominio');
  const claridad = validarRating(body.claridad, 'claridad');
  const empatia = validarRating(body.empatia, 'empatia');
  const retroalimentacion =
    body.retroalimentacion != null ? validarRating(body.retroalimentacion, 'retroalimentacion') : 3;
  const organizacion =
    body.organizacion != null ? validarRating(body.organizacion, 'organizacion') : 3;
  const puntualidad =
    body.puntualidad != null ? validarRating(body.puntualidad, 'puntualidad') : 4;
  const dificultad = validarDificultad(body.dificultad);

  const horasEstudio =
    body.horasEstudioSemanal != null ? Number(body.horasEstudioSemanal) : 4.0;
  if (Number.isNaN(horasEstudio) || horasEstudio < 0 || horasEstudio > 40) {
    throw new ApiError(400, 'Las horas de estudio semanal deben estar entre 0 y 40');
  }
  const recomienda = body.recomienda != null ? Boolean(body.recomienda) : true;
  const asistenciaObligatoria =
    body.asistenciaObligatoria != null ? Boolean(body.asistenciaObligatoria) : true;

  let notaObtenida = null;
  if (body.notaObtenida !== undefined && body.notaObtenida !== null && body.notaObtenida !== '') {
    notaObtenida = Number(body.notaObtenida);
    if (Number.isNaN(notaObtenida) || notaObtenida < 0 || notaObtenida > 20) {
      throw new ApiError(400, 'La nota obtenida debe estar entre 0 y 20');
    }
  }

  const comentario = typeof body.comentario === 'string' ? body.comentario.trim() : '';
  if (comentario.length < 30 || comentario.length > 500) {
    throw new ApiError(400, 'El comentario debe tener entre 30 y 500 caracteres');
  }

  const uRes = await query('SELECT id FROM usuarios WHERE id = $1 AND activo = TRUE', [usuarioId]);
  if (uRes.rows.length === 0) {
    throw new ApiError(401, 'Usuario no verificado');
  }
  const dRes = await query('SELECT id FROM docentes WHERE id = $1 AND activo = TRUE', [docenteId]);
  if (dRes.rows.length === 0) {
    throw new ApiError(404, 'Docente no encontrado');
  }
  const cRes = await query('SELECT id FROM cursos WHERE id = $1 AND activo = TRUE', [cursoId]);
  if (cRes.rows.length === 0) {
    throw new ApiError(404, 'Curso no encontrado');
  }

  const dcRes = await query(
    'SELECT id FROM docente_curso WHERE docente_id = $1 AND curso_id = $2 AND activo = TRUE',
    [docenteId, cursoId]
  );
  if (dcRes.rows.length === 0) {
    throw new ApiError(400, 'El docente no dicta el curso seleccionado');
  }

  const perRes = await query(
    'SELECT id FROM periodos_academicos WHERE es_actual = TRUE LIMIT 1'
  );
  const periodoId = perRes.rows[0]?.id ?? null;

  const dupRes = await query(
    `SELECT id FROM resenas
     WHERE usuario_id = $1 AND docente_id = $2 AND curso_id = $3
       AND periodo_id IS NOT DISTINCT FROM $4`,
    [usuarioId, docenteId, cursoId, periodoId]
  );
  if (dupRes.rows.length > 0) {
    throw new ApiError(409, 'Ya enviaste una reseña para este docente y curso en el periodo actual');
  }

  const inserted = await query(
    `INSERT INTO resenas (
       usuario_id, docente_id, curso_id, periodo_id,
       dominio, claridad, empatia, retroalimentacion, organizacion, puntualidad,
       dificultad, horas_estudio_semanal, recomienda, asistencia_obligatoria, nota_obtenida,
       comentario, estado
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, 'PENDIENTE')
     RETURNING id`,
    [
      usuarioId,
      docenteId,
      cursoId,
      periodoId,
      dominio,
      claridad,
      empatia,
      retroalimentacion,
      organizacion,
      puntualidad,
      dificultad,
      horasEstudio,
      recomienda,
      asistenciaObligatoria,
      notaObtenida,
      comentario,
    ]
  );

  const full = await query(`${SELECT_BASE} WHERE r.id = $1`, [inserted.rows[0].id]);
  return mapResena(full.rows[0]);
}

export async function listarPorDocente(docenteIdParam) {
  const docenteId = parsePositiveInt(docenteIdParam, 'docenteId');
  const res = await query(
    `${SELECT_BASE} WHERE r.docente_id = $1 AND r.estado = 'APROBADA' ORDER BY COALESCE(v.votos_utiles, 0) DESC, r.fecha DESC`,
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
    `${SELECT_BASE}
     WHERE r.estado IN ('PENDIENTE', 'MARCADA_ANOMALIA')
     ORDER BY r.es_anomalia_ml DESC, r.fecha ASC`
  );
  return res.rows.map(mapResena);
}

export async function cambiarEstado(idParam, aprobar, { adminId = null, motivo = null } = {}) {
  const id = parsePositiveInt(idParam, 'id');
  const res = await query('SELECT id, estado FROM resenas WHERE id = $1', [id]);
  if (res.rows.length === 0) {
    throw new ApiError(404, 'Reseña no encontrada');
  }
  if (!['PENDIENTE', 'MARCADA_ANOMALIA'].includes(res.rows[0].estado)) {
    throw new ApiError(409, 'La reseña ya fue revisada');
  }
  const nuevoEstado = aprobar ? 'APROBADA' : 'RECHAZADA';
  const parsedAdminId = adminId ? parsePositiveInt(adminId, 'adminId') : null;
  const motivoLimpiado = typeof motivo === 'string' && motivo.trim() ? motivo.trim().slice(0, 255) : null;
  await query(
    'UPDATE resenas SET estado = $1, moderado_por = $2, motivo_rechazo = $3 WHERE id = $4',
    [nuevoEstado, parsedAdminId, aprobar ? null : motivoLimpiado, id]
  );
}

export async function votarUtil(resenaIdParam, usuarioIdParam, esUtil = true) {
  const resenaId = parsePositiveInt(resenaIdParam, 'resenaId');
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');

  const resenaRes = await query("SELECT id FROM resenas WHERE id = $1 AND estado = 'APROBADA'", [resenaId]);
  if (resenaRes.rows.length === 0) {
    throw new ApiError(404, 'Reseña no encontrada');
  }
  await query(
    `INSERT INTO resena_votos (resena_id, usuario_id, es_util)
     VALUES ($1, $2, $3)
     ON CONFLICT (resena_id, usuario_id) DO UPDATE SET es_util = EXCLUDED.es_util`,
    [resenaId, usuarioId, Boolean(esUtil)]
  );
  const countRes = await query(
    'SELECT COUNT(*) FILTER (WHERE es_util = TRUE)::int AS votos_utiles FROM resena_votos WHERE resena_id = $1',
    [resenaId]
  );
  return { votosUtiles: Number(countRes.rows[0]?.votos_utiles || 0) };
}
