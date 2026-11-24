import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../../core/services/api.service';
import { ReporteDocenteResponse } from '../../../core/models/api.models';
import { ToastService } from '../../../core/services/toast.service';

@Component({
  selector: 'app-reportes',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './reportes.component.html',
  styleUrl: './reportes.component.scss',
})
export class ReportesComponent implements OnInit {
  private api = inject(ApiService);
  private toast = inject(ToastService);

  reportes = signal<ReporteDocenteResponse[]>([]);
  loading = signal(true);
  error = signal<string | null>(null);

  ngOnInit(): void {
    this.cargarReportes();
  }

  cargarReportes(): void {
    this.loading.set(true);
    this.error.set(null);

    this.api.get<ReporteDocenteResponse[]>('/admin/reportes/docentes').subscribe({
      next: (data) => {
        this.reportes.set(data);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err.message);
        this.loading.set(false);
        this.toast.error(err.message);
      }
    });
  }
}