import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import {
  BarChart3,
  Check,
  Clock,
  Plus,
  ShieldAlert,
  Star,
  Users,
  X,
} from 'lucide-react';
import { adminApi, cursosApi } from '../services/api';
import type { Curso, ReporteDocente, Resena, UsuarioAdmin } from '../types/api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import { formatRelativeDate } from '../utils/formatters';

type AdminTab = 'reportes' | 'moderacion' | 'gestion';

export function AdminPage() {
  const { user } = useAuth();
  const { showToast } = useToast();

  const [tab, setTab] = useState<AdminTab>('reportes');
  const [reportes, setReportes] = useState<ReporteDocente[]>([]);
  const [pendientes, setPendientes] = useState<Resena[]>([]);
  const [usuarios, setUsuarios] = useState<UsuarioAdmin[]>([]);
  const [cursos, setCursos] = useState<Curso[]>([]);
  const [loading, setLoading] = useState(true);

  const [nombre, setNombre] = useState('');
  const [facultad, setFacultad] = useState('Facultad de Ingeniería · Ingeniería de Sistemas');
  const [estiloEnsenanza, setEstiloEnsenanza] = useState('Explicación clara');
  const [estiloEvaluacion, setEstiloEvaluacion] = useState('Prácticas y exámenes');
  const [resumen, setResumen] = useState('');
  const [etiquetas, setEtiquetas] = useState('Metodología clara,Práctica semanal');
  const [cursoId, setCursoId] = useState<number>(1);

  const loadAll = useCallback(async () => {
    setLoading(true);
    try {
      const [rep, pend, users, cur] = await Promise.all([
        adminApi.reporteDocentes(),
        adminApi.pendientes(),
        adminApi.usuarios(),
        cursosApi.listar(),
      ]);
      setReportes(rep);
      setPendientes(pend);
      setUsuarios(users);
      setCursos(cur);
      if (cur.length > 0) setCursoId(cur[0].id);
    } catch (err) {
      showToast((err as Error).message, 'error');
    } finally {
      setLoading(false);
    }
  }, [showToast]);

  useEffect(() => {
    if (user?.rol === 'ADMIN') loadAll();
    else setLoading(false);
  }, [user?.rol, loadAll]);

  const handleModerate = async (id: number, aprobar: boolean) => {
    try {
      if (aprobar) await adminApi.aprobar(id);
      else await adminApi.rechazar(id);
      showToast(aprobar ? 'Reseña aprobada y publicada' : 'Reseña rechazada', 'success');
      await loadAll();
    } catch (err) {
      showToast((err as Error).message, 'error');
    }
  };

  const handleCreateDocente = async (e: FormEvent) => {
    e.preventDefault();
    try {
      await adminApi.crearDocente({
        nombre,
        facultad,
        estiloEnsenanza,
        estiloEvaluacion,
        resumen,
        etiquetas,
        cursoIds: cursoId ? [cursoId] : [],
      });
      showToast('Docente registrado en el catálogo UTP', 'success');
      setNombre('');
      setResumen('');
      await loadAll();
    } catch (err) {
      showToast((err as Error).message, 'error');
    }
  };

  if (!user || user.rol !== 'ADMIN') {
    return (
      <div className="container" style={{ padding: '48px 24px' }}>
        <div className="card card-pad" style={{ textAlign: 'center', padding: 40 }}>
          <ShieldAlert size={34} color="#d97706" style={{ marginBottom: 12 }} />
          <h1 style={{ fontSize: 24, marginBottom: 8 }}>Acceso exclusivo para Coordinación UTP</h1>
          <p style={{ color: 'var(--ink-muted)', marginBottom: 18 }}>
            Inicia sesión con la cuenta institucional de Coordinación Académica para ver el panel
            de analítica B2B y moderación.
          </p>
          <Link to="/login" className="btn btn-primary">
            Ir a iniciar sesión
          </Link>
        </div>
      </div>
    );
  }

  const totalAprobadas = reportes.reduce((acc, r) => acc + r.totalResenas, 0);
  const avgGlobal =
    reportes.length > 0
      ? reportes.reduce((acc, r) => acc + r.promedioGeneral, 0) / reportes.length
      : 0;

  return (
    <div className="container" style={{ padding: '36px 24px 56px' }}>
      <div className="section-header" style={{ marginBottom: 22 }}>
        <div>
          <div className="eyebrow">Licencia Institucional B2B · UTP Lima Centro</div>
          <h1 style={{ fontSize: 30, fontWeight: 700 }}>Panel de Analítica y Moderación</h1>
        </div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <button
            type="button"
            className={`filter-chip ${tab === 'reportes' ? 'active' : ''}`}
            onClick={() => setTab('reportes')}
          >
            Analítica Docente ({reportes.length})
          </button>
          <button
            type="button"
            className={`filter-chip ${tab === 'moderacion' ? 'active' : ''}`}
            onClick={() => setTab('moderacion')}
          >
            Cola de Moderación ({pendientes.length})
          </button>
          <button
            type="button"
            className={`filter-chip ${tab === 'gestion' ? 'active' : ''}`}
            onClick={() => setTab('gestion')}
          >
            Docentes y Usuarios
          </button>
        </div>
      </div>

      <div className="kpi-grid">
        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Promedio institucional</span>
            <Star size={18} color="#d97706" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>{avgGlobal.toFixed(2)} / 5</div>
        </div>
        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Reseñas aprobadas</span>
            <BarChart3 size={18} color="#065f46" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>{totalAprobadas}</div>
        </div>
        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Pendientes de revisión</span>
            <Clock size={18} color="#d97706" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>{pendientes.length}</div>
        </div>
        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Usuarios verificados</span>
            <Users size={18} color="#2b5c8f" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>{usuarios.length}</div>
        </div>
      </div>

      {loading ? (
        <div className="card card-pad">Cargando datos institucionales...</div>
      ) : tab === 'reportes' ? (
        <div className="card">
          <div style={{ padding: '18px 22px', borderBottom: '1px solid var(--border)' }}>
            <h2 style={{ fontSize: 18, fontWeight: 700 }}>Ranking y Métricas por Docente</h2>
          </div>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Docente</th>
                  <th>Facultad</th>
                  <th>General</th>
                  <th>Dominio</th>
                  <th>Claridad</th>
                  <th>Empatía</th>
                  <th>Aprobadas</th>
                  <th>Pendientes</th>
                </tr>
              </thead>
              <tbody>
                {reportes.map((r) => (
                  <tr key={r.docenteId}>
                    <td>
                      <Link
                        to={`/docentes/${r.docenteId}`}
                        style={{ fontWeight: 700, color: 'var(--brand-blue)' }}
                      >
                        {r.docenteNombre}
                      </Link>
                    </td>
                    <td style={{ color: 'var(--ink-muted)' }}>{r.facultad}</td>
                    <td>
                      <span className="rating-chip">{r.promedioGeneral.toFixed(1)}</span>
                    </td>
                    <td>{r.promedioDominio.toFixed(1)}</td>
                    <td>{r.promedioClaridad.toFixed(1)}</td>
                    <td>{r.promedioEmpatia.toFixed(1)}</td>
                    <td>{r.totalResenas}</td>
                    <td>
                      {r.resenasPendientes > 0 ? (
                        <span className="status-badge status-PENDIENTE">{r.resenasPendientes}</span>
                      ) : (
                        <span style={{ color: 'var(--ink-muted)' }}>0</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : tab === 'moderacion' ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          {pendientes.length === 0 ? (
            <div className="card card-pad" style={{ textAlign: 'center', padding: 36 }}>
              No hay reseñas pendientes en la cola de moderación.
            </div>
          ) : (
            pendientes.map((r) => (
              <div key={r.id} className="card review-card">
                <div className="review-top">
                  <div>
                    <strong style={{ fontSize: 16 }}>{r.docenteNombre}</strong>
                    <div style={{ fontSize: 13, color: 'var(--ink-muted)' }}>
                      {r.cursoNombre} · Enviada {formatRelativeDate(r.fecha)}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 8 }}>
                    <button
                      type="button"
                      className="btn btn-emerald btn-sm"
                      onClick={() => handleModerate(r.id, true)}
                    >
                      <Check size={15} />
                      <span>Aprobar</span>
                    </button>
                    <button
                      type="button"
                      className="btn btn-danger-soft btn-sm"
                      onClick={() => handleModerate(r.id, false)}
                    >
                      <X size={15} />
                      <span>Rechazar</span>
                    </button>
                  </div>
                </div>
                <div style={{ fontSize: 13, color: 'var(--ink-muted)', marginBottom: 8 }}>
                  Dominio {r.dominio}/5 · Claridad {r.claridad}/5 · Empatía {r.empatia}/5 · Dificultad{' '}
                  <strong>{r.dificultad}</strong>
                </div>
                <p style={{ margin: 0 }}>{r.comentario}</p>
              </div>
            ))
          )}
        </div>
      ) : (
        <div className="two-col" style={{ paddingBottom: 0 }}>
          <div className="card">
            <div style={{ padding: '18px 22px', borderBottom: '1px solid var(--border)' }}>
              <h2 style={{ fontSize: 18, fontWeight: 700 }}>Comunidad Verificada</h2>
            </div>
            <div className="table-wrap">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Nombre</th>
                    <th>Correo UTP</th>
                    <th>Carrera</th>
                    <th>Rol</th>
                    <th>Reseñas</th>
                  </tr>
                </thead>
                <tbody>
                  {usuarios.map((u) => (
                    <tr key={u.id}>
                      <td>
                        <strong>{u.nombre}</strong>
                      </td>
                      <td>{u.correo}</td>
                      <td>
                        {u.carrera} (Ciclo {u.ciclo})
                      </td>
                      <td>
                        <span className="pill-verified">{u.rol}</span>
                      </td>
                      <td>{u.totalResenas}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="card card-pad">
            <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 14 }}>Registrar Docente</h2>
            <form onSubmit={handleCreateDocente}>
              <div className="form-group">
                <label className="form-label">Nombre completo</label>
                <input
                  type="text"
                  className="form-control"
                  value={nombre}
                  onChange={(e) => setNombre(e.target.value)}
                  required
                />
              </div>
              <div className="form-group">
                <label className="form-label">Facultad / Carrera</label>
                <input
                  type="text"
                  className="form-control"
                  value={facultad}
                  onChange={(e) => setFacultad(e.target.value)}
                  required
                />
              </div>
              <div className="form-group">
                <label className="form-label">Curso principal</label>
                <select
                  className="form-control"
                  value={cursoId}
                  onChange={(e) => setCursoId(Number(e.target.value))}
                >
                  {cursos.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.codigo} — {c.nombre}
                    </option>
                  ))}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">Estilo de enseñanza</label>
                <input
                  type="text"
                  className="form-control"
                  value={estiloEnsenanza}
                  onChange={(e) => setEstiloEnsenanza(e.target.value)}
                  required
                />
              </div>
              <div className="form-group">
                <label className="form-label">Estilo de evaluación</label>
                <input
                  type="text"
                  className="form-control"
                  value={estiloEvaluacion}
                  onChange={(e) => setEstiloEvaluacion(e.target.value)}
                  required
                />
              </div>
              <div className="form-group">
                <label className="form-label">Resumen ("En pocas palabras")</label>
                <textarea
                  className="form-control"
                  rows={3}
                  value={resumen}
                  onChange={(e) => setResumen(e.target.value)}
                />
              </div>
              <div className="form-group">
                <label className="form-label">Etiquetas (separadas por coma)</label>
                <input
                  type="text"
                  className="form-control"
                  value={etiquetas}
                  onChange={(e) => setEtiquetas(e.target.value)}
                />
              </div>
              <button type="submit" className="btn btn-primary" style={{ width: '100%' }}>
                <Plus size={16} />
                <span>Guardar docente</span>
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
