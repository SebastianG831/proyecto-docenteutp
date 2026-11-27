import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { parsePositiveInt } from '../utils/validators.js';
import { mapResumenRow } from './docenteService.js';

export async function listar(usuarioIdParam) {
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');
  const res = await query(
    `SELECT v.*,
            mf.avg_horas_estudio,
            mf.tasa_recomendacion,
            km.etiqueta_negocio AS perfil_ml,
            km.cluster_label AS perfil_ml_id,
            COALESCE(db.es_outlier, FALSE) AS es_outlier_ml
     FROM docentes_guardados dg
     JOIN vw_docentes_resumen v ON v.id = dg.docente_id
     LEFT JOIN vw_ml_docentes_features mf ON mf.docente_id = v.id
     LEFT JOIN vw_docentes_clusters_activos km ON km.docente_id = v.id AND km.algoritmo = 'KMEANS'
     LEFT JOIN vw_docentes_clusters_activos db ON db.docente_id = v.id AND db.algoritmo = 'DBSCAN'
     WHERE dg.usuario_id = $1 AND v.activo = TRUE
     ORDER BY dg.prioridad DESC, dg.fecha DESC`,
    [usuarioId]
  );
  return res.rows.map(mapResumenRow);
}

export async function guardar(usuarioIdParam, docenteIdParam) {
  const usuarioId = parsePositiveInt(usuarioIdParam, 'usuarioId');
  const docenteId = parsePositiveInt(docenteIdParam, 'docenteId');

  const uRes = await query('SELECT id FROM usuarios WHERE id = $1 AND activo = TRUE', [usuarioId]);
  if (uRes.rows.length === 0) {
    throw new ApiError(401, 'Usuario no verificado');
  }
  const dRes = await query('SELECT id FROM docentes WHERE id = $1 AND activo = TRUE', [docenteId]);
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
