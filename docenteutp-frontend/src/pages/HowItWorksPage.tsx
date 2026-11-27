import { Link } from 'react-router-dom';
import { BarChart3, CheckCircle2, Scale, Search, ShieldCheck, Sparkles } from 'lucide-react';

export function HowItWorksPage() {
  const pillars = [
    {
      icon: <ShieldCheck size={22} color="#065f46" />,
      title: '1. Identidad Verificada UTP',
      desc: 'Solo estudiantes con correo institucional @utp.edu.pe pueden publicar. Las reseñas se muestran de forma anónima, protegiendo al alumno y evitando cuentas falsas.',
    },
    {
      icon: <Scale size={22} color="#2b5c8f" />,
      title: '2. Rúbrica de 3 Criterios Objetivos',
      desc: 'Cada docente es evaluado en Dominio del tema, Claridad de explicación y Empatía/accesibilidad, además del nivel de dificultad (Ligero, Moderado, Exigente).',
    },
    {
      icon: <Search size={22} color="#d97706" />,
      title: '3. Consulta y Comparación Pre-Matrícula',
      desc: 'Busca por nombre de docente o código de curso (ej. SIS-201, MAT-101) y compara horarios en segundos antes de matricularte.',
    },
    {
      icon: <BarChart3 size={22} color="#065f46" />,
      title: '4. Analítica Continua B2B',
      desc: 'Coordinación Académica UTP cuenta con un panel institucional para moderar comentarios anti-spam y monitorear indicadores de calidad docente durante todo el ciclo.',
    },
  ];

  return (
    <div className="container" style={{ padding: '40px 24px 64px' }}>
      <div style={{ maxWidth: 740, marginBottom: 32 }}>
        <div className="eyebrow">Propuesta de Valor · UTP Lima Centro</div>
        <h1 className="hero-title" style={{ fontSize: 34 }}>
          Cómo funciona DocenteUTP
        </h1>
        <p className="hero-subtitle">
          Centralizamos información objetiva, verificada y oportuna antes de la matrícula para
          reducir la incertidumbre académica y mejorar la toma de decisiones.
        </p>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
          gap: 18,
          marginBottom: 28,
        }}
      >
        {pillars.map((p) => (
          <div key={p.title} className="card card-pad">
            <div
              style={{
                width: 44,
                height: 44,
                borderRadius: 'var(--radius-md)',
                background: 'var(--bg-sage)',
                display: 'grid',
                placeItems: 'center',
                marginBottom: 14,
              }}
            >
              {p.icon}
            </div>
            <h2 style={{ fontSize: 17, fontWeight: 700, marginBottom: 8 }}>{p.title}</h2>
            <p style={{ margin: 0, fontSize: 13.5, color: 'var(--ink-secondary)' }}>{p.desc}</p>
          </div>
        ))}
      </div>

      <div className="summary-box" style={{ justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start', maxWidth: 680 }}>
          <div className="summary-icon">
            <Sparkles size={20} />
          </div>
          <div>
            <h3 style={{ fontSize: 18, fontWeight: 700, marginBottom: 6 }}>
              ¿Listo para elegir tus cursos con confianza?
            </h3>
            <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', fontSize: 13, color: 'var(--ink-secondary)' }}>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <CheckCircle2 size={15} color="#047857" /> Gratis para estudiantes UTP
              </span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <CheckCircle2 size={15} color="#047857" /> 1 reseña por docente y curso
              </span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <CheckCircle2 size={15} color="#047857" /> Moderación anti-spam
              </span>
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <Link to="/" className="btn btn-primary">
            Explorar docentes
          </Link>
          <Link to="/comparar" className="btn btn-outline">
            Comparar cursos
          </Link>
        </div>
      </div>
    </div>
  );
}
