import { useState, type FormEvent } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { LogIn, ShieldCheck } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';

export function LoginPage() {
  const { login } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from || '/';

  const [correo, setCorreo] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const user = await login(correo, password);
      showToast(`¡Bienvenido, ${user.nombre}!`, 'success');
      navigate(user.rol === 'ADMIN' && from === '/' ? '/admin' : from, { replace: true });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  const fillDemo = (demoEmail: string, demoPass: string) => {
    setCorreo(demoEmail);
    setPassword(demoPass);
    setError('');
  };

  return (
    <div className="auth-wrap">
      <div className="card card-pad">
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
          <span className="pill-verified">
            <ShieldCheck size={15} />
            <span>Acceso verificado UTP</span>
          </span>
        </div>
        <h1 style={{ fontSize: 26, fontWeight: 700, marginBottom: 6 }}>Iniciar sesión</h1>
        <p style={{ margin: '0 0 22px', color: 'var(--ink-muted)' }}>
          Ingresa con tu correo institucional <code>@utp.edu.pe</code>.
        </p>

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label" htmlFor="login-correo">
              Correo institucional
            </label>
            <input
              id="login-correo"
              type="email"
              className="form-control"
              placeholder="u21205364@utp.edu.pe"
              value={correo}
              onChange={(e) => setCorreo(e.target.value)}
              required
            />
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="login-password">
              Contraseña
            </label>
            <input
              id="login-password"
              type="password"
              className="form-control"
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
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

          <button type="submit" className="btn btn-primary" style={{ width: '100%' }} disabled={loading}>
            <LogIn size={16} />
            <span>{loading ? 'Ingresando...' : 'Ingresar'}</span>
          </button>
        </form>

        <div className="divider" />

        <div style={{ fontSize: 12.5, color: 'var(--ink-muted)', marginBottom: 10 }}>
          Cuentas de demostración disponibles:
        </div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 18 }}>
          <button
            type="button"
            className="btn btn-outline btn-sm"
            onClick={() => fillDemo('alumno1@utp.edu.pe', 'estudiante123')}
          >
            Demo Estudiante
          </button>
          <button
            type="button"
            className="btn btn-outline btn-sm"
            onClick={() => fillDemo('admin@utp.edu.pe', 'admin1234')}
          >
            Demo Coordinación (B2B)
          </button>
        </div>

        <div style={{ textAlign: 'center', fontSize: 13.5, color: 'var(--ink-muted)' }}>
          ¿Aún no tienes cuenta?{' '}
          <Link to="/registro" style={{ color: 'var(--brand-blue)', fontWeight: 600 }}>
            Regístrate con tu correo UTP
          </Link>
        </div>
      </div>
    </div>
  );
}
