import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { query } from '../db/pool.js';
import { redondear } from './docenteService.js';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ML_SCRIPT_PATH = path.resolve(__dirname, '../../../docenteutp-ml/run_clustering.py');
const DEFAULT_PYTHON_BIN = path.resolve(__dirname, '../../../docenteutp-ml/.venv/bin/python');

function pct(value) {
  return Math.round(Number(value || 0) * 100);
}

function round2(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

function dificultadLabelFromScore(score) {
  const s = Number(score || 0);
  if (s <= 0) return 'Sin datos';
  if (s < 1.55) return 'Ligero';
  if (s < 2.4) return 'Moderado';
  return 'Exigente';
}

function consejoParaPerfil(nombre) {
  if (nombre.includes('Excelencia')) {
    return 'Recomendado si buscas clases muy claras, acompañamiento constante y alto aprendizaje.';
  }
  if (nombre.includes('Accesibles')) {
    return 'Ideal si priorizas cercanía, dinámica participativa y carga semanal ligera.';
  }
  if (nombre.includes('Carga Extrema')) {
    return 'Solo recomendable si cuentas con alta disponibilidad horaria (>20 h/sem) para este curso.';
  }
  if (nombre.includes('Exigentes')) {
    return 'Excelente opción si quieres profundizar al máximo y estás dispuesto a dedicar más horas de estudio.';
  }
  if (nombre.includes('Polarizado') || nombre.includes('Divididas')) {
    return 'Revisa los comentarios individuales antes de matricularte: las experiencias varían bastante según el estudiante.';
  }
  if (nombre.includes('Riesgo')) {
    return 'Conviene comparar otras secciones del mismo curso antes de definir tu horario.';
  }
  return 'Perfil equilibrado en exigencia y claridad para llevar el curso con ritmo estable.';
}

function explicarAlertaDocente(row) {
  const razones = [];
  if (Number(row.indice_polarizacion) >= 1.5) {
    razones.push(`Polarización extrema entre estudiantes (dispersión ${round2(row.indice_polarizacion)})`);
  }
  if (Number(row.avg_horas_estudio) >= 18) {
    razones.push(`Carga académica desproporcionada (${redondear(row.avg_horas_estudio)} h/semana)`);
  }
  if (Number(row.tasa_rechazo_bruta) >= 0.3) {
    razones.push(`${pct(row.tasa_rechazo_bruta)}% de reseñas rechazadas en moderación`);
  }
  if (Number(row.ratio_guardados_resena) >= 3) {
    razones.push(`Volumen inusual de guardados frente a reseñas (${redondear(row.ratio_guardados_resena)}x)`);
  }
  if (razones.length === 0) {
    razones.push('Comportamiento estadístico atípico respecto al resto de docentes');
  }
  return razones;
}

function explicarAlertaResena(row) {
  const razones = [];
  if (Number(row.ratio_mayusculas) >= 0.45) {
    razones.push('Uso excesivo de mayúsculas');
  }
  if (Number(row.resenas_usuario_24h) >= 3) {
    razones.push(`Ráfaga de ${row.resenas_usuario_24h} reseñas en 24h`);
  }
  if (Number(row.desviacion_abs_vs_docente) >= 2.0) {
    razones.push(`Calificación muy distante del promedio (${redondear(row.desviacion_abs_vs_docente)} pts)`);
  }
  if (Number(row.total_reportes) > 0) {
    razones.push(`${row.total_reportes} ${Number(row.total_reportes) === 1 ? 'reporte' : 'reportes'} de estudiantes`);
  }
  if (Number(row.horas_estudio_semanal) >= 20) {
    razones.push(`Carga extrema reportada (${redondear(row.horas_estudio_semanal)} h/sem)`);
  }
  if (razones.length === 0) {
    razones.push('Patrón atípico detectado por DBSCAN');
  }
  return razones;
}

function interpretacionSilhouette(sil) {
  if (sil == null) return 'Sin métrica disponible';
  if (sil >= 0.7) return 'Separación muy sólida entre perfiles';
  if (sil >= 0.5) return 'Buena diferenciación entre grupos';
  return 'Segmentación moderada';
}

async function buildDocentePerfilSection(algoritmo, modeloLabel, docentesMap) {
  const expRes = await query(
    `SELECT * FROM ml_experimentos
     WHERE algoritmo = $1 AND entidad_objetivo = 'DOCENTE' AND activo = TRUE
     LIMIT 1`,
    [algoritmo]
  );
  if (expRes.rows.length === 0) {
    return null;
  }
  const exp = expRes.rows[0];

  const clustersRes = await query(
    `SELECT * FROM ml_clusters
     WHERE experimento_id = $1
     ORDER BY cluster_label ASC`,
    [exp.id]
  );

  const asigRes = await query(
    `SELECT a.docente_id, a.cluster_label, a.es_outlier, a.probabilidad_pertenencia, a.distancia_centroide
     FROM ml_asignaciones a
     WHERE a.experimento_id = $1
     ORDER BY a.cluster_label ASC, a.distancia_centroide ASC NULLS LAST`,
    [exp.id]
  );

  const docentesByCluster = new Map();
  for (const row of asigRes.rows) {
    const doc = docentesMap.get(Number(row.docente_id));
    if (!doc) continue;
    const list = docentesByCluster.get(row.cluster_label) || [];
    list.push({
      id: doc.id,
      nombre: doc.nombre,
      facultad: doc.facultad,
      sede: doc.sede,
      cursoPrincipal: doc.cursoPrincipal,
      calificacion: doc.calificacion,
      totalResenas: doc.totalResenas,
      avgHorasEstudio: doc.avgHorasEstudio,
      tasaRecomendacionPct: doc.tasaRecomendacionPct,
      nivelDificultad: doc.nivelDificultad,
      probabilidadPertenencia:
        row.probabilidad_pertenencia != null ? pct(row.probabilidad_pertenencia) : null,
    });
    docentesByCluster.set(row.cluster_label, list);
  }

  const totalMuestras = Number(exp.n_muestras || 1);
  const grupos = clustersRes.rows.map((c) => {
    const centro = c.centroide_original || {};
    const dom = redondear(centro.avg_dominio);
    const cla = redondear(centro.avg_claridad);
    const emp = redondear(centro.avg_empatia);
    const dif = round2(centro.dificultad_score);
    const hrs = redondear(centro.avg_horas_estudio);
    const recPct = pct(centro.tasa_recomendacion);
    const calProm = redondear((Number(centro.avg_dominio || 0) + Number(centro.avg_claridad || 0) + Number(centro.avg_empatia || 0)) / 3);
    const docs = (docentesByCluster.get(c.cluster_label) || []).sort(
      (a, b) => b.calificacion - a.calificacion || b.totalResenas - a.totalResenas
    );

    return {
      clusterLabel: Number(c.cluster_label),
      nombre: c.etiqueta_negocio,
      descripcion: c.descripcion,
      consejoEstudiante: consejoParaPerfil(c.etiqueta_negocio || ''),
      tamano: Number(c.tamano),
      porcentaje: Math.round((Number(c.tamano) / totalMuestras) * 100),
      metricas: {
        dominio: dom,
        claridad: cla,
        empatia: emp,
        calificacionPromedio: calProm,
        dificultadScore: dif,
        dificultadTexto: dificultadLabelFromScore(dif),
        horasEstudio: hrs,
        tasaRecomendacionPct: recPct,
      },
      docentes: docs,
    };
  });

  // Orden natural: mejor recomendación y calificación primero, atípicos/riesgo al final
  grupos.sort((a, b) => b.metricas.calificacionPromedio - a.metricas.calificacionPromedio);

  return {
    algoritmo,
    modeloLabel,
    experimentoId: Number(exp.id),
    nMuestras: Number(exp.n_muestras),
    nClusters: Number(exp.n_clusters_encontrados),
    calidadSeparacionPct: exp.silhouette_score != null ? pct(exp.silhouette_score) : null,
    interpretacionCalidad: interpretacionSilhouette(exp.silhouette_score),
    hiperparametros: exp.hiperparametros || {},
    ejecutadoEn: exp.ejecutado_en,
    grupos,
  };
}

export async function obtenerEstadisticasCompletas() {
  // 1. Resumen global institucional
  const resumenRes = await query(`
    SELECT
      (SELECT COUNT(*)::int FROM docentes WHERE activo = TRUE) AS total_docentes,
      (SELECT COUNT(*)::int FROM resenas WHERE estado = 'APROBADA') AS total_aprobadas,
      (SELECT COUNT(*)::int FROM resenas WHERE estado IN ('PENDIENTE', 'MARCADA_ANOMALIA')) AS total_pendientes,
      (SELECT COUNT(*)::int FROM resenas WHERE estado = 'RECHAZADA') AS total_rechazadas,
      (SELECT COUNT(*)::int FROM usuarios WHERE rol = 'ESTUDIANTE' AND activo = TRUE) AS total_estudiantes,
      (SELECT COUNT(*)::int FROM cursos WHERE activo = TRUE) AS total_cursos,
      (SELECT COUNT(*)::int FROM sedes WHERE activo = TRUE) AS total_sedes,
      (SELECT COALESCE(ROUND(AVG(calificacion_promedio), 2), 0) FROM resenas WHERE estado = 'APROBADA') AS promedio_general,
      (SELECT COALESCE(AVG(CASE WHEN recomienda THEN 1.0 ELSE 0.0 END), 0) FROM resenas WHERE estado = 'APROBADA') AS tasa_recomendacion,
      (SELECT COALESCE(ROUND(AVG(horas_estudio_semanal), 1), 0) FROM resenas WHERE estado = 'APROBADA') AS avg_horas_estudio,
      (SELECT COALESCE(ROUND(AVG(nota_obtenida), 1), 0) FROM resenas WHERE estado = 'APROBADA' AND nota_obtenida IS NOT NULL) AS avg_nota,
      (SELECT MAX(ejecutado_en) FROM ml_experimentos WHERE activo = TRUE) AS ultima_actualizacion_ml
  `);
  const resRow = resumenRes.rows[0];

  // 2. Mapa completo de docentes (consumible: calificación vs horas, claridad vs empatía, etc.)
  const docentesRes = await query(`
    SELECT
      v.id,
      v.nombre,
      v.facultad,
      v.sede,
      v.modalidad_principal,
      v.curso_principal,
      v.calificacion,
      v.calificacion_integral,
      v.total_resenas,
      v.nivel_dificultad,
      mf.avg_dominio,
      mf.avg_claridad,
      mf.avg_empatia,
      mf.dificultad_score,
      mf.avg_horas_estudio,
      mf.tasa_recomendacion,
      mf.avg_nota_obtenida,
      mf.indice_polarizacion,
      mf.total_guardados,
      km.cluster_label AS perfil_kmeans_id,
      km.etiqueta_negocio AS perfil_kmeans,
      ms.cluster_label AS perfil_meanshift_id,
      ms.etiqueta_negocio AS perfil_meanshift,
      COALESCE(db.es_outlier, FALSE) AS es_outlier_dbscan
    FROM vw_docentes_resumen v
    JOIN vw_ml_docentes_features mf ON mf.docente_id = v.id
    LEFT JOIN vw_docentes_clusters_activos km ON km.docente_id = v.id AND km.algoritmo = 'KMEANS'
    LEFT JOIN vw_docentes_clusters_activos ms ON ms.docente_id = v.id AND ms.algoritmo = 'MEAN_SHIFT'
    LEFT JOIN vw_docentes_clusters_activos db ON db.docente_id = v.id AND db.algoritmo = 'DBSCAN'
    WHERE v.activo = TRUE
    ORDER BY v.calificacion DESC, v.nombre ASC
  `);

  const mapaDocentes = docentesRes.rows.map((d) => ({
    id: Number(d.id),
    nombre: d.nombre,
    facultad: d.facultad,
    sede: d.sede,
    modalidadPrincipal: d.modalidad_principal,
    cursoPrincipal: d.curso_principal,
    calificacion: Number(d.calificacion),
    calificacionIntegral: Number(d.calificacion_integral),
    avgDominio: redondear(d.avg_dominio),
    avgClaridad: redondear(d.avg_claridad),
    avgEmpatia: redondear(d.avg_empatia),
    dificultadScore: round2(d.dificultad_score),
    nivelDificultad: dificultadLabelFromScore(d.dificultad_score),
    avgHorasEstudio: redondear(d.avg_horas_estudio),
    tasaRecomendacionPct: pct(d.tasa_recomendacion),
    avgNotaObtenida: redondear(d.avg_nota_obtenida),
    indicePolarizacion: round2(d.indice_polarizacion),
    totalResenas: Number(d.total_resenas),
    totalGuardados: Number(d.total_guardados),
    perfilKmeansId: d.perfil_kmeans_id != null ? Number(d.perfil_kmeans_id) : null,
    perfilKmeans: d.perfil_kmeans || 'Sin clasificar',
    perfilMeanshiftId: d.perfil_meanshift_id != null ? Number(d.perfil_meanshift_id) : null,
    perfilMeanshift: d.perfil_meanshift || 'Sin clasificar',
    esOutlierDbscan: Boolean(d.es_outlier_dbscan),
  }));

  const docentesMap = new Map(mapaDocentes.map((d) => [d.id, d]));

  // 3. Segmentación Docente (K-Means y Mean Shift)
  const [kmeansDocentes, meanshiftDocentes] = await Promise.all([
    buildDocentePerfilSection('KMEANS', 'Perfiles Principales (K-Means)', docentesMap),
    buildDocentePerfilSection('MEAN_SHIFT', 'Modos Naturales (Mean Shift)', docentesMap),
  ]);

  // 4. Distribuciones por Sede, Facultad, Modalidad, Periodo y Dificultad
  const [sedeRes, facRes, modRes, perRes, difRes] = await Promise.all([
    query(`
      SELECT
        s.nombre,
        s.ciudad,
        COUNT(DISTINCT d.id)::int AS total_docentes,
        COUNT(r.id) FILTER (WHERE r.estado = 'APROBADA')::int AS total_resenas,
        COALESCE(ROUND(AVG(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 2), 0) AS calificacion_promedio,
        COALESCE(AVG(CASE WHEN r.recomienda THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0) AS tasa_recomendacion
      FROM sedes s
      LEFT JOIN docentes d ON d.sede_id = s.id AND d.activo = TRUE
      LEFT JOIN resenas r ON r.docente_id = d.id
      WHERE s.activo = TRUE
      GROUP BY s.id, s.nombre, s.ciudad
      ORDER BY total_docentes DESC
    `),
    query(`
      SELECT
        f.nombre,
        COUNT(DISTINCT d.id)::int AS total_docentes,
        COUNT(r.id) FILTER (WHERE r.estado = 'APROBADA')::int AS total_resenas,
        COALESCE(ROUND(AVG(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 2), 0) AS calificacion_promedio,
        COALESCE(ROUND(AVG(r.horas_estudio_semanal) FILTER (WHERE r.estado = 'APROBADA'), 1), 0) AS avg_horas_estudio,
        COALESCE(AVG(CASE WHEN r.recomienda THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0) AS tasa_recomendacion
      FROM facultades f
      LEFT JOIN docentes d ON d.facultad_id = f.id AND d.activo = TRUE
      LEFT JOIN resenas r ON r.docente_id = d.id
      GROUP BY f.id, f.nombre
      ORDER BY total_docentes DESC
    `),
    query(`
      SELECT
        d.modalidad_principal AS modalidad,
        COUNT(DISTINCT d.id)::int AS total_docentes,
        COUNT(r.id) FILTER (WHERE r.estado = 'APROBADA')::int AS total_resenas,
        COALESCE(ROUND(AVG(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 2), 0) AS calificacion_promedio,
        COALESCE(ROUND(AVG(r.horas_estudio_semanal) FILTER (WHERE r.estado = 'APROBADA'), 1), 0) AS avg_horas_estudio,
        COALESCE(AVG(CASE WHEN r.recomienda THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0) AS tasa_recomendacion
      FROM docentes d
      LEFT JOIN resenas r ON r.docente_id = d.id
      WHERE d.activo = TRUE
      GROUP BY d.modalidad_principal
      ORDER BY total_docentes DESC
    `),
    query(`
      SELECT
        p.codigo,
        p.es_actual,
        COUNT(r.id) FILTER (WHERE r.estado = 'APROBADA')::int AS total_resenas,
        COALESCE(ROUND(AVG(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 2), 0) AS calificacion_promedio,
        COALESCE(ROUND(AVG(r.horas_estudio_semanal) FILTER (WHERE r.estado = 'APROBADA'), 1), 0) AS avg_horas_estudio,
        COALESCE(AVG(CASE WHEN r.recomienda THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0) AS tasa_recomendacion
      FROM periodos_academicos p
      LEFT JOIN resenas r ON r.periodo_id = p.id
      GROUP BY p.id, p.codigo, p.es_actual, p.fecha_inicio
      ORDER BY p.fecha_inicio ASC
    `),
    query(`
      SELECT
        dificultad,
        COUNT(*)::int AS total_resenas,
        ROUND(AVG(calificacion_promedio), 2) AS calificacion_promedio,
        ROUND(AVG(horas_estudio_semanal), 1) AS avg_horas_estudio
      FROM resenas
      WHERE estado = 'APROBADA'
      GROUP BY dificultad
      ORDER BY CASE dificultad WHEN 'LIGERO' THEN 1 WHEN 'MODERADO' THEN 2 ELSE 3 END
    `),
  ]);

  const totalDifRes = difRes.rows.reduce((acc, r) => acc + Number(r.total_resenas), 0) || 1;

  // 5. Perfiles de Estudiantes (K-Means en USUARIO)
  const usrExpRes = await query(`
    SELECT * FROM ml_experimentos
    WHERE algoritmo = 'KMEANS' AND entidad_objetivo = 'USUARIO' AND activo = TRUE
    LIMIT 1
  `);
  let perfilesEstudiantes = null;
  if (usrExpRes.rows.length > 0) {
    const exp = usrExpRes.rows[0];
    const uClusRes = await query(
      `SELECT * FROM ml_clusters WHERE experimento_id = $1 ORDER BY tamano DESC`,
      [exp.id]
    );
    const totalU = Number(exp.n_muestras || 1);
    perfilesEstudiantes = {
      algoritmo: 'KMEANS',
      nMuestras: Number(exp.n_muestras),
      nClusters: Number(exp.n_clusters_encontrados),
      calidadSeparacionPct: exp.silhouette_score != null ? pct(exp.silhouette_score) : null,
      grupos: uClusRes.rows.map((c) => {
        const ctr = c.centroide_original || {};
        return {
          clusterLabel: Number(c.cluster_label),
          nombre: c.etiqueta_negocio,
          descripcion: c.descripcion,
          tamano: Number(c.tamano),
          porcentaje: Math.round((Number(c.tamano) / totalU) * 100),
          cicloPromedio: redondear(ctr.ciclo),
          resenasPromedio: redondear(ctr.total_resenas),
          guardadosPromedio: redondear(ctr.total_guardados),
          calificacionDadaPromedio: redondear(ctr.avg_calificacion_dada),
          horasReportadasPromedio: redondear(ctr.avg_horas_reportadas),
          tasaRecomendacionPct: pct(ctr.tasa_recomendacion_dada),
        };
      }),
    };
  }

  // 6. Alertas de Calidad y Anomalías (DBSCAN Docentes + Reseñas)
  const [outliersDocRes, anomResRes, resExpRes] = await Promise.all([
    query(`
      SELECT
        vc.docente_id,
        vc.docente_nombre,
        d.facultad,
        d.sede,
        mf.avg_general,
        mf.indice_polarizacion,
        mf.avg_horas_estudio,
        mf.tasa_rechazo_bruta,
        mf.ratio_guardados_resena,
        mf.total_resenas_aprobadas
      FROM vw_docentes_clusters_activos vc
      JOIN docentes d ON d.id = vc.docente_id
      JOIN vw_ml_docentes_features mf ON mf.docente_id = vc.docente_id
      WHERE vc.algoritmo = 'DBSCAN' AND vc.es_outlier = TRUE
      ORDER BY mf.avg_general DESC
    `),
    query(`
      SELECT
        va.resena_id,
        va.docente_id,
        va.docente_nombre,
        va.usuario_correo,
        va.estado,
        va.calificacion_promedio,
        va.comentario,
        rf.ratio_mayusculas,
        rf.resenas_usuario_24h,
        rf.desviacion_abs_vs_docente,
        rf.total_reportes,
        rf.horas_estudio_semanal
      FROM vw_resenas_anomalias_activas va
      JOIN vw_ml_resenas_features rf ON rf.resena_id = va.resena_id
      ORDER BY va.resena_id DESC
    `),
    query(`
      SELECT e.n_muestras, e.n_outliers,
             COALESCE((
               SELECT SUM(c.tamano)::int
               FROM ml_clusters c
               WHERE c.experimento_id = e.id
                 AND c.etiqueta_negocio ILIKE '%Promocional%'
             ), 0) AS promocionales
      FROM ml_experimentos e
      WHERE e.algoritmo = 'DBSCAN' AND e.entidad_objetivo = 'RESENA' AND e.activo = TRUE
      LIMIT 1
    `),
  ]);

  const resMeta = resExpRes.rows[0] || { n_muestras: 0, n_outliers: 0, promocionales: 0 };

  return {
    resumen: {
      totalDocentes: Number(resRow.total_docentes),
      totalResenasAprobadas: Number(resRow.total_aprobadas),
      totalResenasPendientes: Number(resRow.total_pendientes),
      totalResenasRechazadas: Number(resRow.total_rechazadas),
      totalEstudiantesActivos: Number(resRow.total_estudiantes),
      totalCursos: Number(resRow.total_cursos),
      totalSedes: Number(resRow.total_sedes),
      promedioGeneral: Number(resRow.promedio_general),
      tasaRecomendacionGlobal: pct(resRow.tasa_recomendacion),
      avgHorasEstudioGlobal: Number(resRow.avg_horas_estudio),
      avgNotaReportada: Number(resRow.avg_nota),
      ultimaActualizacionMl: resRow.ultima_actualizacion_ml,
    },
    perfilesDocentes: {
      kmeans: kmeansDocentes,
      meanshift: meanshiftDocentes,
    },
    mapaDocentes,
    distribuciones: {
      porSede: sedeRes.rows.map((s) => ({
        nombre: s.nombre,
        ciudad: s.ciudad,
        totalDocentes: Number(s.total_docentes),
        totalResenas: Number(s.total_resenas),
        calificacionPromedio: Number(s.calificacion_promedio),
        tasaRecomendacionPct: pct(s.tasa_recomendacion),
      })),
      porFacultad: facRes.rows.map((f) => ({
        nombre: f.nombre,
        totalDocentes: Number(f.total_docentes),
        totalResenas: Number(f.total_resenas),
        calificacionPromedio: Number(f.calificacion_promedio),
        avgHorasEstudio: Number(f.avg_horas_estudio),
        tasaRecomendacionPct: pct(f.tasa_recomendacion),
      })),
      porModalidad: modRes.rows.map((m) => ({
        modalidad: m.modalidad,
        totalDocentes: Number(m.total_docentes),
        totalResenas: Number(m.total_resenas),
        calificacionPromedio: Number(m.calificacion_promedio),
        avgHorasEstudio: Number(m.avg_horas_estudio),
        tasaRecomendacionPct: pct(m.tasa_recomendacion),
      })),
      porPeriodo: perRes.rows.map((p) => ({
        codigo: p.codigo,
        esActual: Boolean(p.es_actual),
        totalResenas: Number(p.total_resenas),
        calificacionPromedio: Number(p.calificacion_promedio),
        avgHorasEstudio: Number(p.avg_horas_estudio),
        tasaRecomendacionPct: pct(p.tasa_recomendacion),
      })),
      porDificultad: difRes.rows.map((d) => ({
        nivel: d.dificultad.charAt(0) + d.dificultad.slice(1).toLowerCase(),
        totalResenas: Number(d.total_resenas),
        porcentaje: Math.round((Number(d.total_resenas) / totalDifRes) * 100),
        calificacionPromedio: Number(d.calificacion_promedio),
        avgHorasEstudio: Number(d.avg_horas_estudio),
      })),
    },
    perfilesEstudiantes,
    alertasCalidad: {
      docentesAtipicos: outliersDocRes.rows.map((d) => ({
        docenteId: Number(d.docente_id),
        docenteNombre: d.docente_nombre,
        facultad: d.facultad,
        sede: d.sede,
        calificacion: redondear(d.avg_general),
        indicePolarizacion: round2(d.indice_polarizacion),
        avgHorasEstudio: redondear(d.avg_horas_estudio),
        tasaRechazoPct: pct(d.tasa_rechazo_bruta),
        ratioGuardadosResena: redondear(d.ratio_guardados_resena),
        totalResenas: Number(d.total_resenas_aprobadas),
        razones: explicarAlertaDocente(d),
      })),
      resenasAnomalasResumen: {
        totalAnalizadas: Number(resMeta.n_muestras || 0),
        totalAnomalasDetectadas: Number(resMeta.n_outliers || 0),
        totalPromocionalesDetectadas: Number(resMeta.promocionales || 0),
        totalAnomalasPendientes: anomResRes.rows.filter((r) => r.estado === 'PENDIENTE').length,
      },
      muestraAnomalas: anomResRes.rows.map((r) => ({
        resenaId: Number(r.resena_id),
        docenteId: Number(r.docente_id),
        docenteNombre: r.docente_nombre,
        usuarioCorreo: r.usuario_correo,
        estado: r.estado,
        calificacion: redondear(r.calificacion_promedio),
        comentario: r.comentario,
        razones: explicarAlertaResena(r),
      })),
    },
  };
}

export async function obtenerHistorialModeracion(limit = 30) {
  const res = await query(
    `SELECT
       mh.id,
       mh.resena_id,
       mh.estado_anterior,
       mh.estado_nuevo,
       mh.observacion,
       mh.creado_en,
       d.nombre AS docente_nombre,
       u.nombre AS admin_nombre
     FROM moderacion_historial mh
     JOIN resenas r ON r.id = mh.resena_id
     JOIN docentes d ON d.id = r.docente_id
     LEFT JOIN usuarios u ON u.id = mh.admin_id
     ORDER BY mh.creado_en DESC
     LIMIT $1`,
    [Math.min(100, Math.max(1, Number(limit) || 30))]
  );
  return res.rows.map((r) => ({
    id: Number(r.id),
    resenaId: Number(r.resena_id),
    docenteNombre: r.docente_nombre,
    adminNombre: r.admin_nombre || 'Sistema',
    estadoAnterior: r.estado_anterior,
    estadoNuevo: r.estado_nuevo,
    observacion: r.observacion || null,
    creadoEn: r.creado_en,
  }));
}

export async function recalcularClustering(adminId = null) {
  const pythonBin = process.env.ML_PYTHON_BIN || DEFAULT_PYTHON_BIN;
  const env = {
    ...process.env,
    DATABASE_URL: process.env.DATABASE_URL,
  };
  if (adminId) {
    env.ADMIN_ID = String(adminId);
  }
  const { stdout } = await execFileAsync(pythonBin, [ML_SCRIPT_PATH], {
    env,
    timeout: 60000,
  });
  return JSON.parse(stdout);
}
