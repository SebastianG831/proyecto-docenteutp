import { Component, input, computed } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-barra-criterio',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="barra-criterio">
      <div class="criterio-header">
        <span class="criterio-nombre">{{ nombre() }}</span>
        <span class="criterio-valor">{{ valor().toFixed(1) }}</span>
      </div>
      <div class="barra-container" role="progressbar" [attr.aria-valuenow]="valor()" aria-valuemin="0" aria-valuemax="5" [attr.aria-label]="'Criterio ' + nombre() + ': ' + valor().toFixed(1) + ' de 5'">
        <div class="barra-track">
          <div class="barra-fill" [style.width.%]="porcentaje()"></div>
        </div>
      </div>
      <div class="barra-estrellas" aria-hidden="true">
        <span class="star filled" *ngFor="let _ of filledStars()">★</span>
        <span class="star half" *ngIf="hasHalfStar()">★</span>
        <span class="star" *ngFor="let _ of emptyStars()">★</span>
      </div>
    </div>
  `,
  styles: [`
    .barra-criterio {
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .criterio-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .criterio-nombre {
      color: #52636d;
      font-size: 14px;
      font-weight: 500;
    }
    .criterio-valor {
      color: #2c3e50;
      font-size: 16px;
      font-weight: 700;
      font-family: 'Plus Jakarta Sans', sans-serif;
    }
    .barra-container {
      height: 8px;
      border-radius: 4px;
      background: #eef0ef;
      overflow: hidden;
    }
    .barra-track {
      height: 100%;
    }
    .barra-fill {
      height: 100%;
      border-radius: 4px;
      background: linear-gradient(90deg, #5b806c, #7ab88a);
      transition: width 0.5s ease-out;
    }
    .barra-estrellas {
      display: flex;
      gap: 3px;
      color: #e8d96a;
      font-size: 13px;
    }
    .barra-estrellas .star.filled {
      color: #f5b81a;
    }
    .barra-estrellas .star.half {
      position: relative;
      color: #e8d96a;
    }
    .barra-estrellas .star.half::after {
      content: '★';
      position: absolute;
      left: 0;
      color: #f5b81a;
      width: 50%;
      overflow: hidden;
    }
  `]
})
export class BarraCriterioComponent {
  readonly nombre = input.required<string>();
  readonly valor = input.required<number>();

  readonly porcentaje = computed(() => Math.min(100, (this.valor() / 5) * 100));
  readonly stars = computed(() => Array(5).fill(0));
  readonly filledStars = computed(() => Array(Math.floor(this.valor())).fill(0));
  readonly hasHalfStar = computed(() => this.valor() % 1 >= 0.5);
  readonly emptyStars = computed(() => Array(5 - Math.ceil(this.valor())).fill(0));
}