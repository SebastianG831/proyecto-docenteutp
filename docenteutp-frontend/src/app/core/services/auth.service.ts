import { Injectable, signal, computed, inject } from '@angular/core';
import { ApiService } from './api.service';
import { AuthResponse, LoginRequest, RegistroRequest } from '../models/api.models';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private api = inject(ApiService);

  // Simulación temporal de usuario para pruebas - CONFIGURABLE
  private readonly MOCK_USER_ID = 1;

  // Estado reactivo
  private _user = signal<AuthResponse | null>(null);
  private _loading = signal(false);
  private _error = signal<string | null>(null);

  readonly user = this._user.asReadonly();
  readonly isLoggedIn = computed(() => this._user() !== null);
  readonly loading = this._loading.asReadonly();
  readonly error = this._error.asReadonly();
  readonly currentUserId = computed(() => this._user()?.id ?? this.MOCK_USER_ID);

  // Simulación de login para desarrollo (backend no tiene JWT/session real)
  login(credentials: LoginRequest): void {
    this._loading.set(true);
    this._error.set(null);

    // Simulación: en producción esto llamaría al backend
    // El backend actual no devuelve token ni mantiene sesión
    setTimeout(() => {
      const mockUser: AuthResponse = {
        id: this.MOCK_USER_ID,
        nombre: 'Ana María',
        correo: credentials.correo,
        carrera: 'Ingeniería de Sistemas',
        ciclo: 7,
        rol: 'ESTUDIANTE'
      };
      this._user.set(mockUser);
      this._loading.set(false);
    }, 500);
  }

  register(data: RegistroRequest): void {
    this._loading.set(true);
    this._error.set(null);

    setTimeout(() => {
      const mockUser: AuthResponse = {
        id: this.MOCK_USER_ID,
        nombre: data.nombre,
        correo: data.correo,
        carrera: data.carrera,
        ciclo: data.ciclo,
        rol: 'ESTUDIANTE'
      };
      this._user.set(mockUser);
      this._loading.set(false);
    }, 500);
  }

  logout(): void {
    this._user.set(null);
  }

  // Método para obtener el userId simulado (para enviar en reseñas)
  getMockUserId(): number {
    return this.currentUserId();
  }

  // Permite cambiar el userId simulado en runtime (para testing)
  setMockUserId(id: number): void {
    // En una implementación real esto no existiría
    console.warn('[DEV] Mock user ID cambiado a:', id);
  }
}