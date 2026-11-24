import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-guardados',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './guardados.component.html',
  styleUrl: './guardados.component.scss',
})
export class GuardadosComponent {
  private auth = inject(AuthService);

  user = this.auth.user;

  getInitials(nombre: string | undefined): string {
    if (!nombre) return 'AM';
    return nombre.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  }
}