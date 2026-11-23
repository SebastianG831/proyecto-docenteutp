import type {
  Curso,
  Docente,
  DocenteDetalle,
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
  buscar: (params: { q?: string; estilo?: string; dificultad?: string; sort?: string } = {}) => {
    const sp = new URLSearchParams();
    if (params.q) sp.set('q', params.q);
    if (params.estilo) sp.set('estilo', params.estilo);
    if (params.dificultad) sp.set('dificultad', params.dificultad);
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

export const adminApi = {
  pendientes: () => request<Resena[]>('/admin/resenas/pendientes'),
  aprobar: (id: number) =>
    request<{ mensaje: string }>(`/admin/resenas/${id}/aprobar`, { method: 'PUT' }),
  rechazar: (id: number) =>
    request<{ mensaje: string }>(`/admin/resenas/${id}/rechazar`, { method: 'PUT' }),
  reporteDocentes: () => request<ReporteDocente[]>('/admin/reportes/docentes'),
  usuarios: () => request<UsuarioAdmin[]>('/admin/usuarios'),
  crearDocente: (payload: {
    nombre: string;
    facultad: string;
    sede?: string;
    estiloEnsenanza: string;
    estiloEvaluacion: string;
    resumen?: string;
    etiquetas?: string;
    cursoIds?: number[];
  }) =>
    request<Docente>('/admin/docentes', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),
};
