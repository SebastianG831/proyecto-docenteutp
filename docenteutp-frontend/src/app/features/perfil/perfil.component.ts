import { Component, OnInit, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { DocenteService } from '../../core/services/docente.service';
import { ResenaService } from '../../core/services/resena.service';
import { DocenteDetalleResponse, ResenaResponse, CriterioPromedioResponse } from '../../core/models/api.models';
import { formatearFecha, tiempoTranscurrido } from '../../core/utils/fechas';
import { ToastService } from '../../core/services/toast.service';
import { ModalResenaComponent } from '../../shared/components/modal-resena/modal-resena.component';
import { BarraCriterioComponent } from '../../shared/components/barra-criterio/barra-criterio.component';

@Component({
  selector: 'app-perfil',
  standalone: true,
  imports: [CommonModule, RouterLink, ModalResenaComponent, BarraCriterioComponent],
  templateUrl: './perfil.component.html',
  styleUrl: './perfil.component.scss',
})
export class PerfilComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private docenteService = inject(DocenteService);
  private resenaService = inject(ResenaService);
  private toast = inject(ToastService);

  docente = signal<DocenteDetalleResponse | null>(null);
  resenas = signal<ResenaResponse[]>([]);
  loading = signal(true);
  error = signal<string | null>(null);
  showResenaModal = signal(false);

  // Computed para criterios
  criterios = computed(() => this.docente()?.criterios || []);

  ngOnInit(): void {
    this.route.params.subscribe(params => {
      const id = Number(params['id']);
      if (id) {
        this.cargarDocente(id);
        this.cargarResenas(id);
      }
    });
  }

  cargarDocente(id: number): void {
    this.loading.set(true);
    this.error.set(null);

    this.docenteService.getDocenteById(id).subscribe({
      next: (data) => {
        this.docente.set(data);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err.message);
        this.loading.set(false);
        this.toast.error(err.message);
      }
    });
  }

  cargarResenas(docenteId: number): void {
    this.resenaService.getResenasByDocente(docenteId).subscribe({
      next: (data) => {
        // Filtrar solo reseñas aprobadas para mostrar en el perfil público
        this.resenas.set(data.filter(r => r.estado === 'APROBADA'));
      },
      error: (err) => {
        console.error('Error cargando reseñas:', err);
      }
    });
  }

  abrirModalResena(): void {
    this.showResenaModal.set(true);
  }

  cerrarModalResena(): void {
    this.showResenaModal.set(false);
  }

  onResenaEnviada(): void {
    this.cerrarModalResena();
    if (this.docente()) {
      this.cargarResenas(this.docente()!.id);
    }
    this.toast.success('Reseña enviada. Quedará pendiente de moderación.');
  }

  getPromedioCriterio(nombre: string): number {
    const criterio = this.criterios().find(c => c.criterio.toLowerCase().includes(nombre.toLowerCase()));
    return criterio?.promedio ?? 0;
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

  protected readonly formatearFecha = formatearFecha;
  protected readonly tiempoTranscurrido = tiempoTranscurrido;
}