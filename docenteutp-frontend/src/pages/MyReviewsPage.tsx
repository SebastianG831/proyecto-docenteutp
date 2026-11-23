import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { MessageSquare, Star, Trash2 } from 'lucide-react';
import { resenasApi } from '../services/api';
import type { Resena } from '../types/api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import { formatRelativeDate, getDifficultyBadgeClass } from '../utils/formatters';

export function MyReviewsPage() {
  const { user } = useAuth();
  const { showToast } = useToast();
  const [resenas, setResenas] = useState<Resena[]>([]);
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!user) {
      setLoading(false);
      return;
    }
    setLoading(true);
    resenasApi
      .porUsuario(user.id)
      .then(setResenas)
      .finally(() => setLoading(false));
  };

  useEffect(load, [user?.id]);

  const handleDelete = async (id: number) => {
    if (!user) return;
    try {
      await resenasApi.eliminar(id, user.id);
      setResenas((prev) => prev.filter((r) => r.id !== id));
      showToast('Reseña eliminada', 'success');
    } catch (err) {
      showToast((err as Error).message, 'error');
    }
  };

  if (!user) {
    return (
      <div className="container" style={{ padding: '48px 24px' }}>
        <div className="card card-pad" style={{ textAlign: 'center', padding: 40 }}>
          <MessageSquare size={32} color="#2b5c8f" style={{ marginBottom: 12 }} />
          <h1 style={{ fontSize: 24, marginBottom: 8 }}>Inicia sesión para ver tus reseñas</h1>
          <p style={{ color: 'var(--ink-muted)', marginBottom: 18 }}>
            Accede con tu correo institucional <code>@utp.edu.pe</code> para gestionar tus
            evaluaciones enviadas.
          </p>
          <Link to="/login" className="btn btn-primary">
            Iniciar sesión
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="container" style={{ padding: '36px 24px 56px' }}>
      <div className="section-header">
        <div>
          <h1 style={{ fontSize: 28, fontWeight: 700 }}>Mis reseñas</h1>
          <p style={{ color: 'var(--ink-muted)', margin: '4px 0 0' }}>
            Historial de evaluaciones enviadas con tu cuenta verificada ({user.correo}).
          </p>
        </div>
        <Link to="/" className="btn btn-outline">
          Explorar docentes
        </Link>
      </div>

      {loading ? (
        <div className="card card-pad">Cargando tus reseñas...</div>
      ) : resenas.length === 0 ? (
        <div className="card card-pad" style={{ textAlign: 'center', padding: 40 }}>
          <h3 style={{ marginBottom: 6 }}>Aún no has publicado reseñas</h3>
          <p style={{ color: 'var(--ink-muted)', marginBottom: 16 }}>
            Busca a un docente de tu ciclo anterior y comparte tu experiencia.
          </p>
          <Link to="/" className="btn btn-primary">
            Buscar docentes
          </Link>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          {resenas.map((r) => (
            <article key={r.id} className="card review-card">
              <div className="review-top">
                <div>
                  <Link
                    to={`/docentes/${r.docenteId}`}
                    style={{ fontSize: 17, fontWeight: 700, color: 'var(--brand-blue)' }}
                  >
                    {r.docenteNombre}
                  </Link>
                  <div style={{ fontSize: 13, color: 'var(--ink-muted)' }}>
                    {r.cursoNombre} · {formatRelativeDate(r.fecha)}
                  </div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <span className={`status-badge status-${r.estado}`}>{r.estado}</span>
                  <button
                    type="button"
                    className="btn btn-danger-soft btn-sm"
                    onClick={() => handleDelete(r.id)}
                  >
                    <Trash2 size={14} />
                    <span>Eliminar</span>
                  </button>
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
                <span className="rating-chip">
                  <Star size={13} fill="#d97706" color="#d97706" />
                  <span>{r.calificacion.toFixed(1)}</span>
                </span>
                <span className={getDifficultyBadgeClass(r.dificultad)}>{r.dificultad}</span>
                <span style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>
                  Dominio {r.dominio}/5 · Claridad {r.claridad}/5 · Empatía {r.empatia}/5
                </span>
              </div>

              <p style={{ margin: 0, color: 'var(--ink-secondary)' }}>{r.comentario}</p>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
