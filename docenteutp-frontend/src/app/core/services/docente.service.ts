import { Injectable, inject } from '@angular/core';
import { ApiService } from './api.service';
import {
  DocenteResponse,
  DocenteDetalleResponse,
  CursoResponse,
  NivelDificultad
} from '../models/api.models';
import { HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface DocenteFilters {
  q?: string;
  estilo?: string;
  dificultad?: NivelDificultad;
}

@Injectable({
  providedIn: 'root'
})
export class DocenteService {
  private api = inject(ApiService);

  getDocentes(filters: DocenteFilters = {}): Observable<DocenteResponse[]> {
    let params = new HttpParams();
    if (filters.q?.trim()) params = params.set('q', filters.q.trim());
    if (filters.estilo?.trim()) params = params.set('estilo', filters.estilo.trim());
    if (filters.dificultad) params = params.set('dificultad', filters.dificultad);

    return this.api.get<DocenteResponse[]>('/docentes', params);
  }

  getDocenteById(id: number): Observable<DocenteDetalleResponse> {
    return this.api.get<DocenteDetalleResponse>(`/docentes/${id}`);
  }

  getCursosByDocente(docenteId: number): Observable<CursoResponse[]> {
    return this.api.get<CursoResponse[]>(`/docentes/${docenteId}/cursos`);
  }
}