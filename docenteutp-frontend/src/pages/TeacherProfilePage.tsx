import { useCallback, useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import {
  BadgeCheck,
  Bookmark,
  ChevronRight,
  MapPin,
  Plus,
  ShieldCheck,
  Sparkles,
  Star,
} from 'lucide-react';
import { docentesApi, resenasApi } from '../services/api';
import type { DocenteDetalle, Resena } from '../types/api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import { CriteriaBar } from '../components/CriteriaBar';
import { RatingStars } from '../components/RatingStars';
import { ReviewModal } from '../components/ReviewModal';
import { formatRelativeDate, getDifficultyBadgeClass, getInitials } from '../utils/formatters';

export function TeacherProfilePage() {
  const { id } = useParams();
  const docenteId = Number(id);
  const { user, savedIds, toggleSaved } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [detalle, setDetalle] = useState<DocenteDetalle | null>(null);
  const [resenas, setResenas] = useState<Resena[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [modalOpen, setModalOpen] = useState(false);

  const loadData = useCallback(async () => {
    if (!docenteId) return;
    setLoading(true);
    setError('');
    try {
      const [det, revs] = await Promise.all([
        docentesApi.obtenerDetalle(docenteId),
        resenasApi.porDocente(docenteId),
      ]);
      setDetalle(det);
      setResenas(revs);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }, [docenteId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleOpenReview = () => {
    if (!user) {
      showToast('Inicia sesión con tu correo @utp.edu.pe para publicar una reseña', 'info');
      navigate('/login', { state: { from: `/docentes/${docenteId}` } });
      return;
    }
    setModalOpen(true);
  };

  const handleToggleSave = async () => {
    if (!detalle) return;
    if (!user) {
      showToast('Inicia sesión para guardar docentes en tu lista', 'info');
      navigate('/login');
      return;
    }
    try {
      const saved = await toggleSaved(detalle.id);
      showToast(saved ? 'Docente guardado' : 'Docente quitado de guardados', 'success');
    } catch (err) {
      showToast((err as Error).message, 'error');
    }
  };

  if (loading) {
    return (
      <div className="container" style={{ padding: '48px 24px' }}>
        <div className="card card-pad">Cargando perfil del docente...</div>
      </div>
    );
  }

  if (error || !detalle) {
    return (
      <div className="container" style={{ padding: '48px 24px' }}>
        <div className="card card-pad">
          <h2 style={{ marginBottom: 8 }}>No se encontró el docente</h2>
          <p style={{ color: 'var(--ink-muted)' }}>{error}</p>
          <Link to="/" className="btn btn-primary" style={{ marginTop: 12 }}>
            Volver al inicio
          </Link>
        </div>
      </div>
    );
  }

  const isSaved = savedIds.has(detalle.id);
  const facultyShort = detalle.facultad.split('·').pop()?.trim() || detalle.facultad;

  return (
    <div className="container">
      <nav className="breadcrumb" aria-label="Ruta de navegación">
        <Link to="/">Docentes</Link>
        <ChevronRight size={14} />
        <span style={{ color: 'var(--brand-blue)', fontWeight: 500 }}>{facultyShort}</span>
        <ChevronRight size={14} />
        <span>{detalle.nombre}</span>
      </nav>

      <section className="card profile-header">
        <div className="profile-header-left">
          <div className="avatar avatar-lg">{getInitials(detalle.nombre)}</div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 28, fontWeight: 700 }}>{detalle.nombre}</h1>
              {detalle.verificado && (
                <span className="pill-verified-blue">
                  <BadgeCheck size={18} />
                  <span>Identidad institucional verificada</span>
                </span>
              )}
            </div>
            <div style={{ fontSize: 15, color: 'var(--ink-muted)', marginTop: 4 }}>
              {detalle.facultad}
            </div>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                fontSize: 13,
                color: 'var(--ink-muted)',
                marginTop: 4,
              }}
            >
              <MapPin size={14} />
              <span>{detalle.sede}</span>
            </div>
          </div>
        </div>

        <div className="profile-header-right">
          <div className="overall-score-box">
            <div className="overall-score-num">
              <Star size={22} fill="#d97706" color="#d97706" />
              <span>{detalle.calificacion > 0 ? detalle.calificacion.toFixed(1) : '—'}</span>
              <span style={{ fontSize: 13, fontWeight: 500 }}>/ 5</span>
            </div>
            <div style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
              {detalle.totalResenas}{' '}
              {detalle.totalResenas === 1 ? 'reseña verificada' : 'reseñas verificadas'}
            </div>
          </div>

          <button type="button" className="btn btn-outline" onClick={handleToggleSave}>
            <Bookmark size={16} fill={isSaved ? 'currentColor' : 'none'} />
            <span>{isSaved ? 'Guardado' : 'Guardar'}</span>
          </button>

          <button type="button" className="btn btn-primary" onClick={handleOpenReview}>
            <Plus size={17} />
            <span>Escribir reseña</span>
          </button>
        </div>
      </section>

      <section className="two-col">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div className="card card-pad">
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginBottom: 16,
                flexWrap: 'wrap',
                gap: 8,
              }}
            >
              <h2 style={{ fontSize: 19, fontWeight: 700 }}>Evaluación por criterios</h2>
              <span style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
                Promedio de opiniones verificadas
              </span>
            </div>
            <div className="criteria-list">
              {detalle.criterios.map((c) => (
                <CriteriaBar key={c.nombre} label={c.nombre} value={c.promedio} />
              ))}
            </div>
          </div>

          <div className="summary-box">
            <div className="summary-icon">
              <Sparkles size={20} />
            </div>
            <div>
              <h2 style={{ fontSize: 17, fontWeight: 700, marginBottom: 6 }}>En pocas palabras</h2>
              <p style={{ margin: '0 0 12px', color: 'var(--ink-primary)' }}>
                {detalle.resumen ||
                  'Las reseñas verificadas destacan la claridad de su metodología y estructura del curso.'}
              </p>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                {detalle.etiquetas.map((tag) => (
                  <span key={tag} className="pill-tag pill-tag-white">
                    {tag}
                  </span>
                ))}
              </div>
            </div>
          </div>

          <div>
            <div className="section-header" style={{ marginBottom: 12 }}>
              <h2 style={{ fontSize: 20, fontWeight: 700 }}>Reseñas verificadas</h2>
              <span style={{ fontSize: 13, color: 'var(--brand-blue)', fontWeight: 500 }}>
                {resenas.length} {resenas.length === 1 ? 'reseña publicada' : 'reseñas publicadas'}
              </span>
            </div>

            {resenas.length === 0 ? (
              <div className="card card-pad" style={{ textAlign: 'center', padding: 32 }}>
                <p style={{ margin: '0 0 12px', color: 'var(--ink-muted)' }}>
                  Aún no hay reseñas aprobadas para este docente. ¡Sé el primero en orientar a otros
                  estudiantes!
                </p>
                <button type="button" className="btn btn-primary btn-sm" onClick={handleOpenReview}>
                  Escribir la primera reseña
                </button>
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {resenas.map((r) => (
                  <article key={r.id} className="card review-card">
                    <div className="review-top">
                      <div className="review-author">
                        <div className="avatar avatar-sm">{r.autorIniciales || 'EU'}</div>
                        <div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            <strong style={{ fontSize: 13.5 }}>Estudiante verificado</strong>
                            <BadgeCheck size={15} color="#2b5c8f" />
                            <span className="pill-verified" style={{ padding: '2px 8px', fontSize: 11 }}>
                              Correo institucional
                            </span>
                          </div>
                        </div>
                      </div>
                      <span style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
                        {formatRelativeDate(r.fecha)}
                      </span>
                    </div>

                    <div
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: 10,
                        marginBottom: 10,
                        flexWrap: 'wrap',
                      }}
                    >
                      <span className="rating-chip">
                        <Star size={13} fill="#d97706" color="#d97706" />
                        <span>{r.calificacion.toFixed(1)}</span>
                      </span>
                      <RatingStars value={r.calificacion} size={14} />
                      <span style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>
                        {r.cursoNombre}
                      </span>
                    </div>

                    <p style={{ margin: '0 0 12px', color: 'var(--ink-secondary)' }}>
                      {r.comentario}
                    </p>

                    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                      <span className={getDifficultyBadgeClass(r.dificultad)}>
                        Dificultad: {r.dificultad.charAt(0) + r.dificultad.slice(1).toLowerCase()}
                      </span>
                      <span className="pill-tag">Dominio {r.dominio}/5</span>
                      <span className="pill-tag" style={{ background: 'var(--bg-muted)' }}>
                        Claridad {r.claridad}/5
                      </span>
                      <span className="pill-tag" style={{ background: 'var(--bg-muted)' }}>
                        Empatía {r.empatia}/5
                      </span>
                    </div>
                  </article>
                ))}
              </div>
            )}
          </div>
        </div>

        <aside className="card card-pad">
          <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 12 }}>Información del curso</h3>

          <div style={{ marginBottom: 10 }}>
            <div style={{ fontSize: 12, color: 'var(--ink-muted)', marginBottom: 6 }}>
              Cursos con reseñas
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {detalle.cursos.map((c) => (
                <div key={c.id} style={{ fontWeight: 600, fontSize: 13.5 }}>
                  {c.codigo} · {c.nombre}
                </div>
              ))}
            </div>
          </div>

          <div className="divider" />

          <div className="info-kv">
            <span style={{ color: 'var(--ink-muted)', fontSize: 13 }}>Nivel de dificultad</span>
            <span className={getDifficultyBadgeClass(detalle.nivelDificultad)}>
              {detalle.nivelDificultad}
            </span>
          </div>

          <div className="info-kv">
            <span style={{ color: 'var(--ink-muted)', fontSize: 13 }}>Estilo de enseñanza</span>
            <span style={{ fontWeight: 600, fontSize: 13 }}>{detalle.estiloEnsenanza}</span>
          </div>

          <div className="info-kv">
            <span style={{ color: 'var(--ink-muted)', fontSize: 13 }}>Estilo de evaluación</span>
            <span style={{ fontWeight: 600, fontSize: 13, textAlign: 'right' }}>
              {detalle.estiloEvaluacion}
            </span>
          </div>

          <div className="trust-note" style={{ marginTop: 14 }}>
            <ShieldCheck size={18} color="#065f46" style={{ flexShrink: 0, marginTop: 2 }} />
            <span>
              Las opiniones provienen de estudiantes verificados que cursaron con este docente.
            </span>
          </div>
        </aside>
      </section>

      {modalOpen && (
        <ReviewModal
          docenteId={detalle.id}
          docenteNombre={detalle.nombre}
          cursos={detalle.cursos}
          onClose={() => setModalOpen(false)}
          onSuccess={loadData}
        />
      )}
    </div>
  );
}
