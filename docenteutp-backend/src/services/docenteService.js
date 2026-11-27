import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { parsePositiveInt } from '../utils/validators.js';

export function redondear(v) {
  return Math.round(Number(v || 0) * 10) / 10;
}

function capitalizarDificultad(s) {
  if (!s || s === 'SIN_DATOS') return 'Sin datos';
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

function separarEtiquetas(etiquetas) {
  if (!etiquetas) return [];
  return etiquetas
    .split(',')
    .map((e) => e.trim())
    .filter(Boolean);
}

export function mapResumenRow(row) {
  return {
    id: Number(row.id),
    codigoDocente: row.codigo_docente || null,
    nombre: row.nombre,
    facultad: row.facultad,
    sede: row.sede,
    cursoPrincipal: row.curso_principal || 'Sin curso asignado',
    calificacion: Number(row.calificacion || 0),
    calificacionIntegral: Number(row.calificacion_integral || 0),
    totalResenas: Number(row.total_resenas || 0),
    estiloEnsenanza: row.estilo_ensenanza,
    modalidadPrincipal: row.modalidad_principal || 'PRESENCIAL',
    verificado: Boolean(row.verificado),
    nivelDificultad: capitalizarDificultad(row.nivel_dificultad),
    avgHorasEstudio: row.avg_horas_estudio != null ? redondear(row.avg_horas_estudio) : null,
    tasaRecomendacion:
      row.tasa_recomendacion != null ? Math.round(Number(row.tasa_recomendacion) * 100) : null,
    perfilMl: row.perfil_ml || null,
    perfilMlId: row.perfil_ml_id != null ? Number(row.perfil_ml_id) : null,
    esOutlierMl: Boolean(row.es_outlier_ml),
  };
}

export async function estadisticas(docenteId) {
  const res = await query(
    `SELECT AVG(dominio) AS dominio,
            AVG(claridad) AS claridad,
            AVG(empatia) AS empatia,
            AVG(retroalimentacion) AS retroalimentacion,
            AVG(organizacion) AS organizacion,
            AVG(puntualidad) AS puntualidad,
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
  const retroalimentacion = row.retroalimentacion ? Number(row.retroalimentacion) : 0;
  const organizacion = row.organizacion ? Number(row.organizacion) : 0;
  const puntualidad = row.puntualidad ? Number(row.puntualidad) : 0;
  const general = total === 0 ? 0 : redondear((dominio + claridad + empatia) / 3);
  return {
    dominio,
    claridad,
    empatia,
    retroalimentacion,
    organizacion,
    puntualidad,
    total,
    general,
  };
}

export async function buscar({
  q = '',
  estilo = '',
  dificultad = '',
  sede = '',
  modalidad = '',
  perfil = '',
  sort = 'nombre',
} = {}) {
  const texto = String(q || '').trim().toLowerCase();
  const est = String(estilo || '').trim();
  const dif = String(dificultad || '').trim().toUpperCase();
  const sedeNorm = String(sede || '').trim().toLowerCase();
  const modNorm = String(modalidad || '').trim().toUpperCase();
  const perfilNorm = String(perfil || '').trim().toLowerCase();

  let orderBy = 'v.nombre ASC';
  if (sort === 'calificacion' || sort === 'relevantes') {
    orderBy = 'v.calificacion DESC, v.total_resenas DESC, v.nombre ASC';
  } else if (sort === 'resenas') {
    orderBy = 'v.total_resenas DESC, v.calificacion DESC, v.nombre ASC';
  }

  const res = await query(
    `SELECT DISTINCT v.*,
            mf.avg_horas_estudio,
            mf.tasa_recomendacion,
            km.etiqueta_negocio AS perfil_ml,
            km.cluster_label AS perfil_ml_id,
            COALESCE(db.es_outlier, FALSE) AS es_outlier_ml
     FROM vw_docentes_resumen v
     LEFT JOIN docente_curso dc ON dc.docente_id = v.id AND dc.activo = TRUE
     LEFT JOIN cursos c ON c.id = dc.curso_id
     LEFT JOIN vw_ml_docentes_features mf ON mf.docente_id = v.id
     LEFT JOIN vw_docentes_clusters_activos km ON km.docente_id = v.id AND km.algoritmo = 'KMEANS'
     LEFT JOIN vw_docentes_clusters_activos db ON db.docente_id = v.id AND db.algoritmo = 'DBSCAN'
     WHERE v.activo = TRUE
       AND (
         $1 = ''
         OR LOWER(v.nombre) LIKE '%' || $1 || '%'
         OR LOWER(COALESCE(c.nombre, '')) LIKE '%' || $1 || '%'
         OR LOWER(COALESCE(c.codigo, '')) LIKE '%' || $1 || '%'
         OR LOWER(COALESCE(v.facultad, '')) LIKE '%' || $1 || '%'
       )
       AND ($2 = '' OR LOWER(v.estilo_ensenanza) = LOWER($2))
       AND ($3 = '' OR UPPER(v.nivel_dificultad) = $3)
       AND ($4 = '' OR LOWER(v.sede) LIKE '%' || $4 || '%')
       AND ($5 = '' OR UPPER(v.modalidad_principal) = $5)
       AND ($6 = '' OR LOWER(COALESCE(km.etiqueta_negocio, '')) LIKE '%' || $6 || '%' OR CAST(km.cluster_label AS TEXT) = $6)
     ORDER BY ${orderBy}`,
    [texto, est, dif, sedeNorm, modNorm, perfilNorm]
  );

  return res.rows.map(mapResumenRow);
}

export async function obtenerDetalle(id) {
  const docenteId = parsePositiveInt(id, 'docenteId');
  const res = await query(
    `SELECT d.*,
            v.calificacion,
            v.calificacion_integral,
            v.promedio_dominio,
            v.promedio_claridad,
            v.promedio_empatia,
            v.total_resenas,
            v.nivel_dificultad,
            mf.avg_retroalimentacion,
            mf.avg_organizacion,
            mf.avg_puntualidad,
            mf.avg_horas_estudio,
            mf.tasa_recomendacion,
            mf.avg_nota_obtenida,
            mf.indice_polarizacion,
            km.etiqueta_negocio AS perfil_ml,
            km.cluster_label AS perfil_ml_id,
            mc.descripcion AS perfil_ml_desc,
            COALESCE(db.es_outlier, FALSE) AS es_outlier_ml
     FROM docentes d
     JOIN vw_docentes_resumen v ON v.id = d.id
     LEFT JOIN vw_ml_docentes_features mf ON mf.docente_id = d.id
     LEFT JOIN vw_docentes_clusters_activos km ON km.docente_id = d.id AND km.algoritmo = 'KMEANS'
     LEFT JOIN ml_clusters mc ON mc.experimento_id = km.experimento_id AND mc.cluster_label = km.cluster_label
     LEFT JOIN vw_docentes_clusters_activos db ON db.docente_id = d.id AND db.algoritmo = 'DBSCAN'
     WHERE d.id = $1 AND d.activo = TRUE`,
    [docenteId]
  );
  if (res.rows.length === 0) {
    throw new ApiError(404, 'Docente no encontrado');
  }
  const d = res.rows[0];

  const cursosRes = await query(
    `SELECT c.id, c.codigo, c.nombre, dc.modalidad
     FROM docente_curso dc
     JOIN cursos c ON c.id = dc.curso_id
     WHERE dc.docente_id = $1 AND dc.activo = TRUE
     ORDER BY c.codigo ASC`,
    [docenteId]
  );

  const etiquetasRes = await query(
    `SELECT e.nombre
     FROM docente_etiqueta de
     JOIN etiquetas e ON e.id = de.etiqueta_id
     WHERE de.docente_id = $1
     ORDER BY de.peso DESC, e.nombre ASC`,
    [docenteId]
  );

  const etiquetas =
    etiquetasRes.rows.length > 0
      ? etiquetasRes.rows.map((r) => r.nombre)
      : separarEtiquetas(d.etiquetas);

  return {
    id: Number(d.id),
    codigoDocente: d.codigo_docente || null,
    nombre: d.nombre,
    facultad: d.facultad,
    sede: d.sede,
    verificado: Boolean(d.verificado),
    modalidadPrincipal: d.modalidad_principal || 'PRESENCIAL',
    aniosExperiencia: Number(d.anios_experiencia_utp ?? 1),
    calificacion: Number(d.calificacion || 0),
    calificacionIntegral: Number(d.calificacion_integral || 0),
    totalResenas: Number(d.total_resenas || 0),
    criterios: [
      { nombre: 'Dominio del tema', promedio: redondear(d.promedio_dominio) },
      { nombre: 'Claridad de explicación', promedio: redondear(d.promedio_claridad) },
      { nombre: 'Empatía y accesibilidad', promedio: redondear(d.promedio_empatia) },
    ],
    criteriosExtendidos: [
      { nombre: 'Retroalimentación', promedio: redondear(d.avg_retroalimentacion) },
      { nombre: 'Organización de clase', promedio: redondear(d.avg_organizacion) },
      { nombre: 'Puntualidad', promedio: redondear(d.avg_puntualidad) },
    ],
    cursos: cursosRes.rows.map((c) => ({
      id: Number(c.id),
      codigo: c.codigo,
      nombre: c.nombre,
      modalidad: c.modalidad,
    })),
    nivelDificultad: capitalizarDificultad(d.nivel_dificultad),
    estiloEnsenanza: d.estilo_ensenanza,
    estiloEvaluacion: d.estilo_evaluacion,
    avgHorasEstudio: d.avg_horas_estudio != null ? redondear(d.avg_horas_estudio) : null,
    tasaRecomendacion:
      d.tasa_recomendacion != null ? Math.round(Number(d.tasa_recomendacion) * 100) : null,
    avgNotaObtenida: d.avg_nota_obtenida != null ? redondear(d.avg_nota_obtenida) : null,
    indicePolarizacion:
      d.indice_polarizacion != null ? Math.round(Number(d.indice_polarizacion) * 100) / 100 : null,
    perfilMl: d.perfil_ml || null,
    perfilMlDesc: d.perfil_ml_desc || null,
    esOutlierMl: Boolean(d.es_outlier_ml),
    resumen: d.resumen || '',
    etiquetas,
  };
}

export async function crearDocente({
  nombre,
  facultad,
  sede = 'UTP Lima Centro · Edificio Arequipa',
  estiloEnsenanza,
  estiloEvaluacion,
  modalidadPrincipal = 'PRESENCIAL',
  aniosExperiencia = 1,
  resumen = '',
  etiquetas = '',
  cursoIds = [],
}) {
  if (!nombre?.trim() || !facultad?.trim() || !estiloEnsenanza?.trim() || !estiloEvaluacion?.trim()) {
    throw new ApiError(400, 'Nombre, facultad, estilo de enseñanza y estilo de evaluación son obligatorios');
  }

  const modVal = ['PRESENCIAL', 'VIRTUAL', 'SEMIPRESENCIAL'].includes(
    String(modalidadPrincipal).toUpperCase()
  )
    ? String(modalidadPrincipal).toUpperCase()
    : 'PRESENCIAL';

  const sedeRes = await query(
    'SELECT id FROM sedes WHERE LOWER(nombre) = LOWER($1) LIMIT 1',
    [sede.trim()]
  );

  const res = await query(
    `INSERT INTO docentes (nombre, facultad, sede_id, sede, verificado, estilo_ensenanza, estilo_evaluacion, modalidad_principal, anios_experiencia_utp, resumen, etiquetas)
     VALUES ($1, $2, $3, $4, TRUE, $5, $6, $7, $8, $9, $10)
     RETURNING id`,
    [
      nombre.trim(),
      facultad.trim(),
      sedeRes.rows[0]?.id ?? null,
      sede.trim(),
      estiloEnsenanza.trim(),
      estiloEvaluacion.trim(),
      modVal,
      Math.max(0, Number(aniosExperiencia) || 1),
      resumen.trim(),
      Array.isArray(etiquetas) ? etiquetas.join(',') : String(etiquetas || '').trim(),
    ]
  );
  const docenteId = res.rows[0].id;

  if (Array.isArray(cursoIds)) {
    for (const cid of cursoIds) {
      const parsedCid = parsePositiveInt(cid, 'cursoId');
      await query(
        `INSERT INTO docente_curso (docente_id, curso_id, modalidad) VALUES ($1, $2, $3) ON CONFLICT (docente_id, curso_id) DO NOTHING`,
        [docenteId, parsedCid, modVal]
      );
    }
  }

  const full = await query(
    `SELECT v.*, mf.avg_horas_estudio, mf.tasa_recomendacion
     FROM vw_docentes_resumen v
     LEFT JOIN vw_ml_docentes_features mf ON mf.docente_id = v.id
     WHERE v.id = $1`,
    [docenteId]
  );
  return mapResumenRow(full.rows[0]);
}
