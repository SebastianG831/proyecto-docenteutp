export type Rol = 'ESTUDIANTE' | 'MODERADOR' | 'ADMIN';
export type NivelDificultad = 'LIGERO' | 'MODERADO' | 'EXIGENTE';
export type EstadoResena = 'PENDIENTE' | 'APROBADA' | 'RECHAZADA' | 'MARCADA_ANOMALIA';

export interface UsuarioAuth {
  id: number;
  nombre: string;
  correo: string;
  carrera: string;
  ciclo: number;
  rol: Rol;
}

export interface CriterioPromedio {
  nombre: string;
  promedio: number;
}

export interface Curso {
  id: number;
  codigo: string;
  nombre: string;
  creditos?: number;
  cicloSugerido?: number | null;
  tipo?: string;
  modalidad?: string;
}

export interface Docente {
  id: number;
  codigoDocente?: string | null;
  nombre: string;
  facultad: string;
  sede?: string;
  cursoPrincipal: string;
  calificacion: number;
  calificacionIntegral?: number;
  totalResenas: number;
  estiloEnsenanza: string;
  modalidadPrincipal?: string;
  verificado: boolean;
  nivelDificultad?: string;
  avgHorasEstudio?: number | null;
  tasaRecomendacion?: number | null;
  perfilMl?: string | null;
  perfilMlId?: number | null;
  esOutlierMl?: boolean;
}

export interface DocenteDetalle {
  id: number;
  codigoDocente?: string | null;
  nombre: string;
  facultad: string;
  sede: string;
  verificado: boolean;
  modalidadPrincipal?: string;
  aniosExperiencia?: number;
  calificacion: number;
  calificacionIntegral?: number;
  totalResenas: number;
  criterios: CriterioPromedio[];
  criteriosExtendidos?: CriterioPromedio[];
  cursos: Curso[];
  nivelDificultad: string;
  estiloEnsenanza: string;
  estiloEvaluacion: string;
  avgHorasEstudio?: number | null;
  tasaRecomendacion?: number | null;
  avgNotaObtenida?: number | null;
  indicePolarizacion?: number | null;
  perfilMl?: string | null;
  perfilMlDesc?: string | null;
  esOutlierMl?: boolean;
  resumen: string;
  etiquetas: string[];
}

export interface Resena {
  id: number;
  docenteId: number;
  docenteNombre: string;
  cursoNombre: string;
  periodoCodigo?: string | null;
  calificacion: number;
  dominio: number;
  claridad: number;
  empatia: number;
  retroalimentacion?: number;
  organizacion?: number;
  puntualidad?: number;
  dificultad: NivelDificultad;
  horasEstudioSemanal?: number;
  recomienda?: boolean;
  asistenciaObligatoria?: boolean;
  notaObtenida?: number | null;
  comentario: string;
  estado: EstadoResena;
  esAnomaliaMl?: boolean;
  motivoRechazo?: string | null;
  votosUtiles?: number;
  totalReportes?: number;
  fecha: string;
  autorIniciales?: string;
}

export interface ResenaInput {
  usuarioId: number;
  docenteId: number;
  cursoId: number;
  dominio: number;
  claridad: number;
  empatia: number;
  retroalimentacion?: number;
  organizacion?: number;
  puntualidad?: number;
  dificultad: NivelDificultad;
  horasEstudioSemanal?: number;
  recomienda?: boolean;
  asistenciaObligatoria?: boolean;
  notaObtenida?: number | null;
  comentario: string;
}

export interface ReporteDocente {
  docenteId: number;
  docenteNombre: string;
  facultad: string;
  sede?: string;
  modalidadPrincipal?: string;
  promedioGeneral: number;
  calificacionIntegral?: number;
  promedioDominio: number;
  promedioClaridad: number;
  promedioEmpatia: number;
  totalResenas: number;
  resenasPendientes: number;
  nivelDificultad?: string;
  avgHorasEstudio?: number;
  tasaRecomendacion?: number;
  indicePolarizacion?: number;
  perfilMl?: string | null;
  esOutlierMl?: boolean;
}

export interface UsuarioAdmin {
  id: number;
  nombre: string;
  correo: string;
  carrera: string;
  ciclo: number;
  rol: Rol;
  activo?: boolean;
  creadoEn: string;
  totalResenas: number;
}

export interface DocenteClusterItem {
  id: number;
  nombre: string;
  facultad: string;
  sede: string;
  cursoPrincipal: string;
  calificacion: number;
  totalResenas: number;
  avgHorasEstudio: number;
  tasaRecomendacionPct: number;
  nivelDificultad: string;
  probabilidadPertenencia: number | null;
}

export interface PerfilDocenteGrupo {
  clusterLabel: number;
  nombre: string;
  descripcion: string;
  consejoEstudiante: string;
  tamano: number;
  porcentaje: number;
  metricas: {
    dominio: number;
    claridad: number;
    empatia: number;
    calificacionPromedio: number;
    dificultadScore: number;
    dificultadTexto: string;
    horasEstudio: number;
    tasaRecomendacionPct: number;
  };
  docentes: DocenteClusterItem[];
}

export interface PerfilDocenteModelo {
  algoritmo: string;
  modeloLabel: string;
  experimentoId: number;
  nMuestras: number;
  nClusters: number;
  calidadSeparacionPct: number | null;
  interpretacionCalidad: string;
  hiperparametros: Record<string, unknown>;
  ejecutadoEn: string;
  grupos: PerfilDocenteGrupo[];
}

export interface MapaDocentePoint {
  id: number;
  nombre: string;
  facultad: string;
  sede: string;
  modalidadPrincipal: string;
  cursoPrincipal: string;
  calificacion: number;
  calificacionIntegral: number;
  avgDominio: number;
  avgClaridad: number;
  avgEmpatia: number;
  dificultadScore: number;
  nivelDificultad: string;
  avgHorasEstudio: number;
  tasaRecomendacionPct: number;
  avgNotaObtenida: number;
  indicePolarizacion: number;
  totalResenas: number;
  totalGuardados: number;
  perfilKmeansId: number | null;
  perfilKmeans: string;
  perfilMeanshiftId: number | null;
  perfilMeanshift: string;
  esOutlierDbscan: boolean;
}

export interface PerfilEstudianteGrupo {
  clusterLabel: number;
  nombre: string;
  descripcion: string;
  tamano: number;
  porcentaje: number;
  cicloPromedio: number;
  resenasPromedio: number;
  guardadosPromedio: number;
  calificacionDadaPromedio: number;
  horasReportadasPromedio: number;
  tasaRecomendacionPct: number;
}

export interface AlertaDocente {
  docenteId: number;
  docenteNombre: string;
  facultad: string;
  sede: string;
  calificacion: number;
  indicePolarizacion: number;
  avgHorasEstudio: number;
  tasaRechazoPct: number;
  ratioGuardadosResena: number;
  totalResenas: number;
  razones: string[];
}

export interface AlertaResena {
  resenaId: number;
  docenteId: number;
  docenteNombre: string;
  usuarioCorreo: string;
  estado: EstadoResena;
  calificacion: number;
  comentario: string;
  razones: string[];
}

export interface EstadisticasResponse {
  resumen: {
    totalDocentes: number;
    totalResenasAprobadas: number;
    totalResenasPendientes: number;
    totalResenasRechazadas: number;
    totalEstudiantesActivos: number;
    totalCursos: number;
    totalSedes: number;
    promedioGeneral: number;
    tasaRecomendacionGlobal: number;
    avgHorasEstudioGlobal: number;
    avgNotaReportada: number;
    ultimaActualizacionMl: string | null;
  };
  perfilesDocentes: {
    kmeans: PerfilDocenteModelo | null;
    meanshift: PerfilDocenteModelo | null;
  };
  mapaDocentes: MapaDocentePoint[];
  distribuciones: {
    porSede: Array<{
      nombre: string;
      ciudad: string;
      totalDocentes: number;
      totalResenas: number;
      calificacionPromedio: number;
      tasaRecomendacionPct: number;
    }>;
    porFacultad: Array<{
      nombre: string;
      totalDocentes: number;
      totalResenas: number;
      calificacionPromedio: number;
      avgHorasEstudio: number;
      tasaRecomendacionPct: number;
    }>;
    porModalidad: Array<{
      modalidad: string;
      totalDocentes: number;
      totalResenas: number;
      calificacionPromedio: number;
      avgHorasEstudio: number;
      tasaRecomendacionPct: number;
    }>;
    porPeriodo: Array<{
      codigo: string;
      esActual: boolean;
      totalResenas: number;
      calificacionPromedio: number;
      avgHorasEstudio: number;
      tasaRecomendacionPct: number;
    }>;
    porDificultad: Array<{
      nivel: string;
      totalResenas: number;
      porcentaje: number;
      calificacionPromedio: number;
      avgHorasEstudio: number;
    }>;
  };
  perfilesEstudiantes: {
    algoritmo: string;
    nMuestras: number;
    nClusters: number;
    calidadSeparacionPct: number | null;
    grupos: PerfilEstudianteGrupo[];
  } | null;
  alertasCalidad: {
    docentesAtipicos: AlertaDocente[];
    resenasAnomalasResumen: {
      totalAnalizadas: number;
      totalAnomalasDetectadas: number;
      totalPromocionalesDetectadas: number;
      totalAnomalasPendientes: number;
    };
    muestraAnomalas: AlertaResena[];
  };
}

export interface ModeracionHistorialItem {
  id: number;
  resenaId: number;
  docenteNombre: string;
  adminNombre: string;
  estadoAnterior: string;
  estadoNuevo: string;
  observacion: string | null;
  creadoEn: string;
}
