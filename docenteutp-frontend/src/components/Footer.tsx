import { Link } from 'react-router-dom';
import { ShieldCheck } from 'lucide-react';

export function Footer() {
  return (
    <footer className="footer">
      <div className="footer-inner">
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <ShieldCheck size={16} color="#065f46" />
          <span>
            <strong>DocenteUTP</strong> · Comunidad verificada con correo institucional{' '}
            <code>@utp.edu.pe</code> · Sede Lima Centro
          </span>
        </div>
        <div style={{ display: 'flex', gap: 18 }}>
          <Link to="/comparar">Comparar cursos</Link>
          <Link to="/como-funciona">Cómo funciona</Link>
          <span>Innovación y Transformación Digital · 2026</span>
        </div>
      </div>
    </footer>
  );
}
