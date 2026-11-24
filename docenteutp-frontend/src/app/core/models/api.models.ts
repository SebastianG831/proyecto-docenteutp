export type Rol = 'ESTUDIANTE' | 'ADMIN';
export type NivelDificultad = 'LIGERO' | 'MODERADO' | 'EXIGENTE';
export type EstadoResena = 'PENDIENTE' | 'APROBADA' | 'RECHAZADA';

export interface AuthResponse {
  id: number;
  nombre: string;
  correo: string;
  carrera: string;
  ciclo: number;
  rol: Rol;
}

export interface LoginRequest {
  correo: string;
  password: string;
}

export interface RegistroRequest {
  nombre: string;
  correo: string;
  password: string;
  carrera: string;
  ciclo: number;
}

export interface CursoResponse {
  id: number;
  codigo: string;
  nombre: string;
}

export interface DocenteResponse {
  id: number;
  nombre: string;
  facultad: string;
  cursoPrincipal: string;
  calificacion: number;
  totalResenas: number;
  estiloEnsenanza: string;
  verificado: boolean;
}

export interface CriterioPromedioResponse {
  criterio: string;
  promedio: number;
}

export interface DocenteDetalleResponse {
  id: number;
  nombre: string;
  facultad: string;
  sede: string;
  verificado: boolean;
  calificacion: number;
  totalResenas: number;
  criterios: CriterioPromedioResponse[];
  cursos: CursoResponse[];
  nivelDificultad: NivelDificultad | null;
  estiloEvaluacion: string | null;
  resumen: string | null;
  etiquetas: string[];
}

export interface ResenaRequest {
  usuarioId: number;
  docenteId: number;
  cursoId: number;
  dominio: number;
  claridad: number;
  empatia: number;
  dificultad: NivelDificultad;
  comentario: string;
}

export interface ResenaResponse {
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
}

export interface ReporteDocenteResponse {
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

export interface MensajeResponse {
  mensaje: string;
}

export interface ApiErrorResponse {
  mensaje?: string;
  message?: string;
}
