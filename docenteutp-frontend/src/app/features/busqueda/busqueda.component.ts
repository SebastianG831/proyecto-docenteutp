import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { DocenteService, DocenteFilters } from '../../core/services/docente.service';
import { DocenteResponse, NivelDificultad } from '../../core/models/api.models';
import { ToastService } from '../../core/services/toast.service';

@Component({
  selector: 'app-busqueda',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './busqueda.component.html',
  styleUrl: './busqueda.component.scss',
})
export class BusquedaComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private docenteService = inject(DocenteService);
  private toast = inject(ToastService);

  searchQuery = '';
  docentes = signal<DocenteResponse[]>([]);
  loading = signal(false);
  error = signal<string | null>(null);

  // Filtros
  selectedEstilo = '';
  selectedDificultad: NivelDificultad | '' = '';
  sortBy = 'relevancia';

  estilosDisponibles = [
    'TEORICO',
    'PRACTICO',
    'MIXTO',
    'INTERACTIVO',
    'AUTODIDACTA'
  ];

  dificultadesDisponibles: (NivelDificultad | '')[] = ['', 'LIGERO', 'MODERADO', 'EXIGENTE'];

  ngOnInit(): void {
    this.route.queryParams.subscribe(params => {
      this.searchQuery = params['q'] || '';
      this.buscar();
    });
  }

  buscar(): void {
    this.loading.set(true);
    this.error.set(null);

    const filters: DocenteFilters = {
      q: this.searchQuery,
      estilo: this.selectedEstilo || undefined,
      dificultad: this.selectedDificultad || undefined
    };

    this.docenteService.getDocentes(filters).subscribe({
      next: (data) => {
        this.docentes.set(data);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err.message);
        this.loading.set(false);
        this.toast.error(err.message);
      }
    });
  }

  onSearchSubmit(): void {
    this.router.navigate(['/buscar'], { queryParams: { q: this.searchQuery } });
  }

  onFilterChange(): void {
    this.buscar();
  }

  limpiarFiltros(): void {
    this.selectedEstilo = '';
    this.selectedDificultad = '';
    this.buscar();
  }

  getTotalResultados(): number {
    return this.docentes().length;
  }

  getInitials(nombre: string): string {
    return nombre.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }

  getStars(rating: number): number[] {
    return Array(Math.floor(rating)).fill(0);
  }

  getEmptyStars(rating: number): number[] {
    return Array(5 - Math.ceil(rating)).fill(0);
  }
}