import { Injectable, signal, computed, inject } from '@angular/core';

export type ToastType = 'success' | 'error' | 'warning' | 'info';

export interface Toast {
  id: number;
  message: string;
  type: ToastType;
  duration?: number;
}

@Injectable({
  providedIn: 'root'
})
export class ToastService {
  private _toasts = signal<Toast[]>([]);
  private counter = 0;

  readonly toasts = this._toasts.asReadonly();

  show(message: string, type: ToastType = 'info', duration = 4000): number {
    const id = ++this.counter;
    const toast: Toast = { id, message, type, duration };
    this._toasts.update(t => [...t, toast]);

    if (duration > 0) {
      setTimeout(() => this.dismiss(id), duration);
    }
    return id;
  }

  success(message: string, duration = 4000): number {
    return this.show(message, 'success', duration);
  }

  error(message: string, duration = 6000): number {
    return this.show(message, 'error', duration);
  }

  warning(message: string, duration = 5000): number {
    return this.show(message, 'warning', duration);
  }

  info(message: string, duration = 4000): number {
    return this.show(message, 'info', duration);
  }

  dismiss(id: number): void {
    this._toasts.update(t => t.filter(toast => toast.id !== id));
  }

  clear(): void {
    this._toasts.set([]);
  }
}