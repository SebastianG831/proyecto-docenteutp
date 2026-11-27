import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import {
  AlertTriangle,
  BarChart3,
  Check,
  Clock,
  History,
  Plus,
  RefreshCw,
  ShieldAlert,
  Sparkles,
  Star,
  Users,
  X,
} from 'lucide-react';
import { adminApi, cursosApi, estadisticasApi } from '../services/api';
import type {
  Curso,
  EstadisticasResponse,
  ModeracionHistorialItem,
  ReporteDocente,
  Resena,
  UsuarioAdmin,
} from '../types/api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import { formatRelativeDate } from '../utils/formatters';

type AdminTab = 'reportes' | 'moderacion' | 'alertas' | 'gestion';

export function AdminPage() {
  const { user } = useAuth();
  const { showToast } = useToast();

  const [tab, setTab] = useState<AdminTab>('reportes');
  const [reportes, setReportes] = useState<ReporteDocente[]>([]);
  const [pendientes, setPendientes] = useState<Resena[]>([]);
  const [usuarios, setUsuarios] = useState<UsuarioAdmin[]>([]);
  const [cursos, setCursos] = useState<Curso[]>([]);
  const [estadisticas, setEstadisticas] = useState<EstadisticasResponse | null>(null);
  const [historial, setHistorial] = useState<ModeracionHistorialItem[]>([]);
  const [onlyMlAlerts, setOnlyMlAlerts] = useState(false);
  const [rejectReasons, setRejectReasons] = useState<Record<number, string>>({});
  const [recalculating, setRecalculating] = useState(false);
  const [loading, setLoading] = useState(true);

  const [nombre, setNombre] = useState('');
  const [facultad, setFacultad] = useState('Facultad de Ingeniería · Ingeniería de Sistemas');
  const [sede, setSede] = useState('UTP Lima Centro · Edificio Arequipa');
  const [modalidadPrincipal, setModalidadPrincipal] = useState('PRESENCIAL');
  const [estiloEnsenanza, setEstiloEnsenanza] = useState('Explicación clara');
  const [estiloEvaluacion, setEstiloEvaluacion] = useState('Prácticas y exámenes');
  const [resumen, setResumen] = useState('');
  const [etiquetas, setEtiquetas] = useState('Metodología clara,Práctica semanal');
  const [cursoId, setCursoId] = useState<number>(1);

  const isStaff = user?.rol === 'ADMIN' || user?.rol === 'MODERADOR';

  const loadAll = useCallback(async () => {
    setLoading(true);
    try {
      const [rep, pend, users, cur, est, hist] = await Promise.all([
        adminApi.reporteDocentes(),
        adminApi.pendientes(),
        adminApi.usuarios(),
        cursosApi.listar(),
        estadisticasApi.obtener(),
        adminApi.historialModeracion(),
      ]);
      setReportes(rep);
      setPendientes(pend);
      setUsuarios(users);
      setCursos(cur);
      setEstadisticas(est);
      setHistorial(hist);
      if (cur.length > 0) setCursoId(cur[0].id);
    } catch (err) {
      showToast((err as Error).message, 'error');
    } finally {
      setLoading(false);
    }
  }, [showToast]);

  useEffect(() => {
    if (isStaff) loadAll();
    else setLoading(false);
  }, [isStaff, loadAll]);

  const handleModerate = async (id: number, aprobar: boolean) => {
    try {
      if (aprobar) {
        await adminApi.aprobar(id, user?.id);
      } else {
        await adminApi.rechazar(id, user?.id, rejectReasons[id]);
      }
      showToast(aprobar ? 'Reseña aprobada y publicada' : 'Reseña rechazada', 'success');
      await loadAll();
    } catch (err) {
      showToast((err as Error).message, 'error');
    }
  };

  const handleRecalculateMl = async () => {
    setRecalculating(true);
    try {
      await adminApi.recalcularMl(user?.id);
      showToast('Modelos K-Means, Mean Shift y DBSCAN recalculados con datos actuales', 'success');
      await loadAll();
    } catch (err) {
      showToast((err as Error).message, 'error');
    } finally {
      setRecalculating(false);
    }
  };

  const handleCreateDocente = async (e: FormEvent) => {
    e.preventDefault();
    try {
      await adminApi.crearDocente({
        nombre,
        facultad,
        sede,
        modalidadPrincipal,
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

  if (!isStaff) {
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
  const mlAlertsCount = pendientes.filter((r) => r.esAnomaliaMl).length;
  const filteredPendientes = onlyMlAlerts ? pendientes.filter((r) => r.esAnomaliaMl) : pendientes;

  return (
    <div className="container" style={{ padding: '36px 24px 56px' }}>
      <div className="section-header" style={{ marginBottom: 22 }}>
        <div>
          <div className="eyebrow">Licencia Institucional B2B · UTP</div>
          <h1 style={{ fontSize: 30, fontWeight: 700 }}>Panel de Analítica y Moderación</h1>
        </div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
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
            className={`filter-chip ${tab === 'alertas' ? 'active' : ''}`}
            onClick={() => setTab('alertas')}
          >
            Alertas ML y Auditoría ({(estadisticas?.alertasCalidad.docentesAtipicos.length || 0) + mlAlertsCount})
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
            <span>Pendientes ({mlAlertsCount} sospecha ML)</span>
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
          <div
            style={{
              padding: '18px 22px',
              borderBottom: '1px solid var(--border)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              flexWrap: 'wrap',
              gap: 10,
            }}
          >
            <div>
              <h2 style={{ fontSize: 18, fontWeight: 700 }}>Ranking y Métricas por Docente</h2>
              <div style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>
                Incluye perfil K-Means, carga de estudio semanal, recomendación y alertas DBSCAN.
              </div>
            </div>
            <Link to="/estadisticas" className="btn btn-outline btn-sm">
              <Sparkles size={14} />
              <span>Ver sitio de estadísticas</span>
            </Link>
          </div>
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Docente</th>
                  <th>Facultad / Sede</th>
                  <th>Perfil ML</th>
                  <th>General</th>
                  <th>Carga</th>
                  <th>Recom.</th>
                  <th>Aprob.</th>
                  <th>Pend.</th>
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
                      {r.esOutlierMl && (
                        <span
                          className="status-badge status-RECHAZADA"
                          style={{ marginLeft: 8, fontSize: 11, padding: '2px 7px' }}
                        >
                          Atípico
                        </span>
                      )}
                    </td>
                    <td style={{ color: 'var(--ink-muted)', fontSize: 12.5 }}>
                      <div>{r.facultad}</div>
                      {r.sede && <div>{r.sede.split('·')[0].trim()}</div>}
                    </td>
                    <td>
                      {r.perfilMl ? (
                        <span className="pill-tag" style={{ fontSize: 11.5 }}>
                          {r.perfilMl}
                        </span>
                      ) : (
                        <span style={{ color: 'var(--ink-muted)' }}>—</span>
                      )}
                    </td>
                    <td>
                      <span className="rating-chip">{r.promedioGeneral.toFixed(1)}</span>
                    </td>
                    <td>{r.avgHorasEstudio != null ? `${r.avgHorasEstudio} h/s` : '—'}</td>
                    <td>{r.tasaRecomendacion != null ? `${r.tasaRecomendacion}%` : '—'}</td>
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
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <button
              type="button"
              className={`filter-chip ${!onlyMlAlerts ? 'active' : ''}`}
              onClick={() => setOnlyMlAlerts(false)}
            >
              Todas las pendientes ({pendientes.length})
            </button>
            <button
              type="button"
              className={`filter-chip ${onlyMlAlerts ? 'active-sage' : ''}`}
              onClick={() => setOnlyMlAlerts(true)}
            >
              Solo alertas de spam DBSCAN ({mlAlertsCount})
            </button>
          </div>

          {filteredPendientes.length === 0 ? (
            <div className="card card-pad" style={{ textAlign: 'center', padding: 36 }}>
              No hay reseñas pendientes en esta vista de moderación.
            </div>
          ) : (
            filteredPendientes.map((r) => (
              <div
                key={r.id}
                className="card review-card"
                style={r.esAnomaliaMl ? { borderColor: '#fca5a5', background: '#fffafa' } : undefined}
              >
                <div className="review-top">
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                      <strong style={{ fontSize: 16 }}>{r.docenteNombre}</strong>
                      {r.esAnomaliaMl && (
                        <span className="status-badge status-RECHAZADA" style={{ gap: 4 }}>
                          <AlertTriangle size={13} />
                          <span>Sospecha de spam / anomalía ML</span>
                        </span>
                      )}
                      {Number(r.totalReportes || 0) > 0 && (
                        <span className="status-badge status-PENDIENTE">
                          {r.totalReportes} reportes
                        </span>
                      )}
                    </div>
                    <div style={{ fontSize: 13, color: 'var(--ink-muted)', marginTop: 2 }}>
                      {r.cursoNombre} {r.periodoCodigo ? `(${r.periodoCodigo})` : ''} · Enviada{' '}
                      {formatRelativeDate(r.fecha)}
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
                  <strong>{r.dificultad}</strong> · Carga{' '}
                  <strong>{r.horasEstudioSemanal ?? 4} h/sem</strong>
                </div>
                <p style={{ margin: '0 0 10px' }}>{r.comentario}</p>
                <input
                  type="text"
                  className="form-control"
                  style={{ maxWidth: 460, padding: '7px 12px', fontSize: 12.5 }}
                  placeholder="Motivo opcional si rechazas (se registra en historial de auditoría)..."
                  value={rejectReasons[r.id] || ''}
                  onChange={(e) =>
                    setRejectReasons((prev) => ({ ...prev, [r.id]: e.target.value }))
                  }
                />
              </div>
            ))
          )}
        </div>
      ) : tab === 'alertas' ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <div className="card card-pad">
            <div className="section-header" style={{ marginBottom: 14 }}>
              <div>
                <h2 style={{ fontSize: 18, fontWeight: 700 }}>
                  Motor de Segmentación y Anomalías (K-Means + Mean Shift + DBSCAN)
                </h2>
                <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--ink-muted)' }}>
                  Recalcula los perfiles docentes, estudiantiles y detección de reseñas spam con los
                  datos más recientes de PostgreSQL.
                </p>
              </div>
              <button
                type="button"
                className="btn btn-primary btn-sm"
                onClick={handleRecalculateMl}
                disabled={recalculating}
              >
                <RefreshCw size={15} />
                <span>{recalculating ? 'Recalculando...' : 'Recalcular modelos ML'}</span>
              </button>
            </div>

            {estadisticas && (
              <div className="compare-grid">
                {estadisticas.alertasCalidad.docentesAtipicos.map((d) => (
                  <div
                    key={d.docenteId}
                    style={{
                      padding: 14,
                      borderRadius: 'var(--radius-md)',
                      background: 'var(--bg-canvas)',
                      border: '1px solid #fecaca',
                    }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                      <Link
                        to={`/docentes/${d.docenteId}`}
                        style={{ fontWeight: 700, color: 'var(--brand-blue)' }}
                      >
                        {d.docenteNombre}
                      </Link>
                      <span className="rating-chip">{d.calificacion.toFixed(1)}★</span>
                    </div>
                    <div style={{ fontSize: 12, color: 'var(--ink-muted)', marginBottom: 8 }}>
                      {d.facultad}
                    </div>
                    {d.razones.map((razon) => (
                      <div key={razon} style={{ fontSize: 12.5, color: '#b45309', marginBottom: 4 }}>
                        • {razon}
                      </div>
                    ))}
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="card">
            <div
              style={{
                padding: '18px 22px',
                borderBottom: '1px solid var(--border)',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}
            >
              <History size={18} color="#2b5c8f" />
              <h2 style={{ fontSize: 18, fontWeight: 700 }}>Auditoría de Moderación</h2>
            </div>
            <div className="table-wrap">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Reseña</th>
                    <th>Docente</th>
                    <th>Cambio de estado</th>
                    <th>Moderador</th>
                    <th>Observación</th>
                    <th>Fecha</th>
                  </tr>
                </thead>
                <tbody>
                  {historial.map((h) => (
                    <tr key={h.id}>
                      <td>#{h.resenaId}</td>
                      <td>
                        <strong>{h.docenteNombre}</strong>
                      </td>
                      <td>
                        <span className="status-badge status-PENDIENTE">{h.estadoAnterior}</span> →{' '}
                        <span className={`status-badge status-${h.estadoNuevo}`}>{h.estadoNuevo}</span>
                      </td>
                      <td>{h.adminNombre}</td>
                      <td style={{ color: 'var(--ink-muted)', fontSize: 12.5 }}>
                        {h.observacion || '—'}
                      </td>
                      <td style={{ color: 'var(--ink-muted)', fontSize: 12.5 }}>
                        {formatRelativeDate(h.creadoEn)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
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
                <label className="form-label">Sede UTP</label>
                <select
                  className="form-control"
                  value={sede}
                  onChange={(e) => setSede(e.target.value)}
                >
                  <option value="UTP Lima Centro · Edificio Arequipa">UTP Lima Centro · Edificio Arequipa</option>
                  <option value="UTP Lima Norte · Panamericana Norte">UTP Lima Norte · Panamericana Norte</option>
                  <option value="UTP Arequipa · Av. Parra">UTP Arequipa · Av. Parra</option>
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">Modalidad principal</label>
                <select
                  className="form-control"
                  value={modalidadPrincipal}
                  onChange={(e) => setModalidadPrincipal(e.target.value)}
                >
                  <option value="PRESENCIAL">Presencial</option>
                  <option value="SEMIPRESENCIAL">Semipresencial</option>
                  <option value="VIRTUAL">Virtual</option>
                </select>
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
