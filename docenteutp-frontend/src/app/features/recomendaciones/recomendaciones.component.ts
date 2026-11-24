import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { DocenteService } from '../../core/services/docente.service';
import { DocenteResponse, NivelDificultad } from '../../core/models/api.models';
import { ToastService } from '../../core/services/toast.service';

@Component({
  selector: 'app-recomendaciones',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './recomendaciones.component.html',
  styleUrl: './recomendaciones.component.scss',
})
export class RecomendacionesComponent implements OnInit {
  private docenteService = inject(DocenteService);
  private toast = inject(ToastService);

  docentes = signal<DocenteResponse[]>([]);
  loading = signal(false);
  error = signal<string | null>(null);

  // Filtros
  selectedEstilo = '';
  selectedDificultad: NivelDificultad | '' = '';
  sortBy = 'calificacion';

  estilosDisponibles = [
    'TEORICO',
    'PRACTICO',
    'MIXTO',
    'INTERACTIVO',
    'AUTODIDACTA'
  ];

  dificultadesDisponibles: (NivelDificultad | '')[] = ['', 'LIGERO', 'MODERADO', 'EXIGENTE'];

  ngOnInit(): void {
    this.cargarRecomendaciones();
  }

  cargarRecomendaciones(): void {
    this.loading.set(true);
    this.error.set(null);

    // Para recomendaciones, ordenar por calificación descendente por defecto
    const params = {
      estilo: this.selectedEstilo || undefined,
      dificultad: this.selectedDificultad || undefined
    };

    this.docenteService.getDocentes(params).subscribe({
      next: (data) => {
        // Ordenar localmente ya que el backend no tiene sort
        let sorted = [...data];
        if (this.sortBy === 'calificacion') {
          sorted.sort((a, b) => b.calificacion - a.calificacion);
        } else if (this.sortBy === 'resenas') {
          sorted.sort((a, b) => b.totalResenas - a.totalResenas);
        } else if (this.sortBy === 'nombre') {
          sorted.sort((a, b) => a.nombre.localeCompare(b.nombre));
        }
        this.docentes.set(sorted.slice(0, 10)); // Top 10
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err.message);
        this.loading.set(false);
        this.toast.error(err.message);
      }
    });
  }

  onFilterChange(): void {
    this.cargarRecomendaciones();
  }

  limpiarFiltros(): void {
    this.selectedEstilo = '';
    this.selectedDificultad = '';
    this.sortBy = 'calificacion';
    this.cargarRecomendaciones();
  }

  getStars(rating: number): number[] {
    return Array(Math.floor(rating)).fill(0);
  }

  getEmptyStars(rating: number): number[] {
    return Array(5 - Math.ceil(rating)).fill(0);
  }

  getInitials(nombre: string): string {
    return nombre.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }
}