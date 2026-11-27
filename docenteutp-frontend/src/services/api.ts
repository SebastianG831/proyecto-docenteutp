import type {
  Curso,
  Docente,
  DocenteDetalle,
  EstadisticasResponse,
  ModeracionHistorialItem,
  ReporteDocente,
  Resena,
  ResenaInput,
  UsuarioAdmin,
  UsuarioAuth,
} from '../types/api';

const BASE_URL = import.meta.env.VITE_API_URL || '/api';

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: {
      'Content-Type': 'application/json',
      ...(options?.headers || {}),
    },
    ...options,
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data?.mensaje || `Error ${res.status} al comunicarse con el servidor`);
  }
  return data as T;
}

export const authApi = {
  login: (correo: string, password: string) =>
    request<UsuarioAuth>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ correo, password }),
    }),
  registro: (payload: {
    nombre: string;
    correo: string;
    password: string;
    carrera: string;
    ciclo: number;
  }) =>
    request<UsuarioAuth>('/auth/registro', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
};

export const docentesApi = {
  buscar: (
    params: {
      q?: string;
      estilo?: string;
      dificultad?: string;
      sede?: string;
      modalidad?: string;
      perfil?: string;
      sort?: string;
    } = {}
  ) => {
    const sp = new URLSearchParams();
    if (params.q) sp.set('q', params.q);
    if (params.estilo) sp.set('estilo', params.estilo);
    if (params.dificultad) sp.set('dificultad', params.dificultad);
    if (params.sede) sp.set('sede', params.sede);
    if (params.modalidad) sp.set('modalidad', params.modalidad);
    if (params.perfil) sp.set('perfil', params.perfil);
    if (params.sort) sp.set('sort', params.sort);
    const qs = sp.toString();
    return request<Docente[]>(`/docentes${qs ? `?${qs}` : ''}`);
  },
  obtenerDetalle: (id: number) => request<DocenteDetalle>(`/docentes/${id}`),
};

export const cursosApi = {
  listar: (q?: string) =>
    request<Curso[]>(`/cursos${q ? `?q=${encodeURIComponent(q)}` : ''}`),
  docentesDelCurso: (cursoId: number) =>
    request<Docente[]>(`/cursos/${cursoId}/docentes`),
};

export const resenasApi = {
  publicar: (payload: ResenaInput) =>
    request<Resena>('/resenas', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
  porDocente: (docenteId: number) => request<Resena[]>(`/resenas/docente/${docenteId}`),
  porUsuario: (usuarioId: number) => request<Resena[]>(`/resenas/usuario/${usuarioId}`),
  votarUtil: (id: number, usuarioId: number, esUtil = true) =>
    request<{ votosUtiles: number }>(`/resenas/${id}/voto`, {
      method: 'POST',
      body: JSON.stringify({ usuarioId, esUtil }),
    }),
  eliminar: (id: number, usuarioId: number) =>
    request<{ mensaje: string }>(`/resenas/${id}?usuarioId=${usuarioId}`, {
      method: 'DELETE',
    }),
};

export const guardadosApi = {
  listar: (usuarioId: number) => request<Docente[]>(`/guardados/usuario/${usuarioId}`),
  guardar: (usuarioId: number, docenteId: number) =>
    request<{ mensaje: string }>(`/guardados/usuario/${usuarioId}/docente/${docenteId}`, {
      method: 'POST',
    }),
  quitar: (usuarioId: number, docenteId: number) =>
    request<{ mensaje: string }>(`/guardados/usuario/${usuarioId}/docente/${docenteId}`, {
      method: 'DELETE',
    }),
};

export const estadisticasApi = {
  obtener: () => request<EstadisticasResponse>('/estadisticas'),
};

export const adminApi = {
  pendientes: () => request<Resena[]>('/admin/resenas/pendientes'),
  aprobar: (id: number, adminId?: number) =>
    request<{ mensaje: string }>(`/admin/resenas/${id}/aprobar`, {
      method: 'PUT',
      body: JSON.stringify({ adminId }),
    }),
  rechazar: (id: number, adminId?: number, motivo?: string) =>
    request<{ mensaje: string }>(`/admin/resenas/${id}/rechazar`, {
      method: 'PUT',
      body: JSON.stringify({ adminId, motivo }),
    }),
  reporteDocentes: () => request<ReporteDocente[]>('/admin/reportes/docentes'),
  usuarios: () => request<UsuarioAdmin[]>('/admin/usuarios'),
  historialModeracion: () => request<ModeracionHistorialItem[]>('/admin/moderacion/historial'),
  recalcularMl: (adminId?: number) =>
    request<{ mensaje: string; resumen: Record<string, unknown> }>('/admin/ml/recalcular', {
      method: 'POST',
      body: JSON.stringify({ adminId }),
    }),
  crearDocente: (payload: {
    nombre: string;
    facultad: string;
    sede?: string;
    estiloEnsenanza: string;
    estiloEvaluacion: string;
    modalidadPrincipal?: string;
    resumen?: string;
    etiquetas?: string;
    cursoIds?: number[];
  }) =>
    request<Docente>('/admin/docentes', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
};
