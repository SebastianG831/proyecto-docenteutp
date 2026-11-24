import { Component, input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-badge-verificado',
  standalone: true,
  imports: [CommonModule],
  template: `
    <span class="badge-verificado" *ngIf="verificado()" [attr.aria-label]="texto()">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M20 6L9 17l-5-5" />
      </svg>
      <span>{{ texto() }}</span>
    </span>
  `,
  styles: [`
    .badge-verificado {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 12px;
      border-radius: 8px;
      background: #e8f0ec;
      color: #5b806c;
      font-size: 13px;
      font-weight: 600;
      white-space: nowrap;
    }
  `]
})
export class BadgeVerificadoComponent {
  readonly verificado = input.required<boolean>();
  readonly texto = input('Verificado');
}