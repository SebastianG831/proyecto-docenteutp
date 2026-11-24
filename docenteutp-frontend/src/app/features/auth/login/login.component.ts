import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { ToastService } from '../../../core/services/toast.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './login.component.html',
  styleUrl: './login.component.scss',
})
export class LoginComponent {
  private auth = inject(AuthService);
  private router = inject(Router);
  private toast = inject(ToastService);

  email = '';
  password = '';
  loading = signal(false);
  error = signal<string | null>(null);

  canSubmit = computed(() => this.email.trim() && this.password.trim() && !this.loading());

  onSubmit(): void {
    if (!this.canSubmit()) return;

    this.loading.set(true);
    this.error.set(null);

    this.auth.login({ correo: this.email, password: this.password });
    this.loading.set(false);

    this.toast.success('Bienvenido, ' + this.auth.user()?.nombre);
    this.router.navigate(['/']);
  }
}