import { Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse, HttpParams } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError, retry } from 'rxjs/operators';

export interface ApiServiceConfig {
  baseUrl: string;
}

@Injectable({
  providedIn: 'root'
})
export class ApiService {
  private readonly baseUrl = '/api';

  constructor(private http: HttpClient) {}

  get<T>(endpoint: string, params?: HttpParams): Observable<T> {
    return this.http.get<T>(`${this.baseUrl}${endpoint}`, { params }).pipe(
      retry({ count: 1, delay: 500 }),
      catchError(this.handleError)
    );
  }

  post<T>(endpoint: string, body: unknown, params?: HttpParams): Observable<T> {
    return this.http.post<T>(`${this.baseUrl}${endpoint}`, body, { params }).pipe(
      catchError(this.handleError)
    );
  }

  put<T>(endpoint: string, body: unknown): Observable<T> {
    return this.http.put<T>(`${this.baseUrl}${endpoint}`, body).pipe(
      catchError(this.handleError)
    );
  }

  delete<T>(endpoint: string): Observable<T> {
    return this.http.delete<T>(`${this.baseUrl}${endpoint}`).pipe(
      catchError(this.handleError)
    );
  }

  private handleError = (error: HttpErrorResponse): Observable<never> => {
    let errorMessage = 'Ha ocurrido un error inesperado';

    if (error.error instanceof ErrorEvent) {
      errorMessage = `Error de conexión: ${error.error.message}`;
    } else {
      switch (error.status) {
        case 0:
          errorMessage = 'No se puede conectar con el servidor. Verifica que el backend esté corriendo en localhost:8080';
          break;
        case 400:
          errorMessage = error.error?.mensaje || error.error?.message || 'Solicitud inválida';
          break;
        case 401:
          errorMessage = 'No autorizado. Inicia sesión nuevamente';
          break;
        case 403:
          errorMessage = 'No tienes permisos para realizar esta acción';
          break;
        case 404:
          errorMessage = 'Recurso no encontrado';
          break;
        case 409:
          errorMessage = error.error?.mensaje || error.error?.message || 'Conflicto: el recurso ya existe';
          break;
        case 500:
          errorMessage = 'Error interno del servidor. Intenta más tarde';
          break;
        default:
          errorMessage = error.error?.mensaje || error.error?.message || `Error ${error.status}: ${error.statusText}`;
      }
    }

    return throwError(() => new Error(errorMessage));
  };
}