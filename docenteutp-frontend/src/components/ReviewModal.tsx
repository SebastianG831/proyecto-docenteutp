import { useState, type FormEvent } from 'react';
import { ChevronDown, ChevronUp, Info, Send, ShieldCheck, X } from 'lucide-react';
import type { Curso, NivelDificultad } from '../types/api';
import { resenasApi } from '../services/api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import { RatingStars } from './RatingStars';

interface ReviewModalProps {
  docenteId: number;
  docenteNombre: string;
  cursos: Curso[];
  onClose: () => void;
  onSuccess: () => void;
}

export function ReviewModal({
  docenteId,
  docenteNombre,
  cursos,
  onClose,
  onSuccess,
}: ReviewModalProps) {
  const { user } = useAuth();
  const { showToast } = useToast();

  const [cursoId, setCursoId] = useState<number>(cursos[0]?.id || 0);
  const [dominio, setDominio] = useState(4);
  const [claridad, setClaridad] = useState(5);
  const [empatia, setEmpatia] = useState(4);
  const [retroalimentacion, setRetroalimentacion] = useState(4);
  const [organizacion, setOrganizacion] = useState(4);
  const [puntualidad, setPuntualidad] = useState(4);
  const [dificultad, setDificultad] = useState<NivelDificultad>('MODERADO');
  const [horasEstudioSemanal, setHorasEstudioSemanal] = useState<number>(4);
  const [recomienda, setRecomienda] = useState<boolean>(true);
  const [notaObtenida, setNotaObtenida] = useState<string>('');
  const [showExtra, setShowExtra] = useState(false);
  const [comentario, setComentario] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!user) return;
    if (!cursoId) {
      setError('Selecciona un curso.');
      return;
    }
    const trimmed = comentario.trim();
    if (trimmed.length < 30) {
      setError('Tu comentario debe tener al menos 30 caracteres.');
      return;
    }

    setError('');
    setSubmitting(true);
    try {
      await resenasApi.publicar({
        usuarioId: user.id,
        docenteId,
        cursoId,
        dominio,
        claridad,
        empatia,
        retroalimentacion,
        organizacion,
        puntualidad,
        dificultad,
        horasEstudioSemanal,
        recomienda,
        notaObtenida: notaObtenida !== '' ? Number(notaObtenida) : null,
        comentario: trimmed,
      });
      showToast('Reseña enviada a moderación. ¡Gracias por aportar a la comunidad UTP!', 'success');
      onSuccess();
      onClose();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="modal-resena-title">
      <div className="modal-card">
        <div className="modal-header">
          <div>
            <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--brand-blue)', marginBottom: 4 }}>
              Tu experiencia cuenta
            </div>
            <h2 id="modal-resena-title" style={{ fontSize: 24, fontWeight: 700 }}>
              Escribe una reseña
            </h2>
            <div style={{ fontSize: 13, color: 'var(--ink-muted)', marginTop: 2 }}>
              {docenteNombre}
              {cursos.find((c) => c.id === cursoId)
                ? ` · ${cursos.find((c) => c.id === cursoId)?.nombre}`
                : ''}
            </div>
          </div>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Cerrar">
            <X size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          {cursos.length > 0 && (
            <div className="form-group">
              <label className="form-label" htmlFor="resena-curso">
                Curso cursado
              </label>
              <select
                id="resena-curso"
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
          )}

          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: 12,
              marginBottom: 16,
              padding: '12px 14px',
              background: 'var(--bg-canvas)',
              borderRadius: 'var(--radius-md)',
              border: '1px solid var(--border)',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontWeight: 600 }}>Dominio del tema</span>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <RatingStars value={dominio} size={22} interactive onChange={setDominio} />
                <span style={{ fontSize: 12, color: 'var(--ink-muted)', width: 32 }}>{dominio} / 5</span>
              </div>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontWeight: 600 }}>Claridad de explicación</span>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <RatingStars value={claridad} size={22} interactive onChange={setClaridad} />
                <span style={{ fontSize: 12, color: 'var(--ink-muted)', width: 32 }}>{claridad} / 5</span>
              </div>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontWeight: 600 }}>Empatía y accesibilidad</span>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <RatingStars value={empatia} size={22} interactive onChange={setEmpatia} />
                <span style={{ fontSize: 12, color: 'var(--ink-muted)', width: 32 }}>{empatia} / 5</span>
              </div>
            </div>
          </div>

          <div className="form-group">
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
              <label className="form-label" htmlFor="resena-comentario" style={{ marginBottom: 0 }}>
                Tu comentario
              </label>
              <span style={{ fontSize: 12, color: 'var(--ink-muted)' }}>Mínimo 30 caracteres</span>
            </div>
            <textarea
              id="resena-comentario"
              className="form-control"
              rows={3}
              maxLength={500}
              placeholder="Comparte detalles útiles sobre la metodología, la evaluación o la dinámica de clase..."
              value={comentario}
              onChange={(e) => setComentario(e.target.value)}
            />
            <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--ink-muted)', marginTop: 4 }}>
              {comentario.length} / 500 caracteres
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 140px', gap: 12, marginBottom: 14 }}>
            <div>
              <span className="form-label">Nivel de dificultad</span>
              <div className="diff-grid">
                {(['LIGERO', 'MODERADO', 'EXIGENTE'] as NivelDificultad[]).map((lvl) => (
                  <button
                    key={lvl}
                    type="button"
                    className={`diff-option ${dificultad === lvl ? 'selected' : ''}`}
                    onClick={() => setDificultad(lvl)}
                  >
                    {lvl === 'LIGERO' ? 'Ligero' : lvl === 'MODERADO' ? 'Moderado' : 'Exigente'}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="form-label" htmlFor="resena-horas">
                Horas/sem
              </label>
              <input
                id="resena-horas"
                type="number"
                min={0}
                max={40}
                step={0.5}
                className="form-control"
                value={horasEstudioSemanal}
                onChange={(e) => setHorasEstudioSemanal(Number(e.target.value))}
              />
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14, flexWrap: 'wrap', gap: 8 }}>
            <label style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>
              <input
                type="checkbox"
                checked={recomienda}
                onChange={(e) => setRecomienda(e.target.checked)}
              />
              <span>¿Recomendarías matricularte con este docente?</span>
            </label>

            <button
              type="button"
              className="btn btn-outline btn-sm"
              onClick={() => setShowExtra((v) => !v)}
            >
              {showExtra ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
              <span>Criterios opcionales</span>
            </button>
          </div>

          {showExtra && (
            <div
              style={{
                padding: '12px 14px',
                background: 'var(--bg-canvas)',
                borderRadius: 'var(--radius-md)',
                border: '1px solid var(--border)',
                marginBottom: 14,
                display: 'flex',
                flexDirection: 'column',
                gap: 10,
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>Retroalimentación</span>
                <RatingStars value={retroalimentacion} size={18} interactive onChange={setRetroalimentacion} />
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>Organización de sesiones</span>
                <RatingStars value={organizacion} size={18} interactive onChange={setOrganizacion} />
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>Puntualidad</span>
                <RatingStars value={puntualidad} size={18} interactive onChange={setPuntualidad} />
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>Nota final obtenida (opcional, 0-20)</span>
                <input
                  type="number"
                  min={0}
                  max={20}
                  step={0.5}
                  placeholder="Ej. 16"
                  className="form-control"
                  style={{ width: 95, padding: '6px 10px' }}
                  value={notaObtenida}
                  onChange={(e) => setNotaObtenida(e.target.value)}
                />
              </div>
            </div>
          )}

          <div className="trust-note" style={{ marginBottom: 16 }}>
            <ShieldCheck size={20} color="#2b5c8f" style={{ flexShrink: 0, marginTop: 2 }} />
            <div>
              <div style={{ fontWeight: 600, fontSize: 13 }}>
                Publicar bajo mi código de estudiante UTP verificado
              </div>
              <div style={{ color: 'var(--ink-muted)', marginTop: 2 }}>
                Tu reseña será visible sin mostrar información personal.
              </div>
            </div>
          </div>

          {error && (
            <div
              style={{
                background: 'var(--danger-bg)',
                color: 'var(--danger)',
                padding: '10px 12px',
                borderRadius: 'var(--radius-sm)',
                fontSize: 13,
                marginBottom: 14,
              }}
            >
              {error}
            </div>
          )}

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
            <button type="button" className="btn btn-outline" onClick={onClose}>
              Cancelar
            </button>
            <button type="submit" className="btn btn-primary" disabled={submitting}>
              <Send size={15} />
              <span>{submitting ? 'Enviando...' : 'Publicar Reseña'}</span>
            </button>
          </div>

          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              fontSize: 11.5,
              color: 'var(--ink-muted)',
              marginTop: 14,
            }}
          >
            <Info size={14} />
            <span>Las reseñas se revisan para mantener una comunidad respetuosa y útil.</span>
          </div>
        </form>
      </div>
    </div>
  );
}
