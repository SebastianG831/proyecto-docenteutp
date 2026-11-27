import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  AlertTriangle,
  ArrowRight,
  Award,
  BookOpen,
  Building2,
  Calendar,
  Clock,
  GraduationCap,
  Layers,
  ShieldCheck,
  Sparkles,
  Star,
  ThumbsUp,
  Users,
} from 'lucide-react';
import { estadisticasApi } from '../services/api';
import type { EstadisticasResponse, MapaDocentePoint, PerfilDocenteGrupo } from '../types/api';

type ModeloKey = 'kmeans' | 'meanshift';
type ScatterMode = 'calificacion_horas' | 'claridad_empatia';

const PROFILE_PALETTE = [
  { color: '#065f46', bg: '#e8f0ec', border: '#b7d7c7' }, // Excelencia
  { color: '#2b5c8f', bg: '#e6f0fa', border: '#bfdbfe' }, // Accesibles
  { color: '#b45309', bg: '#fef3c7', border: '#fde68a' }, // Exigentes
  { color: '#dc2626', bg: '#fef2f2', border: '#fecaca' }, // Riesgo
  { color: '#7c3aed', bg: '#f3e8ff', border: '#ddd6fe' }, // Polarizado
  { color: '#0f766e', bg: '#ccfbf1', border: '#99f6e4' }, // Carga Extrema
];

function getProfileStyle(nombre: string, fallbackIndex = 0) {
  const n = nombre.toLowerCase();
  if (n.includes('excelencia')) return PROFILE_PALETTE[0];
  if (n.includes('accesible')) return PROFILE_PALETTE[1];
  if (n.includes('carga extrema')) return PROFILE_PALETTE[5];
  if (n.includes('exigente')) return PROFILE_PALETTE[2];
  if (n.includes('riesgo')) return PROFILE_PALETTE[3];
  if (n.includes('polariz') || n.includes('dividid')) return PROFILE_PALETTE[4];
  return PROFILE_PALETTE[fallbackIndex % PROFILE_PALETTE.length];
}

export function StatisticsPage() {
  const [data, setData] = useState<EstadisticasResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [modelo, setModelo] = useState<ModeloKey>('kmeans');
  const [selectedCluster, setSelectedCluster] = useState<number | null>(null);
  const [scatterMode, setScatterMode] = useState<ScatterMode>('calificacion_horas');
  const [hoveredDoc, setHoveredDoc] = useState<MapaDocentePoint | null>(null);

  useEffect(() => {
    setLoading(true);
    estadisticasApi
      .obtener()
      .then((res) => {
        setData(res);
      })
      .catch((err) => setError((err as Error).message))
      .finally(() => setLoading(false));
  }, []);

  const activeModel = useMemo(() => {
    if (!data) return null;
    return modelo === 'kmeans' ? data.perfilesDocentes.kmeans : data.perfilesDocentes.meanshift;
  }, [data, modelo]);

  useEffect(() => {
    if (activeModel && activeModel.grupos.length > 0) {
      setSelectedCluster(activeModel.grupos[0].clusterLabel);
    } else {
      setSelectedCluster(null);
    }
  }, [modelo, activeModel?.experimentoId]);

  const activeGroup: PerfilDocenteGrupo | null = useMemo(() => {
    if (!activeModel || selectedCluster === null) return null;
    return activeModel.grupos.find((g) => g.clusterLabel === selectedCluster) || activeModel.grupos[0] || null;
  }, [activeModel, selectedCluster]);

  if (loading) {
    return (
      <div className="container" style={{ padding: '48px 24px' }}>
        <div className="card card-pad">Cargando estadísticas e indicadores académicos de UTP...</div>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="container" style={{ padding: '48px 24px' }}>
        <div className="card card-pad" style={{ color: 'var(--danger)' }}>
          {error || 'No se pudieron cargar las estadísticas.'}
        </div>
      </div>
    );
  }

  const { resumen, mapaDocentes, distribuciones, perfilesEstudiantes, alertasCalidad } = data;

  // Scatter dimensions
  const svgW = 680;
  const svgH = 340;
  const padL = 54;
  const padR = 24;
  const padT = 22;
  const padB = 46;
  const plotW = svgW - padL - padR;
  const plotH = svgH - padT - padB;

  const maxHoras = Math.max(26, ...mapaDocentes.map((d) => d.avgHorasEstudio + 2));

  const getCoords = (d: MapaDocentePoint) => {
    if (scatterMode === 'calificacion_horas') {
      const x = padL + (Math.min(maxHoras, Math.max(0, d.avgHorasEstudio)) / maxHoras) * plotW;
      const y = padT + (1 - (Math.min(5, Math.max(1, d.calificacion)) - 1) / 4) * plotH;
      return { x, y };
    }
    const x = padL + ((Math.min(5, Math.max(1, d.avgClaridad)) - 1) / 4) * plotW;
    const y = padT + (1 - (Math.min(5, Math.max(1, d.avgEmpatia)) - 1) / 4) * plotH;
    return { x, y };
  };

  return (
    <div className="container" style={{ padding: '36px 24px 64px' }}>
      {/* Header */}
      <div className="hero-top" style={{ marginBottom: 24 }}>
        <div>
          <div className="eyebrow" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <Sparkles size={15} />
            <span>Inteligencia Académica UTP · Datos reales para decidir mejor</span>
          </div>
          <h1 className="hero-title" style={{ fontSize: 32 }}>
            Estadísticas y Perfiles Docentes
          </h1>
          <p className="hero-subtitle" style={{ maxWidth: 740 }}>
            Convertimos las {resumen.totalResenasAprobadas} reseñas verificadas de estudiantes UTP en
            indicadores claros para elegir horario según tu ritmo, exigencia y forma de aprender.
          </p>
        </div>
        <Link to="/comparar" className="btn btn-primary btn-sm">
          <span>Comparar por curso</span>
          <ArrowRight size={15} />
        </Link>
      </div>

      {/* KPI Strip */}
      <div className="kpi-grid">
        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Docentes evaluados</span>
            <GraduationCap size={18} color="#2b5c8f" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>{resumen.totalDocentes}</div>
          <div style={{ fontSize: 12, color: 'var(--ink-muted)', marginTop: 4 }}>
            En {resumen.totalCursos} cursos y {resumen.totalSedes} sedes UTP
          </div>
        </div>

        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Calificación promedio</span>
            <Star size={18} color="#d97706" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>
            {resumen.promedioGeneral.toFixed(2)} / 5
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-muted)', marginTop: 4 }}>
            Sobre {resumen.totalResenasAprobadas} reseñas verificadas
          </div>
        </div>

        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Tasa de recomendación</span>
            <ThumbsUp size={18} color="#065f46" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>
            {resumen.tasaRecomendacionGlobal}%
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-muted)', marginTop: 4 }}>
            Volvería a llevar con el mismo docente
          </div>
        </div>

        <div className="card card-pad">
          <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--ink-muted)' }}>
            <span>Dedicación semanal</span>
            <Clock size={18} color="#2b5c8f" />
          </div>
          <div style={{ fontSize: 28, fontWeight: 700, marginTop: 8 }}>
            {resumen.avgHorasEstudioGlobal} h/sem
          </div>
          <div style={{ fontSize: 12, color: 'var(--ink-muted)', marginTop: 4 }}>
            Nota promedio reportada: {resumen.avgNotaReportada} / 20
          </div>
        </div>
      </div>

      {/* Section 1: Perfiles Docentes (K-Means + Mean Shift) */}
      {activeModel && (
        <section style={{ marginBottom: 28 }}>
          <div className="section-header" style={{ marginBottom: 14 }}>
            <div>
              <h2 style={{ fontSize: 22, fontWeight: 700 }}>
                ¿Qué tipo de docente estás buscando?
              </h2>
              <p style={{ margin: '4px 0 0', fontSize: 13.5, color: 'var(--ink-muted)' }}>
                Agrupación automática por desempeño, claridad, empatía, carga de estudio y recomendación
                {activeModel.calidadSeparacionPct
                  ? ` · ${activeModel.interpretacionCalidad} (${activeModel.calidadSeparacionPct}%)`
                  : ''}
              </p>
            </div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <button
                type="button"
                className={`filter-chip ${modelo === 'kmeans' ? 'active' : ''}`}
                onClick={() => setModelo('kmeans')}
              >
                4 Perfiles Principales (K-Means)
              </button>
              <button
                type="button"
                className={`filter-chip ${modelo === 'meanshift' ? 'active' : ''}`}
                onClick={() => setModelo('meanshift')}
              >
                6 Modos Específicos (Mean Shift)
              </button>
            </div>
          </div>

          <div className="stats-profile-grid">
            {activeModel.grupos.map((g, idx) => {
              const st = getProfileStyle(g.nombre, idx);
              const isSelected = activeGroup?.clusterLabel === g.clusterLabel;
              return (
                <button
                  key={g.clusterLabel}
                  type="button"
                  onClick={() => setSelectedCluster(g.clusterLabel)}
                  className="card stats-profile-card"
                  style={{
                    textAlign: 'left',
                    cursor: 'pointer',
                    borderColor: isSelected ? st.color : 'var(--border)',
                    boxShadow: isSelected ? `0 0 0 2px ${st.border}` : undefined,
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                    <span
                      className="status-badge"
                      style={{ background: st.bg, color: st.color, fontSize: 12 }}
                    >
                      {g.nombre}
                    </span>
                    <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--ink-primary)' }}>
                      {g.tamano} {g.tamano === 1 ? 'docente' : 'docentes'} ({g.porcentaje}%)
                    </span>
                  </div>

                  <p style={{ margin: '10px 0 12px', fontSize: 13, color: 'var(--ink-secondary)' }}>
                    {g.descripcion}
                  </p>

                  <div className="stats-mini-metrics">
                    <div>
                      <span className="stats-mini-label">Calif.</span>
                      <strong>{g.metricas.calificacionPromedio.toFixed(1)}★</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Claridad</span>
                      <strong>{g.metricas.claridad.toFixed(1)}</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Empatía</span>
                      <strong>{g.metricas.empatia.toFixed(1)}</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Carga</span>
                      <strong>{g.metricas.horasEstudio} h/s</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Recom.</span>
                      <strong>{g.metricas.tasaRecomendacionPct}%</strong>
                    </div>
                  </div>
                </button>
              );
            })}
          </div>

          {/* Selected Profile Detail Drawer */}
          {activeGroup && (
            <div className="card card-pad" style={{ marginTop: 16 }}>
              <div className="section-header" style={{ marginBottom: 12 }}>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
                    <h3 style={{ fontSize: 18, fontWeight: 700 }}>{activeGroup.nombre}</h3>
                    <span className="badge-diff">{activeGroup.metricas.dificultadTexto}</span>
                    <span className="pill-verified">
                      {activeGroup.metricas.tasaRecomendacionPct}% recomendación
                    </span>
                  </div>
                  <p style={{ margin: '6px 0 0', fontSize: 13.5, color: 'var(--ink-secondary)' }}>
                    <strong>¿Te conviene?</strong> {activeGroup.consejoEstudiante}
                  </p>
                </div>
                {modelo === 'kmeans' && (
                  <Link
                    to={`/?perfil=${encodeURIComponent(activeGroup.nombre)}`}
                    className="btn btn-outline btn-sm"
                  >
                    <span>Filtrar en catálogo</span>
                    <ArrowRight size={14} />
                  </Link>
                )}
              </div>

              <div className="stats-teacher-chips">
                {activeGroup.docentes.map((doc) => (
                  <Link key={doc.id} to={`/docentes/${doc.id}`} className="stats-teacher-pill">
                    <div>
                      <div style={{ fontWeight: 700, fontSize: 13.5, color: 'var(--ink-primary)' }}>
                        {doc.nombre}
                      </div>
                      <div style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
                        {doc.cursoPrincipal} · {doc.sede.split('·')[0].trim()}
                      </div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
                      <span className="rating-chip">{doc.calificacion.toFixed(1)}★</span>
                      <span style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
                        {doc.avgHorasEstudio}h/s
                      </span>
                    </div>
                  </Link>
                ))}
              </div>
            </div>
          )}
        </section>
      )}

      {/* Section 2: Interactive Real-Axis Scatter Plot */}
      <section className="card card-pad" style={{ marginBottom: 28 }}>
        <div className="section-header" style={{ marginBottom: 14 }}>
          <div>
            <h2 style={{ fontSize: 20, fontWeight: 700 }}>
              Mapa Visual de Docentes (ejes reales)
            </h2>
            <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--ink-muted)' }}>
              Pasa el cursor sobre cualquier punto para ver al docente y haz clic para abrir su perfil.
            </p>
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button
              type="button"
              className={`filter-chip ${scatterMode === 'calificacion_horas' ? 'active-sage' : ''}`}
              onClick={() => setScatterMode('calificacion_horas')}
            >
              Calificación vs. Horas/semana
            </button>
            <button
              type="button"
              className={`filter-chip ${scatterMode === 'claridad_empatia' ? 'active-sage' : ''}`}
              onClick={() => setScatterMode('claridad_empatia')}
            >
              Claridad vs. Empatía
            </button>
          </div>
        </div>

        <div className="scatter-layout">
          <div className="scatter-svg-wrap">
            <svg
              viewBox={`0 0 ${svgW} ${svgH}`}
              role="img"
              aria-label="Mapa de docentes por métricas reales"
              style={{ width: '100%', height: 'auto', display: 'block' }}
            >
              {/* Horizontal grid & Y labels (1 to 5) */}
              {[1, 2, 3, 4, 5].map((val) => {
                const y = padT + (1 - (val - 1) / 4) * plotH;
                return (
                  <g key={`y-${val}`}>
                    <line x1={padL} y1={y} x2={svgW - padR} y2={y} stroke="#e3e8ee" strokeDasharray="3 3" />
                    <text x={padL - 10} y={y + 4} textAnchor="end" fontSize="11" fill="#64748b">
                      {val.toFixed(0)}★
                    </text>
                  </g>
                );
              })}

              {/* Vertical grid & X labels */}
              {(scatterMode === 'calificacion_horas'
                ? [0, 5, 10, 15, 20, 25]
                : [1, 2, 3, 4, 5]
              ).map((val) => {
                const x =
                  scatterMode === 'calificacion_horas'
                    ? padL + (val / maxHoras) * plotW
                    : padL + ((val - 1) / 4) * plotW;
                return (
                  <g key={`x-${val}`}>
                    <line x1={x} y1={padT} x2={x} y2={svgH - padB} stroke="#e3e8ee" strokeDasharray="3 3" />
                    <text x={x} y={svgH - padB + 18} textAnchor="middle" fontSize="11" fill="#64748b">
                      {scatterMode === 'calificacion_horas' ? `${val}h` : `${val}`}
                    </text>
                  </g>
                );
              })}

              {/* Axis titles */}
              <text x={padL + plotW / 2} y={svgH - 8} textAnchor="middle" fontSize="12" fontWeight="600" fill="#475569">
                {scatterMode === 'calificacion_horas'
                  ? 'Horas de estudio semanal reportadas'
                  : 'Claridad de explicación (1–5)'}
              </text>
              <text
                x={16}
                y={padT + plotH / 2}
                textAnchor="middle"
                fontSize="12"
                fontWeight="600"
                fill="#475569"
                transform={`rotate(-90 16 ${padT + plotH / 2})`}
              >
                {scatterMode === 'calificacion_horas' ? 'Calificación promedio' : 'Empatía y trato'}
              </text>

              {/* Sweet-spot highlight when in calificacion_horas */}
              {scatterMode === 'calificacion_horas' && (
                <rect
                  x={padL}
                  y={padT}
                  width={(8 / maxHoras) * plotW}
                  height={((5 - 4) / 4) * plotH}
                  fill="#065f46"
                  opacity={0.05}
                  rx={6}
                />
              )}

              {/* Points */}
              {mapaDocentes.map((d) => {
                const { x, y } = getCoords(d);
                const perfilNombre = modelo === 'kmeans' ? d.perfilKmeans : d.perfilMeanshift;
                const clusterVal = modelo === 'kmeans' ? d.perfilKmeansId : d.perfilMeanshiftId;
                const st = getProfileStyle(perfilNombre, clusterVal || 0);
                const dimmed = selectedCluster !== null && clusterVal !== selectedCluster;
                const isHovered = hoveredDoc?.id === d.id;

                return (
                  <Link key={d.id} to={`/docentes/${d.id}`}>
                    <g
                      onMouseEnter={() => setHoveredDoc(d)}
                      onMouseLeave={() => setHoveredDoc(null)}
                      style={{ cursor: 'pointer' }}
                    >
                      {d.esOutlierDbscan && (
                        <circle
                          cx={x}
                          cy={y}
                          r={isHovered ? 12 : 10}
                          fill="none"
                          stroke="#dc2626"
                          strokeWidth={1.8}
                          strokeDasharray="3 2"
                          opacity={dimmed ? 0.35 : 0.9}
                        />
                      )}
                      <circle
                        cx={x}
                        cy={y}
                        r={isHovered ? 8 : 6}
                        fill={st.color}
                        stroke="#ffffff"
                        strokeWidth={1.5}
                        opacity={dimmed ? 0.25 : 0.92}
                      />
                    </g>
                  </Link>
                );
              })}
            </svg>
          </div>

          {/* Info Card / Legend */}
          <div className="scatter-sidebar">
            {hoveredDoc ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <div className="eyebrow" style={{ marginBottom: 0 }}>
                  {hoveredDoc.perfilKmeans}
                </div>
                <div style={{ fontWeight: 700, fontSize: 16 }}>{hoveredDoc.nombre}</div>
                <div style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>
                  {hoveredDoc.cursoPrincipal} · {hoveredDoc.sede.split('·')[0].trim()}
                </div>
                <div className="divider" style={{ margin: '6px 0' }} />
                <div className="info-kv" style={{ padding: '4px 0' }}>
                  <span style={{ color: 'var(--ink-muted)' }}>Calificación</span>
                  <strong>{hoveredDoc.calificacion.toFixed(1)} / 5</strong>
                </div>
                <div className="info-kv" style={{ padding: '4px 0' }}>
                  <span style={{ color: 'var(--ink-muted)' }}>Carga semanal</span>
                  <strong>{hoveredDoc.avgHorasEstudio} h/sem</strong>
                </div>
                <div className="info-kv" style={{ padding: '4px 0' }}>
                  <span style={{ color: 'var(--ink-muted)' }}>Lo recomienda</span>
                  <strong>{hoveredDoc.tasaRecomendacionPct}%</strong>
                </div>
                <div className="info-kv" style={{ padding: '4px 0' }}>
                  <span style={{ color: 'var(--ink-muted)' }}>Claridad / Empatía</span>
                  <strong>
                    {hoveredDoc.avgClaridad.toFixed(1)} / {hoveredDoc.avgEmpatia.toFixed(1)}
                  </strong>
                </div>
                {hoveredDoc.esOutlierDbscan && (
                  <div className="status-badge status-RECHAZADA" style={{ marginTop: 4 }}>
                    Señal atípica detectada (DBSCAN)
                  </div>
                )}
              </div>
            ) : (
              <div>
                <h3 style={{ fontSize: 15, fontWeight: 700, marginBottom: 10 }}>Cómo leer este mapa</h3>
                <p style={{ fontSize: 13, color: 'var(--ink-secondary)', margin: '0 0 12px' }}>
                  {scatterMode === 'calificacion_horas'
                    ? 'La zona sombreada superior izquierda agrupa docentes con calificación ≥ 4.0 y carga ≤ 8 horas por semana.'
                    : 'Arriba a la derecha se ubican los docentes que explican con claridad y mantienen un trato cercano.'}
                </p>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, fontSize: 12.5 }}>
                  {(activeModel?.grupos || []).map((g, i) => {
                    const st = getProfileStyle(g.nombre, i);
                    return (
                      <div key={g.clusterLabel} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <span
                          style={{
                            width: 10,
                            height: 10,
                            borderRadius: 99,
                            background: st.color,
                            flexShrink: 0,
                          }}
                        />
                        <span>{g.nombre}</span>
                      </div>
                    );
                  })}
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
                    <span
                      style={{
                        width: 12,
                        height: 12,
                        borderRadius: 99,
                        border: '2px dashed #dc2626',
                        flexShrink: 0,
                      }}
                    />
                    <span>Caso atípico (DBSCAN)</span>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Section 3: Distribuciones por Sede, Facultad y Periodo */}
      <section className="stats-two-grid" style={{ marginBottom: 28 }}>
        <div className="card card-pad">
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
            <Building2 size={18} color="#2b5c8f" />
            <h2 style={{ fontSize: 18, fontWeight: 700 }}>Panorama por Sede y Facultad</h2>
          </div>

          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-muted)', marginBottom: 8 }}>
            POR SEDE UTP
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginBottom: 20 }}>
            {distribuciones.porSede.map((s) => (
              <div key={s.nombre}>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, marginBottom: 4 }}>
                  <strong>{s.nombre.split('·')[0].trim()}</strong>
                  <span style={{ color: 'var(--ink-muted)' }}>
                    {s.totalDocentes} doc. · {s.calificacionPromedio.toFixed(2)}★ · {s.tasaRecomendacionPct}% recom.
                  </span>
                </div>
                <div className="criteria-track">
                  <div
                    className="criteria-fill"
                    style={{ width: `${(s.calificacionPromedio / 5) * 100}%` }}
                  />
                </div>
              </div>
            ))}
          </div>

          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-muted)', marginBottom: 8 }}>
            POR FACULTAD
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {distribuciones.porFacultad.map((f) => (
              <div key={f.nombre}>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, marginBottom: 4 }}>
                  <strong>{f.nombre}</strong>
                  <span style={{ color: 'var(--ink-muted)' }}>
                    {f.totalDocentes} doc. · {f.calificacionPromedio.toFixed(2)}★ · {f.avgHorasEstudio} h/s
                  </span>
                </div>
                <div className="criteria-track">
                  <div
                    className="criteria-fill"
                    style={{
                      width: `${(f.calificacionPromedio / 5) * 100}%`,
                      background: 'var(--brand-green)',
                    }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="card card-pad">
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}>
            <Calendar size={18} color="#065f46" />
            <h2 style={{ fontSize: 18, fontWeight: 700 }}>Evolución por Ciclo y Dificultad</h2>
          </div>

          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-muted)', marginBottom: 8 }}>
            PERIODOS ACADÉMICOS
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 20 }}>
            {distribuciones.porPeriodo.map((p) => (
              <div
                key={p.codigo}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  padding: '10px 12px',
                  borderRadius: 'var(--radius-md)',
                  background: p.esActual ? 'var(--bg-sage)' : 'var(--bg-canvas)',
                  border: '1px solid var(--border)',
                  gap: 10,
                }}
              >
                <div>
                  <strong>Ciclo {p.codigo}</strong>{' '}
                  {p.esActual && <span className="pill-verified" style={{ marginLeft: 6 }}>Actual</span>}
                  <div style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
                    {p.totalResenas} reseñas · ~{p.avgHorasEstudio} h/sem
                  </div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span className="rating-chip">{p.calificacionPromedio.toFixed(2)}★</span>
                  <span style={{ fontSize: 12.5, fontWeight: 600 }}>{p.tasaRecomendacionPct}% rec.</span>
                </div>
              </div>
            ))}
          </div>

          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-muted)', marginBottom: 8 }}>
            DISTRIBUCIÓN POR NIVEL DE EXIGENCIA
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10 }}>
            {distribuciones.porDificultad.map((d) => (
              <div
                key={d.nivel}
                style={{
                  padding: 12,
                  borderRadius: 'var(--radius-md)',
                  background: 'var(--bg-canvas)',
                  border: '1px solid var(--border)',
                }}
              >
                <div style={{ fontWeight: 700, fontSize: 14 }}>{d.nivel}</div>
                <div style={{ fontSize: 20, fontWeight: 700, margin: '4px 0', color: 'var(--brand-blue)' }}>
                  {d.porcentaje}%
                </div>
                <div style={{ fontSize: 11.5, color: 'var(--ink-muted)' }}>
                  {d.calificacionPromedio.toFixed(1)}★ · {d.avgHorasEstudio} h/s
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Section 4: Perfiles de Estudiantes Evaluadores (K-Means Usuarios) */}
      {perfilesEstudiantes && (
        <section style={{ marginBottom: 28 }}>
          <div className="section-header" style={{ marginBottom: 14 }}>
            <div>
              <h2 style={{ fontSize: 20, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 8 }}>
                <Users size={20} color="#2b5c8f" />
                <span>¿Cómo evalúa la comunidad estudiantil?</span>
              </h2>
              <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--ink-muted)' }}>
                Segmentación K-Means sobre {perfilesEstudiantes.nMuestras} cuentas estudiantiles activas
                para entender quiénes publican y cómo cambia el rigor según el ciclo.
              </p>
            </div>
          </div>

          <div className="compare-grid">
            {perfilesEstudiantes.grupos.map((u) => {
              const isAlert = u.nombre.toLowerCase().includes('atípica');
              return (
                <div
                  key={u.clusterLabel}
                  className="card card-pad"
                  style={isAlert ? { borderColor: '#fecaca', background: '#fffafa' } : undefined}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                    <span className={`status-badge ${isAlert ? 'status-RECHAZADA' : 'status-APROBADA'}`}>
                      {u.nombre}
                    </span>
                    <strong>
                      {u.tamano} alumnos ({u.porcentaje}%)
                    </strong>
                  </div>
                  <p style={{ fontSize: 13, color: 'var(--ink-secondary)', margin: '10px 0 14px' }}>
                    {u.descripcion}
                  </p>
                  <div className="stats-mini-metrics">
                    <div>
                      <span className="stats-mini-label">Ciclo prom.</span>
                      <strong>{u.cicloPromedio}</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Reseñas</span>
                      <strong>{u.resenasPromedio}</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Guardados</span>
                      <strong>{u.guardadosPromedio}</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Calif. dada</span>
                      <strong>{u.calificacionDadaPromedio.toFixed(1)}★</strong>
                    </div>
                    <div>
                      <span className="stats-mini-label">Recom.</span>
                      <strong>{u.tasaRecomendacionPct}%</strong>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* Section 5: Control de Calidad y Casos Atípicos (DBSCAN) */}
      <section className="card card-pad">
        <div className="section-header" style={{ marginBottom: 14 }}>
          <div>
            <h2 style={{ fontSize: 20, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 8 }}>
              <ShieldCheck size={20} color="#065f46" />
              <span>Control de Calidad y Detección de Casos Atípicos (DBSCAN)</span>
            </h2>
            <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--ink-muted)' }}>
              Aislamos automáticamente reseñas sospechosas de spam antes de publicarse y señalamos
              docentes con métricas extremas o polarizantes.
            </p>
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <span className="pill-verified">
              <Layers size={14} /> {alertasCalidad.resenasAnomalasResumen.totalAnalizadas} reseñas analizadas
            </span>
            <span className="status-badge status-PENDIENTE">
              {alertasCalidad.resenasAnomalasResumen.totalAnomalasDetectadas} anómalas aisladas
            </span>
            <span className="status-badge status-RECHAZADA">
              {alertasCalidad.resenasAnomalasResumen.totalPromocionalesDetectadas} promocionales filtradas
            </span>
          </div>
        </div>

        <div className="compare-grid">
          {alertasCalidad.docentesAtipicos.map((d) => (
            <div
              key={d.docenteId}
              style={{
                padding: 16,
                borderRadius: 'var(--radius-md)',
                background: 'var(--bg-canvas)',
                border: '1px solid var(--border)',
                display: 'flex',
                flexDirection: 'column',
                gap: 8,
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
                <div>
                  <Link
                    to={`/docentes/${d.docenteId}`}
                    style={{ fontWeight: 700, fontSize: 15, color: 'var(--brand-blue)' }}
                  >
                    {d.docenteNombre}
                  </Link>
                  <div style={{ fontSize: 12, color: 'var(--ink-muted)' }}>
                    {d.facultad}
                  </div>
                </div>
                <span className="rating-chip">{d.calificacion.toFixed(1)}★</span>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 4 }}>
                {d.razones.map((r) => (
                  <div
                    key={r}
                    style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12.5, color: '#b45309' }}
                  >
                    <AlertTriangle size={14} style={{ flexShrink: 0 }} />
                    <span>{r}</span>
                  </div>
                ))}
              </div>

              <div style={{ marginTop: 'auto', paddingTop: 6 }}>
                <Link to={`/docentes/${d.docenteId}`} className="btn btn-outline btn-sm">
                  <BookOpen size={14} />
                  <span>Ver detalle y reseñas</span>
                </Link>
              </div>
            </div>
          ))}
        </div>

        <div className="trust-note" style={{ marginTop: 18 }}>
          <Award size={18} color="#065f46" style={{ flexShrink: 0, marginTop: 2 }} />
          <span>
            Todas las reseñas marcadas como spam o ráfagas coordinadas permanecen ocultas en la{' '}
            <strong>cola de moderación</strong> hasta ser revisadas por Coordinación Académica UTP.
          </span>
        </div>
      </section>
    </div>
  );
}
