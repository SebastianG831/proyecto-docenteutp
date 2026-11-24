import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';
import { ResenaService } from '../../core/services/resena.service';
import { ResenaResponse, EstadoResena } from '../../core/models/api.models';
import { tiempoTranscurrido } from '../../core/utils/fechas';
import { ToastService } from '../../core/services/toast.service';

@Component({
  selector: 'app-mis-resenas',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './mis-resenas.component.html',
  styleUrl: './mis-resenas.component.scss',
})
export class MisResenasComponent implements OnInit {
  private auth = inject(AuthService);
  private resenaService = inject(ResenaService);
  private toast = inject(ToastService);

  resenas = signal<ResenaResponse[]>([]);
  loading = signal(true);
  error = signal<string | null>(null);

  user = this.auth.user;

  ngOnInit(): void {
    this.cargarResenas();
  }

  cargarResenas(): void {
    const userId = this.auth.getMockUserId();
    this.loading.set(true);
    this.error.set(null);

    this.resenaService.getResenasByUsuario(userId).subscribe({
      next: (data) => {
        this.resenas.set(data);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err.message);
        this.loading.set(false);
        this.toast.error(err.message);
      }
    });
  }

  getEstadoClass(estado: EstadoResena): string {
    switch (estado) {
      case 'APROBADA': return 'estado-aprobada';
      case 'PENDIENTE': return 'estado-pendiente';
      case 'RECHAZADA': return 'estado-rechazada';
      default: return '';
    }
  }

  getEstadoLabel(estado: EstadoResena): string {
    switch (estado) {
      case 'APROBADA': return 'Aprobada';
      case 'PENDIENTE': return 'Pendiente de moderación';
      case 'RECHAZADA': return 'Rechazada';
      default: return estado;
    }
  }

  protected readonly tiempoTranscurrido = tiempoTranscurrido;

  getInitials(nombre: string | undefined): string {
    if (!nombre) return 'AM';
    return nombre.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }

  getStars(rating: number): number[] {
    return Array(Math.floor(rating)).fill(0);
  }

  getEmptyStars(rating: number): number[] {
    return Array(5 - Math.ceil(rating)).fill(0);
  }
}