export type Rol = 'ESTUDIANTE' | 'ADMIN';
export type NivelDificultad = 'LIGERO' | 'MODERADO' | 'EXIGENTE';
export type EstadoResena = 'PENDIENTE' | 'APROBADA' | 'RECHAZADA';

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
}

export interface Docente {
  id: number;
  nombre: string;
  facultad: string;
  cursoPrincipal: string;
  calificacion: number;
  totalResenas: number;
  estiloEnsenanza: string;
  verificado: boolean;
  nivelDificultad?: string;
}

export interface DocenteDetalle {
  id: number;
  nombre: string;
  facultad: string;
  sede: string;
  verificado: boolean;
  calificacion: number;
  totalResenas: number;
  criterios: CriterioPromedio[];
  cursos: Curso[];
  nivelDificultad: string;
  estiloEnsenanza: string;
  estiloEvaluacion: string;
  resumen: string;
  etiquetas: string[];
}

export interface Resena {
  id: number;
  docenteId: number;
  docenteNombre: string;
  cursoNombre: string;
  calificacion: number;
  dominio: number;
  claridad: number;
  empatia: number;
  dificultad: NivelDificultad;
  comentario: string;
  estado: EstadoResena;
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
  dificultad: NivelDificultad;
  comentario: string;
}

export interface ReporteDocente {
  docenteId: number;
  docenteNombre: string;
  facultad: string;
  promedioGeneral: number;
  promedioDominio: number;
  promedioClaridad: number;
  promedioEmpatia: number;
  totalResenas: number;
  resenasPendientes: number;
}

export interface UsuarioAdmin {
  id: number;
  nombre: string;
  correo: string;
  carrera: string;
  ciclo: number;
  rol: Rol;
  creadoEn: string;
  totalResenas: number;
}
