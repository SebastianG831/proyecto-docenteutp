import { Component, input, computed } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-estrellas',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="estrellas" [attr.aria-label]="ariaLabel()">
      <span class="star filled" *ngFor="let _ of filledStars(); let i = index" [style.--i]="i">★</span>
      <span class="star half" *ngIf="hasHalfStar()">★</span>
      <span class="star" *ngFor="let _ of emptyStars(); let i = index" [style.--i]="i">★</span>
    </div>
  `,
  styles: [`
    .estrellas {
      display: inline-flex;
      gap: 2px;
      color: #f5b81a;
      font-size: 16px;
      line-height: 1;
    }
    .star {
      display: inline-flex;
    }
    .star.filled {
      color: #f5b81a;
    }
    .star.half {
      position: relative;
      color: #e8d96a;
    }
    .star.half::after {
      content: '★';
      position: absolute;
      left: 0;
      color: #f5b81a;
      width: 50%;
      overflow: hidden;
    }
  `]
})
export class EstrellasComponent {
  readonly rating = input.required<number>();
  readonly max = input(5);
  readonly ariaLabel = input('');

  readonly filledStars = computed(() => Array(Math.floor(this.rating())).fill(0));
  readonly hasHalfStar = computed(() => this.rating() % 1 >= 0.5);
  readonly emptyStars = computed(() => Array(this.max() - Math.ceil(this.rating())).fill(0));
}