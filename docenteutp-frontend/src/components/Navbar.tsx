import { NavLink, Link, useNavigate } from 'react-router-dom';
import {
  Bookmark,
  GraduationCap,
  LogOut,
  ShieldCheck,
  BarChart3,
  PieChart,
  UserCheck,
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { getInitials } from '../utils/formatters';

export function Navbar() {
  const { user, savedIds, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  const isStaff = user?.rol === 'ADMIN' || user?.rol === 'MODERADOR';

  return (
    <header className="navbar">
      <div className="navbar-inner">
        <Link to="/" className="brand-link">
          <div className="brand-icon">
            <GraduationCap size={22} />
          </div>
          <div>
            <div className="brand-name">DocenteUTP</div>
            <div className="brand-sub">Lima Centro · Lima Norte · Arequipa</div>
          </div>
        </Link>

        <nav className="nav-links" aria-label="Navegación principal">
          <NavLink to="/" end className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
            Explorar docentes
          </NavLink>
          <NavLink
            to="/comparar"
            className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
          >
            Comparar cursos
          </NavLink>
          <NavLink
            to="/estadisticas"
            className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
          >
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              <PieChart size={15} /> Estadísticas
            </span>
          </NavLink>
          <NavLink
            to="/mis-resenas"
            className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
          >
            Mis reseñas
          </NavLink>
          <NavLink
            to="/como-funciona"
            className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
          >
            Cómo funciona
          </NavLink>
          {isStaff && (
            <NavLink
              to="/admin"
              className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
            >
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                <BarChart3 size={15} /> Panel B2B
              </span>
            </NavLink>
          )}
        </nav>

        <div className="nav-actions">
          <Link to="/guardados" className="btn btn-outline btn-sm">
            <Bookmark size={15} />
            <span>Guardados</span>
            {user && savedIds.size > 0 && (
              <span className="pill-verified" style={{ padding: '2px 7px', fontSize: 11 }}>
                {savedIds.size}
              </span>
            )}
          </Link>

          {user ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span className="pill-verified" title={user.correo}>
                <ShieldCheck size={15} />
                <span>
                  {user.rol === 'ADMIN'
                    ? 'Coordinación'
                    : user.rol === 'MODERADOR'
                    ? 'Moderación'
                    : 'Estudiante UTP'}
                </span>
              </span>
              <div className="avatar avatar-sm avatar-sage" title={user.nombre}>
                {getInitials(user.nombre)}
              </div>
              <button
                type="button"
                className="btn btn-outline btn-icon"
                onClick={handleLogout}
                title="Cerrar sesión"
                aria-label="Cerrar sesión"
              >
                <LogOut size={15} />
              </button>
            </div>
          ) : (
            <Link to="/login" className="btn btn-primary btn-sm">
              <UserCheck size={15} />
              <span>Iniciar sesión</span>
            </Link>
          )}
        </div>
      </div>
    </header>
  );
}
