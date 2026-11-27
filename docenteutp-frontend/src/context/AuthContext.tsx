import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { authApi, guardadosApi } from '../services/api';
import type { UsuarioAuth } from '../types/api';

interface AuthContextValue {
  user: UsuarioAuth | null;
  savedIds: Set<number>;
  login: (correo: string, password: string) => Promise<UsuarioAuth>;
  register: (payload: {
    nombre: string;
    correo: string;
    password: string;
    carrera: string;
    ciclo: number;
  }) => Promise<UsuarioAuth>;
  logout: () => void;
  toggleSaved: (docenteId: number) => Promise<boolean>;
  refreshSaved: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);
const STORAGE_KEY = 'docenteutp_user_v1';

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<UsuarioAuth | null>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      return raw ? (JSON.parse(raw) as UsuarioAuth) : null;
    } catch {
      return null;
    }
  });

  const [savedIds, setSavedIds] = useState<Set<number>>(new Set());

  const refreshSaved = async () => {
    if (!user) {
      setSavedIds(new Set());
      return;
    }
    try {
      const docs = await guardadosApi.listar(user.id);
      setSavedIds(new Set(docs.map((d) => d.id)));
    } catch {
      // ignore on initial load
    }
  };

  useEffect(() => {
    refreshSaved();
  }, [user?.id]);

  const persistUser = (u: UsuarioAuth | null) => {
    setUser(u);
    if (u) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(u));
    } else {
      localStorage.removeItem(STORAGE_KEY);
    }
  };

  const login = async (correo: string, password: string) => {
    const u = await authApi.login(correo, password);
    persistUser(u);
    return u;
  };

  const register = async (payload: {
    nombre: string;
    correo: string;
    password: string;
    carrera: string;
    ciclo: number;
  }) => {
    const u = await authApi.registro(payload);
    persistUser(u);
    return u;
  };

  const logout = () => {
    persistUser(null);
    setSavedIds(new Set());
  };

  const toggleSaved = async (docenteId: number): Promise<boolean> => {
    if (!user) {
      throw new Error('Inicia sesión con tu correo UTP para guardar docentes');
    }
    const isSaved = savedIds.has(docenteId);
    if (isSaved) {
      await guardadosApi.quitar(user.id, docenteId);
      setSavedIds((prev) => {
        const next = new Set(prev);
        next.delete(docenteId);
        return next;
      });
      return false;
    } else {
      await guardadosApi.guardar(user.id, docenteId);
      setSavedIds((prev) => new Set(prev).add(docenteId));
      return true;
    }
  };

  return (
    <AuthContext.Provider
      value={{ user, savedIds, login, register, logout, toggleSaved, refreshSaved }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth debe usarse dentro de AuthProvider');
  return ctx;
}
