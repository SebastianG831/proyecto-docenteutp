import { query } from '../db/pool.js';
import { redondear } from './docenteService.js';

export async function reportePorDocente() {
  const res = await query(
    `SELECT
       v.id AS docente_id,
       v.nombre AS docente_nombre,
       v.facultad,
       v.sede,
       v.modalidad_principal,
       v.calificacion AS promedio_general,
       v.calificacion_integral,
       v.promedio_dominio,
       v.promedio_claridad,
       v.promedio_empatia,
       v.total_resenas,
       v.resenas_pendientes,
       v.nivel_dificultad,
       mf.avg_horas_estudio,
       mf.tasa_recomendacion,
       mf.indice_polarizacion,
       km.etiqueta_negocio AS perfil_ml,
       COALESCE(db.es_outlier, FALSE) AS es_outlier_ml
     FROM vw_docentes_resumen v
     LEFT JOIN vw_ml_docentes_features mf ON mf.docente_id = v.id
     LEFT JOIN vw_docentes_clusters_activos km ON km.docente_id = v.id AND km.algoritmo = 'KMEANS'
     LEFT JOIN vw_docentes_clusters_activos db ON db.docente_id = v.id AND db.algoritmo = 'DBSCAN'
     WHERE v.activo = TRUE
     ORDER BY v.calificacion DESC, v.total_resenas DESC, v.nombre ASC`
  );

  return res.rows.map((r) => ({
    docenteId: Number(r.docente_id),
    docenteNombre: r.docente_nombre,
    facultad: r.facultad,
    sede: r.sede,
    modalidadPrincipal: r.modalidad_principal,
    promedioGeneral: Number(r.promedio_general || 0),
    calificacionIntegral: Number(r.calificacion_integral || 0),
    promedioDominio: redondear(r.promedio_dominio),
    promedioClaridad: redondear(r.promedio_claridad),
    promedioEmpatia: redondear(r.promedio_empatia),
    totalResenas: Number(r.total_resenas || 0),
    resenasPendientes: Number(r.resenas_pendientes || 0),
    nivelDificultad: r.nivel_dificultad,
    avgHorasEstudio: r.avg_horas_estudio != null ? redondear(r.avg_horas_estudio) : 0,
    tasaRecomendacion:
      r.tasa_recomendacion != null ? Math.round(Number(r.tasa_recomendacion) * 100) : 0,
    indicePolarizacion:
      r.indice_polarizacion != null ? Math.round(Number(r.indice_polarizacion) * 100) / 100 : 0,
    perfilMl: r.perfil_ml || null,
    esOutlierMl: Boolean(r.es_outlier_ml),
  }));
}
