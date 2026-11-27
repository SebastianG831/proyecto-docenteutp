import { Link, useNavigate } from 'react-router-dom';
import { ArrowRight, BadgeCheck, Bookmark, Clock, Star, ThumbsUp } from 'lucide-react';
import type { Docente } from '../types/api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import { getDifficultyBadgeClass, getInitials } from '../utils/formatters';

interface TeacherCardProps {
  docente: Docente;
  variantIndex?: number;
}

export function TeacherCard({ docente, variantIndex = 0 }: TeacherCardProps) {
  const { user, savedIds, toggleSaved } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();
  const isSaved = savedIds.has(docente.id);

  const handleSave = async (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (!user) {
      showToast('Inicia sesión con tu correo @utp.edu.pe para guardar docentes', 'info');
      navigate('/login');
      return;
    }
    try {
      const savedNow = await toggleSaved(docente.id);
      showToast(
        savedNow ? `${docente.nombre} guardado en tu lista` : `${docente.nombre} quitado de guardados`,
        'success'
      );
    } catch (err) {
      showToast((err as Error).message, 'error');
    }
  };

  return (
    <Link to={`/docentes/${docente.id}`} className="card teacher-card">
      <div className="teacher-card-left">
        <div className={`avatar avatar-md ${variantIndex % 2 === 1 ? 'avatar-sage' : ''}`}>
          {getInitials(docente.nombre)}
        </div>
        <div className="teacher-card-meta">
          <div className="teacher-name-row">
            <span className="teacher-name">{docente.nombre}</span>
            {docente.verificado && (
              <span className="pill-verified-blue">
                <BadgeCheck size={16} />
                <span>Verificado</span>
              </span>
            )}
            {docente.perfilMl && (
              <span className="pill-tag" style={{ padding: '2px 9px', fontSize: 11 }}>
                {docente.perfilMl}
              </span>
            )}
          </div>
          <div className="teacher-sub">
            {docente.facultad} · <strong>{docente.cursoPrincipal}</strong>
            {docente.sede ? ` · ${docente.sede.split('·')[0].trim()}` : ''}
          </div>
          <div className="teacher-metrics">
            <span className="rating-chip">
              <Star size={14} fill="#d97706" color="#d97706" />
              <span>{docente.calificacion > 0 ? docente.calificacion.toFixed(1) : 'Nuevo'}</span>
            </span>
            <span style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>
              · {docente.totalResenas}{' '}
              {docente.totalResenas === 1 ? 'reseña verificada' : 'reseñas verificadas'}
            </span>
            {docente.nivelDificultad && docente.nivelDificultad !== 'Sin datos' && (
              <span className={getDifficultyBadgeClass(docente.nivelDificultad)}>
                Nivel {docente.nivelDificultad}
              </span>
            )}
            {docente.avgHorasEstudio != null && docente.avgHorasEstudio > 0 && (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--ink-muted)' }}>
                <Clock size={12} /> {docente.avgHorasEstudio} h/s
              </span>
            )}
            {docente.tasaRecomendacion != null && docente.totalResenas > 0 && (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 12, color: '#065f46', fontWeight: 600 }}>
                <ThumbsUp size={12} /> {docente.tasaRecomendacion}%
              </span>
            )}
          </div>
        </div>
      </div>

      <div className="teacher-card-right">
        <span className="pill-tag">{docente.estiloEnsenanza}</span>
        <button
          type="button"
          className="btn btn-outline btn-icon"
          onClick={handleSave}
          title={isSaved ? 'Quitar de guardados' : 'Guardar docente'}
          aria-label={isSaved ? 'Quitar de guardados' : 'Guardar docente'}
          style={isSaved ? { borderColor: 'var(--brand-blue)', color: 'var(--brand-blue)' } : undefined}
        >
          <Bookmark size={16} fill={isSaved ? 'currentColor' : 'none'} />
        </button>
        <ArrowRight size={18} color="#64748b" />
      </div>
    </Link>
  );
}
