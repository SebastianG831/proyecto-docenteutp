import { Injectable, inject } from '@angular/core';
import { ApiService } from './api.service';
import {
  ResenaRequest,
  ResenaResponse,
  EstadoResena,
  NivelDificultad
} from '../models/api.models';
import { AuthService } from './auth.service';
import { Observable } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class ResenaService {
  private api = inject(ApiService);
  private auth = inject(AuthService);

  crearResena(resena: Omit<ResenaRequest, 'usuarioId'>): Observable<ResenaResponse> {
    const usuarioId = this.auth.getMockUserId();
    const payload: ResenaRequest = { ...resena, usuarioId };
    return this.api.post<ResenaResponse>('/resenas', payload);
  }

  getResenasByDocente(docenteId: number): Observable<ResenaResponse[]> {
    return this.api.get<ResenaResponse[]>(`/resenas/docente/${docenteId}`);
  }

  getResenasByUsuario(usuarioId: number): Observable<ResenaResponse[]> {
    return this.api.get<ResenaResponse[]>(`/resenas/usuario/${usuarioId}`);
  }
}