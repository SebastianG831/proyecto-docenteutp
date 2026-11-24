import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { ToastService } from '../../../core/services/toast.service';

@Component({
  selector: 'app-registro',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './registro.component.html',
  styleUrl: './registro.component.scss',
})
export class RegistroComponent {
  private auth = inject(AuthService);
  private router = inject(Router);
  private toast = inject(ToastService);

  nombre = '';
  email = '';
  password = '';
  confirmPassword = '';
  carrera = '';
  ciclo = 1;
  loading = signal(false);
  error = signal<string | null>(null);

  carreras = [
    'Ingeniería de Sistemas',
    'Ingeniería de Software',
    'Ingeniería Industrial',
    'Ingeniería Civil',
    'Ingeniería Electrónica',
    'Ingeniería Mecánica',
    'Administración',
    'Contabilidad',
    'Derecho',
    'Psicología',
    'Comunicaciones',
    'Arquitectura',
    'Otra'
  ];

  canSubmit = computed(() =>
    this.nombre.trim() &&
    this.email.trim() &&
    this.password.length >= 6 &&
    this.password === this.confirmPassword &&
    this.carrera &&
    this.ciclo >= 1 &&
    this.ciclo <= 10 &&
    !this.loading()
  );

  onSubmit(): void {
    if (!this.canSubmit()) return;

    this.loading.set(true);
    this.error.set(null);

    this.auth.register({
      nombre: this.nombre,
      correo: this.email,
      password: this.password,
      carrera: this.carrera,
      ciclo: this.ciclo
    });
    this.loading.set(false);

    this.toast.success('Cuenta creada. Bienvenido, ' + this.auth.user()?.nombre);
    this.router.navigate(['/']);
  }
}