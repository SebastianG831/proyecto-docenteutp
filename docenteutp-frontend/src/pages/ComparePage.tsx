import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, BadgeCheck, Scale, Star } from 'lucide-react';
import { cursosApi, docentesApi } from '../services/api';
import type { Curso, DocenteDetalle } from '../types/api';
import { CriteriaBar } from '../components/CriteriaBar';
import { getDifficultyBadgeClass, getInitials } from '../utils/formatters';

export function ComparePage() {
  const [cursos, setCursos] = useState<Curso[]>([]);
  const [selectedCursoId, setSelectedCursoId] = useState<number>(0);
  const [detalles, setDetalles] = useState<DocenteDetalle[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    cursosApi.listar().then((data) => {
      setCursos(data);
      if (data.length > 0) setSelectedCursoId(data[0].id);
    });
  }, []);

  useEffect(() => {
    if (!selectedCursoId) return;
    setLoading(true);
    cursosApi
      .docentesDelCurso(selectedCursoId)
      .then((docs) => Promise.all(docs.map((d) => docentesApi.obtenerDetalle(d.id))))
      .then(setDetalles)
      .finally(() => setLoading(false));
  }, [selectedCursoId]);

  return (
    <div className="container" style={{ padding: '36px 24px 56px' }}>
      <div className="hero-top" style={{ marginBottom: 22 }}>
        <div>
          <div className="eyebrow" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <Scale size={15} />
            <span>Comparación Estructurada Pre-Matrícula</span>
          </div>
          <h1 className="hero-title" style={{ fontSize: 30 }}>
            Comparar docentes por curso
          </h1>
          <p className="hero-subtitle">
            Elige un curso y contrasta dominio, claridad, empatía y nivel de exigencia antes de
            matricularte.
          </p>
        </div>
      </div>

      <div className="card card-pad" style={{ marginBottom: 24 }}>
        <div className="filter-row" style={{ marginTop: 0 }}>
          <span className="filter-label">Curso:</span>
          {cursos.map((c) => (
            <button
              key={c.id}
              type="button"
              className={`filter-chip ${selectedCursoId === c.id ? 'active' : ''}`}
              onClick={() => setSelectedCursoId(c.id)}
            >
              {c.codigo} · {c.nombre}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="card card-pad">Cargando comparativa de docentes...</div>
      ) : detalles.length === 0 ? (
        <div className="card card-pad">No hay docentes registrados para este curso.</div>
      ) : (
        <div className="compare-grid">
          {detalles.map((d, idx) => (
            <div key={d.id} className="card card-pad" style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                <div className={`avatar avatar-md ${idx % 2 === 1 ? 'avatar-sage' : ''}`}>
                  {getInitials(d.nombre)}
                </div>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <h2 style={{ fontSize: 18, fontWeight: 700 }}>{d.nombre}</h2>
                    {d.verificado && <BadgeCheck size={16} color="#2b5c8f" />}
                  </div>
                  <div style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>{d.facultad}</div>
                </div>
              </div>

              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  background: 'var(--bg-canvas)',
                  padding: '12px 14px',
                  borderRadius: 'var(--radius-md)',
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span className="rating-chip" style={{ fontSize: 15, padding: '6px 12px' }}>
                    <Star size={15} fill="#d97706" color="#d97706" />
                    <span>{d.calificacion.toFixed(1)}</span>
                  </span>
                  <span style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>
                    {d.totalResenas} reseñas
                  </span>
                </div>
                <span className={getDifficultyBadgeClass(d.nivelDificultad)}>
                  {d.nivelDificultad}
                </span>
              </div>

              <div className="criteria-list">
                {d.criterios.map((c) => (
                  <CriteriaBar key={c.nombre} label={c.nombre} value={c.promedio} />
                ))}
              </div>

              <div style={{ fontSize: 13, color: 'var(--ink-secondary)' }}>
                <div>
                  <strong>Enseñanza:</strong> {d.estiloEnsenanza}
                </div>
                <div style={{ marginTop: 4 }}>
                  <strong>Evaluación:</strong> {d.estiloEvaluacion}
                </div>
              </div>

              <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-muted)', flex: 1 }}>
                {d.resumen}
              </p>

              <Link to={`/docentes/${d.id}`} className="btn btn-primary btn-sm">
                <span>Ver perfil y reseñas</span>
                <ArrowRight size={15} />
              </Link>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
