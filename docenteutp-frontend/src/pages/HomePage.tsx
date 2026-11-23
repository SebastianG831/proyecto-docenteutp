import { useEffect, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import {
  CheckCircle2,
  MapPin,
  Scale,
  Search,
  ShieldCheck,
  SlidersHorizontal,
} from 'lucide-react';
import { docentesApi } from '../services/api';
import type { Docente } from '../types/api';
import { TeacherCard } from '../components/TeacherCard';

const ESTILOS = [
  { label: 'Metodología clara', value: 'Explicación clara' },
  { label: 'Alto nivel de exigencia', value: 'Alto nivel de exigencia' },
  { label: 'Evaluación continua', value: 'Evaluación continua' },
  { label: 'Explicación dinámica', value: 'Explicación dinámica' },
];

const DIFICULTADES = [
  { label: 'Ligero', value: 'LIGERO' },
  { label: 'Moderado', value: 'MODERADO' },
  { label: 'Exigente', value: 'EXIGENTE' },
];

export function HomePage() {
  const [queryText, setQueryText] = useState('');
  const [appliedQuery, setAppliedQuery] = useState('');
  const [estilo, setEstilo] = useState('');
  const [dificultad, setDificultad] = useState('');
  const [sort, setSort] = useState('relevantes');
  const [docentes, setDocentes] = useState<Docente[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    docentesApi
      .buscar({ q: appliedQuery, estilo, dificultad, sort })
      .then((data) => {
        if (active) setDocentes(data);
      })
      .catch((err) => {
        if (active) setError((err as Error).message);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [appliedQuery, estilo, dificultad, sort]);

  const handleSearch = (e: FormEvent) => {
    e.preventDefault();
    setAppliedQuery(queryText);
  };

  const clearFilters = () => {
    setQueryText('');
    setAppliedQuery('');
    setEstilo('');
    setDificultad('');
  };

  const hasFilters = Boolean(appliedQuery || estilo || dificultad);

  return (
    <div className="container">
      <section className="hero-section">
        <div className="hero-top">
          <div>
            <div className="eyebrow">Matrícula con más claridad · UTP Lima Centro</div>
            <h1 className="hero-title">Encuentra al docente ideal para ti</h1>
            <p className="hero-subtitle">
              Opiniones honestas y evaluaciones estructuradas de estudiantes de UTP Lima Centro,
              Edificio Arequipa.
            </p>
          </div>
          <span className="pill-verified" style={{ padding: '10px 16px', fontSize: 13.5 }}>
            <ShieldCheck size={18} />
            <span>Comunidad verificada UTP</span>
          </span>
        </div>

        <form className="search-bar-card" onSubmit={handleSearch}>
          <div className="search-input-wrap">
            <Search size={20} color="#64748b" />
            <input
              type="text"
              className="search-input"
              placeholder="Busca por nombre de docente, curso o código (ej. SIS-201, MAT-101, Carlos)..."
              value={queryText}
              onChange={(e) => setQueryText(e.target.value)}
            />
          </div>
          <button type="submit" className="btn btn-primary">
            <Search size={16} />
            <span>Buscar</span>
          </button>
        </form>

        <div className="filter-row">
          <span className="filter-label">Explora por:</span>
          {ESTILOS.map((item) => {
            const active = estilo === item.value;
            return (
              <button
                key={item.value}
                type="button"
                className={`filter-chip ${active ? 'active' : ''}`}
                onClick={() => setEstilo(active ? '' : item.value)}
              >
                {item.label}
              </button>
            );
          })}

          <span className="filter-label" style={{ marginLeft: 8 }}>
            Dificultad:
          </span>
          {DIFICULTADES.map((d) => {
            const active = dificultad === d.value;
            return (
              <button
                key={d.value}
                type="button"
                className={`filter-chip ${active ? 'active-sage' : ''}`}
                onClick={() => setDificultad(active ? '' : d.value)}
              >
                {d.label}
              </button>
            );
          })}

          <span className="pill-verified" style={{ marginLeft: 'auto' }}>
            <MapPin size={14} />
            <span>Lima Centro</span>
          </span>
        </div>
      </section>

      <section className="two-col">
        <div>
          <div className="section-header">
            <div>
              <h2 style={{ fontSize: 20, fontWeight: 700 }}>Docentes recomendados</h2>
              <p style={{ margin: '2px 0 0', fontSize: 13, color: 'var(--ink-muted)' }}>
                {loading
                  ? 'Buscando docentes verificados...'
                  : `${docentes.length} ${
                      docentes.length === 1 ? 'coincidencia' : 'coincidencias'
                    } en UTP Lima Centro`}
              </p>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              {hasFilters && (
                <button type="button" className="btn btn-outline btn-sm" onClick={clearFilters}>
                  Limpiar filtros
                </button>
              )}
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 6,
                  background: '#fff',
                  border: '1px solid var(--border)',
                  borderRadius: 'var(--radius-md)',
                  padding: '6px 12px',
                }}
              >
                <SlidersHorizontal size={15} color="#64748b" />
                <select
                  aria-label="Ordenar docentes"
                  value={sort}
                  onChange={(e) => setSort(e.target.value)}
                  style={{
                    border: 'none',
                    outline: 'none',
                    background: 'transparent',
                    fontSize: 13,
                    fontWeight: 500,
                    color: 'var(--ink-primary)',
                    cursor: 'pointer',
                  }}
                >
                  <option value="relevantes">Más relevantes</option>
                  <option value="calificacion">Mejor calificados</option>
                  <option value="resenas">Más reseñas</option>
                  <option value="nombre">Orden alfabético</option>
                </select>
              </div>
            </div>
          </div>

          {error && (
            <div className="card card-pad" style={{ color: 'var(--danger)' }}>
              {error}
            </div>
          )}

          {!loading && !error && docentes.length === 0 && (
            <div className="card card-pad" style={{ textAlign: 'center', padding: '44px 24px' }}>
              <h3 style={{ marginBottom: 6 }}>No encontramos docentes con esos filtros</h3>
              <p style={{ color: 'var(--ink-muted)', marginBottom: 16 }}>
                Prueba con otro código de curso (ej. SIS-201, MAT-101) o limpia los filtros activos.
              </p>
              <button type="button" className="btn btn-primary" onClick={clearFilters}>
                Ver todos los docentes
              </button>
            </div>
          )}

          <div className="teacher-list">
            {docentes.map((doc, idx) => (
              <TeacherCard key={doc.id} docente={doc} variantIndex={idx} />
            ))}
          </div>
        </div>

        <aside style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="card card-pad">
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 'var(--radius-md)',
                background: 'var(--bg-sage)',
                color: 'var(--brand-green)',
                display: 'grid',
                placeItems: 'center',
                marginBottom: 14,
              }}
            >
              <ShieldCheck size={22} />
            </div>
            <h3 style={{ fontSize: 17, fontWeight: 700, marginBottom: 8 }}>
              Opiniones que dan tranquilidad
            </h3>
            <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-muted)' }}>
              Cada reseña está vinculada a un estudiante UTP verificado y a un curso cursado.
            </p>
            <div className="divider" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, fontSize: 13 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <CheckCircle2 size={17} color="#047857" />
                <span>Sin reseñas anónimas</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <CheckCircle2 size={17} color="#047857" />
                <span>Criterios académicos claros</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <CheckCircle2 size={17} color="#047857" />
                <span>Moderación anti-spam activa</span>
              </div>
            </div>
          </div>

          <div className="card card-pad" style={{ background: 'var(--bg-sage)', borderColor: '#d7e5dd' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <Scale size={18} color="#065f46" />
              <h3 style={{ fontSize: 16, fontWeight: 700 }}>Comparador Pre-Matrícula</h3>
            </div>
            <p style={{ margin: '0 0 14px', fontSize: 13, color: 'var(--ink-secondary)' }}>
              ¿Dudas entre dos horarios del mismo curso? Compara metodología, dominio y exigencia lado a
              lado.
            </p>
            <Link to="/comparar" className="btn btn-emerald btn-sm" style={{ width: '100%' }}>
              Comparar docentes por curso
            </Link>
          </div>
        </aside>
      </section>
    </div>
  );
}
