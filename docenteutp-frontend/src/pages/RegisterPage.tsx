import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ShieldCheck, UserPlus } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';

const CARRERAS = [
  'Ingeniería de Software',
  'Ingeniería de Sistemas',
  'Ingeniería Industrial',
  'Informática',
  'Ingeniería Mecatrónica',
  'Ingeniería Electrónica',
  'Ingeniería Biomédica',
  'Ingeniería Aeronáutica',
  'Psicología',
];

export function RegisterPage() {
  const { register } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [nombre, setNombre] = useState('');
  const [correo, setCorreo] = useState('');
  const [password, setPassword] = useState('');
  const [carrera, setCarrera] = useState(CARRERAS[0]);
  const [ciclo, setCiclo] = useState(5);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await register({ nombre, correo, password, carrera, ciclo });
      showToast('Cuenta UTP verificada y creada con éxito', 'success');
      navigate('/');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-wrap">
      <div className="card card-pad">
        <div style={{ marginBottom: 14 }}>
          <span className="pill-verified">
            <ShieldCheck size={15} />
            <span>Verificación institucional @utp.edu.pe</span>
          </span>
        </div>
        <h1 style={{ fontSize: 26, fontWeight: 700, marginBottom: 6 }}>Crear cuenta estudiantil</h1>
        <p style={{ margin: '0 0 22px', color: 'var(--ink-muted)' }}>
          Tus reseñas se mostrarán de forma anónima con insignia de estudiante verificado.
        </p>

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label" htmlFor="reg-nombre">
              Nombre completo
            </label>
            <input
              id="reg-nombre"
              type="text"
              className="form-control"
              placeholder="Ej. Valeria Paredes"
              value={nombre}
              onChange={(e) => setNombre(e.target.value)}
              required
            />
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="reg-correo">
              Correo institucional UTP
            </label>
            <input
              id="reg-correo"
              type="email"
              className="form-control"
              placeholder="u21205364@utp.edu.pe"
              value={correo}
              onChange={(e) => setCorreo(e.target.value)}
              required
            />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 110px', gap: 12 }}>
            <div className="form-group">
              <label className="form-label" htmlFor="reg-carrera">
                Carrera
              </label>
              <select
                id="reg-carrera"
                className="form-control"
                value={carrera}
                onChange={(e) => setCarrera(e.target.value)}
              >
                {CARRERAS.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="reg-ciclo">
                Ciclo
              </label>
              <input
                id="reg-ciclo"
                type="number"
                min={1}
                max={12}
                className="form-control"
                value={ciclo}
                onChange={(e) => setCiclo(Number(e.target.value))}
                required
              />
            </div>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="reg-pass">
              Contraseña (mínimo 8 caracteres)
            </label>
            <input
              id="reg-pass"
              type="password"
              minLength={8}
              className="form-control"
              placeholder="Mínimo 8 caracteres"
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
            <UserPlus size={16} />
            <span>{loading ? 'Creando cuenta...' : 'Crear cuenta UTP'}</span>
          </button>
        </form>

        <div style={{ textAlign: 'center', fontSize: 13.5, color: 'var(--ink-muted)', marginTop: 18 }}>
          ¿Ya tienes cuenta?{' '}
          <Link to="/login" style={{ color: 'var(--brand-blue)', fontWeight: 600 }}>
            Inicia sesión
          </Link>
        </div>
      </div>
    </div>
  );
}
