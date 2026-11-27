import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Bookmark } from 'lucide-react';
import { guardadosApi } from '../services/api';
import type { Docente } from '../types/api';
import { useAuth } from '../context/AuthContext';
import { TeacherCard } from '../components/TeacherCard';

export function SavedTeachersPage() {
  const { user, savedIds } = useAuth();
  const [docentes, setDocentes] = useState<Docente[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) {
      setLoading(false);
      return;
    }
    setLoading(true);
    guardadosApi
      .listar(user.id)
      .then(setDocentes)
      .finally(() => setLoading(false));
  }, [user?.id, savedIds.size]);

  if (!user) {
    return (
      <div className="container" style={{ padding: '48px 24px' }}>
        <div className="card card-pad" style={{ textAlign: 'center', padding: 40 }}>
          <Bookmark size={32} color="#065f46" style={{ marginBottom: 12 }} />
          <h1 style={{ fontSize: 24, marginBottom: 8 }}>Tus docentes guardados</h1>
          <p style={{ color: 'var(--ink-muted)', marginBottom: 18 }}>
            Inicia sesión con tu correo UTP para guardar opciones de matrícula y compararlas luego.
          </p>
          <Link to="/login" className="btn btn-primary">
            Iniciar sesión
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="container" style={{ padding: '36px 24px 56px' }}>
      <div className="section-header">
        <div>
          <h1 style={{ fontSize: 28, fontWeight: 700 }}>Docentes guardados</h1>
          <p style={{ color: 'var(--ink-muted)', margin: '4px 0 0' }}>
            Tu lista rápida de docentes para la próxima matrícula.
          </p>
        </div>
        <Link to="/comparar" className="btn btn-outline">
          Comparar por curso
        </Link>
      </div>

      {loading ? (
        <div className="card card-pad">Cargando guardados...</div>
      ) : docentes.length === 0 ? (
        <div className="card card-pad" style={{ textAlign: 'center', padding: 40 }}>
          <h3 style={{ marginBottom: 6 }}>No tienes docentes guardados todavía</h3>
          <p style={{ color: 'var(--ink-muted)', marginBottom: 16 }}>
            Usa el ícono de marcador en cualquier tarjeta de docente para tenerlo a la mano.
          </p>
          <Link to="/" className="btn btn-primary">
            Explorar docentes
          </Link>
        </div>
      ) : (
        <div className="teacher-list">
          {docentes.map((doc, idx) => (
            <TeacherCard key={doc.id} docente={doc} variantIndex={idx} />
          ))}
        </div>
      )}
    </div>
  );
}
