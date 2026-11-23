import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { parsePositiveInt } from '../utils/validators.js';

export function redondear(v) {
  return Math.round(Number(v) * 10) / 10;
}

function capitalizar(s) {
  if (!s) return 'Sin datos';
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

function separarEtiquetas(etiquetas) {
  if (!etiquetas) return [];
  return etiquetas
    .split(',')
    .map((e) => e.trim())
    .filter(Boolean);
}

export async function estadisticas(docenteId) {
  const res = await query(
    `SELECT AVG(dominio) AS dominio,
            AVG(claridad) AS claridad,
            AVG(empatia) AS empatia,
            COUNT(id)::int AS total
     FROM resenas
     WHERE docente_id = $1 AND estado = 'APROBADA'`,
    [docenteId]
  );
  const row = res.rows[0] || {};
  const total = Number(row.total || 0);
  const dominio = row.dominio ? Number(row.dominio) : 0;
  const claridad = row.claridad ? Number(row.claridad) : 0;
  const empatia = row.empatia ? Number(row.empatia) : 0;
  const general = total === 0 ? 0 : redondear((dominio + claridad + empatia) / 3);
  return { dominio, claridad, empatia, total, general };
}

export async function dificultadMasFrecuente(docenteId) {
  const res = await query(
    `SELECT dificultad, COUNT(id)::int AS cantidad
     FROM resenas
     WHERE docente_id = $1 AND estado = 'APROBADA'
     GROUP BY dificultad
     ORDER BY cantidad DESC
     LIMIT 1`,
    [docenteId]
  );
  return res.rows.length > 0 ? res.rows[0].dificultad : null;
}

export async function aResponse(docente) {
  const est = await estadisticas(docente.id);
  const dif = await dificultadMasFrecuente(docente.id);
  const cursoRes = await query(
    `SELECT c.nombre
     FROM docente_curso dc
     JOIN cursos c ON c.id = dc.curso_id
     WHERE dc.docente_id = $1
     ORDER BY dc.id ASC
     LIMIT 1`,
    [docente.id]
  );
  const cursoPrincipal = cursoRes.rows[0]?.nombre || 'Sin curso asignado';

  return {
    id: Number(docente.id),
    nombre: docente.nombre,
    facultad: docente.facultad,
    cursoPrincipal,
    calificacion: est.general,
    totalResenas: est.total,
    estiloEnsenanza: docente.estilo_ensenanza,
    verificado: Boolean(docente.verificado),
    nivelDificultad: dif ? capitalizar(dif) : 'Sin datos',
  };
}

export async function buscar({ q = '', estilo = '', dificultad = '', sort = 'nombre' } = {}) {
  const texto = String(q || '').trim().toLowerCase();
  const est = String(estilo || '').trim();
  const dif = String(dificultad || '').trim().toUpperCase();

  const res = await query(
    `SELECT DISTINCT d.*
     FROM docentes d
     LEFT JOIN docente_curso dc ON dc.docente_id = d.id
     LEFT JOIN cursos c ON c.id = dc.curso_id
     WHERE (
       $1 = ''
       OR LOWER(d.nombre) LIKE '%' || $1 || '%'
       OR LOWER(COALESCE(c.nombre, '')) LIKE '%' || $1 || '%'
       OR LOWER(COALESCE(c.codigo, '')) LIKE '%' || $1 || '%'
       OR LOWER(COALESCE(d.facultad, '')) LIKE '%' || $1 || '%'
     )
     AND ($2 = '' OR LOWER(d.estilo_ensenanza) = LOWER($2))
     ORDER BY d.nombre ASC`,
    [texto, est]
  );

  let items = await Promise.all(res.rows.map((d) => aResponse(d)));

  if (dif) {
    items = items.filter((item) => item.nivelDificultad.toUpperCase() === dif);
  }

  if (sort === 'calificacion' || sort === 'relevantes') {
    items.sort((a, b) => b.calificacion - a.calificacion || b.totalResenas - a.totalResenas);
  } else if (sort === 'resenas') {
    items.sort((a, b) => b.totalResenas - a.totalResenas || b.calificacion - a.calificacion);
  }

  return items;
}

export async function obtenerDetalle(id) {
  const docenteId = parsePositiveInt(id, 'docenteId');
  const res = await query('SELECT * FROM docentes WHERE id = $1', [docenteId]);
  if (res.rows.length === 0) {
    throw new ApiError(404, 'Docente no encontrado');
  }
  const d = res.rows[0];
  const est = await estadisticas(docenteId);
  const dif = await dificultadMasFrecuente(docenteId);

  const cursosRes = await query(
    `SELECT c.id, c.codigo, c.nombre
     FROM docente_curso dc
     JOIN cursos c ON c.id = dc.curso_id
     WHERE dc.docente_id = $1
     ORDER BY c.codigo ASC`,
    [docenteId]
  );

  return {
    id: Number(d.id),
    nombre: d.nombre,
    facultad: d.facultad,
    sede: d.sede,
    verificado: Boolean(d.verificado),
    calificacion: est.general,
    totalResenas: est.total,
    criterios: [
      { nombre: 'Dominio del tema', promedio: redondear(est.dominio) },
      { nombre: 'Claridad de explicación', promedio: redondear(est.claridad) },
      { nombre: 'Empatía y accesibilidad', promedio: redondear(est.empatia) },
    ],
    cursos: cursosRes.rows.map((c) => ({
      id: Number(c.id),
      codigo: c.codigo,
      nombre: c.nombre,
    })),
    nivelDificultad: dif ? capitalizar(dif) : 'Sin datos',
    estiloEnsenanza: d.estilo_ensenanza,
    estiloEvaluacion: d.estilo_evaluacion,
    resumen: d.resumen || '',
    etiquetas: separarEtiquetas(d.etiquetas),
  };
}

export async function crearDocente({
  nombre,
  facultad,
  sede = 'UTP Lima Centro · Edificio Arequipa',
  estiloEnsenanza,
  estiloEvaluacion,
  resumen = '',
  etiquetas = '',
  cursoIds = [],
}) {
  if (!nombre?.trim() || !facultad?.trim() || !estiloEnsenanza?.trim() || !estiloEvaluacion?.trim()) {
    throw new ApiError(400, 'Nombre, facultad, estilo de enseñanza y estilo de evaluación son obligatorios');
  }

  const res = await query(
    `INSERT INTO docentes (nombre, facultad, sede, verificado, estilo_ensenanza, estilo_evaluacion, resumen, etiquetas)
     VALUES ($1, $2, $3, TRUE, $4, $5, $6, $7)
     RETURNING *`,
    [
      nombre.trim(),
      facultad.trim(),
      sede.trim(),
      estiloEnsenanza.trim(),
      estiloEvaluacion.trim(),
      resumen.trim(),
      Array.isArray(etiquetas) ? etiquetas.join(',') : String(etiquetas || '').trim(),
    ]
  );
  const docente = res.rows[0];

  if (Array.isArray(cursoIds)) {
    for (const cid of cursoIds) {
      const parsedCid = parsePositiveInt(cid, 'cursoId');
      await query(
        `INSERT INTO docente_curso (docente_id, curso_id) VALUES ($1, $2) ON CONFLICT (docente_id, curso_id) DO NOTHING`,
        [docente.id, parsedCid]
      );
    }
  }

  return aResponse(docente);
}
