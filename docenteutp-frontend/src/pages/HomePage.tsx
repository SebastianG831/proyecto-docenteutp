import { useEffect, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import {
  CheckCircle2,
  MapPin,
  PieChart,
  Scale,
  Search,
  ShieldCheck,
  SlidersHorizontal,
} from 'lucide-react';
import { docentesApi } from '../services/api';
import type { Docente } from '../types/api';
import { TeacherCard } from '../components/TeacherCard';

const ESTILOS = [
  { label: 'Explicación clara', value: 'Explicación clara' },
  { label: 'Alto nivel de exigencia', value: 'Alto nivel de exigencia' },
  { label: 'Evaluación continua', value: 'Evaluación continua' },
  { label: 'Explicación dinámica', value: 'Explicación dinámica' },
];

const DIFICULTADES = [
  { label: 'Ligero', value: 'LIGERO' },
  { label: 'Moderado', value: 'MODERADO' },
  { label: 'Exigente', value: 'EXIGENTE' },
];

const SEDES = [
  { label: 'Todas las sedes', value: '' },
  { label: 'Lima Centro', value: 'Lima Centro' },
  { label: 'Lima Norte', value: 'Lima Norte' },
  { label: 'Arequipa', value: 'Arequipa' },
];

export function HomePage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const initialPerfil = searchParams.get('perfil') || '';

  const [queryText, setQueryText] = useState('');
  const [appliedQuery, setAppliedQuery] = useState('');
  const [estilo, setEstilo] = useState('');
  const [dificultad, setDificultad] = useState('');
  const [sede, setSede] = useState('');
  const [perfil, setPerfil] = useState(initialPerfil);
  const [sort, setSort] = useState('relevantes');
  const [docentes, setDocentes] = useState<Docente[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    setPerfil(searchParams.get('perfil') || '');
  }, [searchParams]);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError('');
    docentesApi
      .buscar({ q: appliedQuery, estilo, dificultad, sede, perfil, sort })
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
  }, [appliedQuery, estilo, dificultad, sede, perfil, sort]);

  const handleSearch = (e: FormEvent) => {
    e.preventDefault();
    setAppliedQuery(queryText);
  };

  const clearFilters = () => {
    setQueryText('');
    setAppliedQuery('');
    setEstilo('');
    setDificultad('');
    setSede('');
    setPerfil('');
    if (searchParams.has('perfil')) {
      setSearchParams({});
    }
  };

  const hasFilters = Boolean(appliedQuery || estilo || dificultad || sede || perfil);

  return (
    <div className="container">
      <section className="hero-section">
        <div className="hero-top">
          <div>
            <div className="eyebrow">Matrícula con más claridad · UTP</div>
            <h1 className="hero-title">Encuentra al docente ideal para ti</h1>
            <p className="hero-subtitle">
              Opiniones honestas y evaluaciones estructuradas de estudiantes UTP en Lima Centro,
              Lima Norte y Arequipa.
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

          <div
            style={{
              marginLeft: 'auto',
              display: 'inline-flex',
              alignItems: 'center',
              gap: 6,
              background: 'var(--bg-sage)',
              color: 'var(--brand-green-ink)',
              padding: '5px 12px',
              borderRadius: 'var(--radius-pill)',
              fontSize: 12,
              fontWeight: 600,
            }}
          >
            <MapPin size={14} />
            <select
              aria-label="Filtrar por sede"
              value={sede}
              onChange={(e) => setSede(e.target.value)}
              style={{
                border: 'none',
                background: 'transparent',
                color: 'inherit',
                fontWeight: 600,
                fontSize: 12,
                outline: 'none',
                cursor: 'pointer',
              }}
            >
              {SEDES.map((s) => (
                <option key={s.label} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        {perfil && (
          <div style={{ marginTop: 12, display: 'flex', alignItems: 'center', gap: 10 }}>
            <span className="pill-verified">Perfil ML activo: {perfil}</span>
            <button
              type="button"
              className="btn btn-outline btn-sm"
              onClick={() => {
                setPerfil('');
                setSearchParams({});
              }}
            >
              Quitar perfil
            </button>
          </div>
        )}
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
                    } en UTP`}
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
                <span>Detección anti-spam con DBSCAN</span>
              </div>
            </div>
          </div>

          <div className="card card-pad" style={{ background: '#f0f6fc', borderColor: '#d0e2f5' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <PieChart size={18} color="#2b5c8f" />
              <h3 style={{ fontSize: 16, fontWeight: 700 }}>Estadísticas y Perfiles UTP</h3>
            </div>
            <p style={{ margin: '0 0 14px', fontSize: 13, color: 'var(--ink-secondary)' }}>
              Explora los 4 perfiles docentes, carga de estudio semanal por curso y tendencias
              reales de la comunidad.
            </p>
            <Link to="/estadisticas" className="btn btn-primary btn-sm" style={{ width: '100%' }}>
              Ver estadísticas académicas
            </Link>
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
