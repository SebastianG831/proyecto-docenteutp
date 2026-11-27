import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { parsePositiveInt } from '../utils/validators.js';
import { mapResumenRow } from './docenteService.js';

export async function listar(q = '') {
  const texto = String(q || '').trim().toLowerCase();
  const res = texto
    ? await query(
        `SELECT id, codigo, nombre, creditos, ciclo_sugerido, tipo
         FROM cursos
         WHERE activo = TRUE
           AND (LOWER(nombre) LIKE '%' || $1 || '%' OR LOWER(codigo) LIKE '%' || $1 || '%')
         ORDER BY codigo ASC`,
        [texto]
      )
    : await query(
        'SELECT id, codigo, nombre, creditos, ciclo_sugerido, tipo FROM cursos WHERE activo = TRUE ORDER BY codigo ASC'
      );

  return res.rows.map((c) => ({
    id: Number(c.id),
    codigo: c.codigo,
    nombre: c.nombre,
    creditos: Number(c.creditos ?? 4),
    cicloSugerido: c.ciclo_sugerido ? Number(c.ciclo_sugerido) : null,
    tipo: c.tipo || 'OBLIGATORIO',
  }));
}

export async function docentesDelCurso(cursoIdParam) {
  const cursoId = parsePositiveInt(cursoIdParam, 'cursoId');
  const existe = await query('SELECT id FROM cursos WHERE id = $1 AND activo = TRUE', [cursoId]);
  if (existe.rows.length === 0) {
    throw new ApiError(404, 'Curso no encontrado');
  }

  const res = await query(
    `SELECT v.*,
            mf.avg_horas_estudio,
            mf.tasa_recomendacion,
            km.etiqueta_negocio AS perfil_ml,
            km.cluster_label AS perfil_ml_id,
            COALESCE(db.es_outlier, FALSE) AS es_outlier_ml
     FROM docente_curso dc
     JOIN vw_docentes_resumen v ON v.id = dc.docente_id
     LEFT JOIN vw_ml_docentes_features mf ON mf.docente_id = v.id
     LEFT JOIN vw_docentes_clusters_activos km ON km.docente_id = v.id AND km.algoritmo = 'KMEANS'
     LEFT JOIN vw_docentes_clusters_activos db ON db.docente_id = v.id AND db.algoritmo = 'DBSCAN'
     WHERE dc.curso_id = $1 AND dc.activo = TRUE AND v.activo = TRUE
     ORDER BY v.nombre ASC`,
    [cursoId]
  );

  return res.rows.map(mapResumenRow);
}
