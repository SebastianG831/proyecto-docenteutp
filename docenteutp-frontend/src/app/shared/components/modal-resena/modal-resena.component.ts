import { Component, input, output, signal, computed, inject, OnInit, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { DocenteDetalleResponse, CursoResponse, NivelDificultad } from '../../../core/models/api.models';
import { ResenaService } from '../../../core/services/resena.service';
import { ToastService } from '../../../core/services/toast.service';

@Component({
  selector: 'app-modal-resena',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './modal-resena.component.html',
  styleUrl: './modal-resena.component.scss',
})
export class ModalResenaComponent implements OnInit {
  private resenaService = inject(ResenaService);
  private toast = inject(ToastService);

  readonly docente = input.required<DocenteDetalleResponse>();
  readonly cerrar = output<void>();
  readonly enviado = output<void>();

  // Form state
  readonly selectedCurso = signal<CursoResponse | null>(null);
  readonly dominio = signal(3);
  readonly claridad = signal(3);
  readonly empatia = signal(3);
  readonly dificultad = signal<NivelDificultad>('MODERADO');
  readonly comentario = signal('');
  readonly submitting = signal(false);
  readonly errores = signal<Record<string, string>>({});

  // Computed
  readonly cursos = computed(() => this.docente().cursos || []);
  readonly canSubmit = computed(() => {
    const errs = this.errores();
    return this.selectedCurso() &&
           this.comentario().trim().length >= 30 &&
           this.comentario().trim().length <= 500 &&
           Object.keys(errs).length === 0 &&
           !this.submitting();
  });

  readonly comentarioLength = computed(() => this.comentario().trim().length);
  readonly comentarioValido = computed(() => this.comentarioLength() >= 30 && this.comentarioLength() <= 500);

  ngOnInit(): void {
    // Auto-seleccionar el primer curso si hay uno
    if (this.cursos().length > 0 && !this.selectedCurso()) {
      this.selectedCurso.set(this.cursos()[0]);
    }
  }

  onBackdropClick(event: MouseEvent): void {
    if (event.target === event.currentTarget) {
      this.cerrar.emit();
    }
  }

  setCurso(curso: CursoResponse): void {
    this.selectedCurso.set(curso);
  }

  setDificultad(d: NivelDificultad): void {
    this.dificultad.set(d);
  }

  setRating(criterio: 'dominio' | 'claridad' | 'empatia', value: number): void {
    if (criterio === 'dominio') this.dominio.set(value);
    else if (criterio === 'claridad') this.claridad.set(value);
    else this.empatia.set(value);
  }

  validateComentario(): void {
    const errors: Record<string, string> = {};
    const length = this.comentarioLength();
    if (length > 0 && length < 30) {
      errors['comentario'] = `Mínimo 30 caracteres (${length}/30)`;
    } else if (length > 500) {
      errors['comentario'] = `Máximo 500 caracteres (${length}/500)`;
    }
    this.errores.set(errors);
  }

  onComentarioChange(): void {
    this.validateComentario();
  }

  async onSubmit(): Promise<void> {
    if (!this.canSubmit()) return;

    this.submitting.set(true);
    this.errores.set({});

    try {
      await this.resenaService.crearResena({
        docenteId: this.docente().id,
        cursoId: this.selectedCurso()!.id,
        dominio: this.dominio(),
        claridad: this.claridad(),
        empatia: this.empatia(),
        dificultad: this.dificultad(),
        comentario: this.comentario().trim()
      }).subscribe({
        next: () => {
          this.submitting.set(false);
          this.enviado.emit();
        },
        error: (err) => {
          this.submitting.set(false);
          if (err.message.includes('ya existe') || err.message.includes('duplicate')) {
            this.errores.set({ general: 'Ya has reseñado este docente en este curso' });
          } else {
            this.toast.error(err.message);
          }
        }
      });
    } catch (err) {
      this.submitting.set(false);
    }
  }

  onCancel(): void {
    this.cerrar.emit();
  }

  getStarArray(): number[] {
    return [1, 2, 3, 4, 5];
  }

  protected readonly NivelDificultad = ['LIGERO', 'MODERADO', 'EXIGENTE'] as const;
}