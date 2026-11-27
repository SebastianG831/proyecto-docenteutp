export function getInitials(nombre: string): string {
  if (!nombre) return 'UT';
  const words = nombre.trim().split(/\s+/);
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

export function formatRelativeDate(isoDate: string): string {
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return 'Reciente';
  const diffMs = Date.now() - date.getTime();
  const days = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
  if (days === 0) return 'Hoy';
  if (days === 1) return 'Hace 1 día';
  if (days < 7) return `Hace ${days} días`;
  const weeks = Math.floor(days / 7);
  if (weeks === 1) return 'Hace 1 semana';
  if (weeks < 5) return `Hace ${weeks} semanas`;
  const months = Math.floor(days / 30);
  if (months <= 1) return 'Hace 1 mes';
  return `Hace ${months} meses`;
}

export function formatDifficultyLabel(dificultad?: string): string {
  if (!dificultad) return 'Sin datos';
  const norm = dificultad.trim().toUpperCase();
  if (norm === 'LIGERO') return 'Ligero';
  if (norm === 'MODERADO') return 'Moderado';
  if (norm === 'EXIGENTE') return 'Exigente';
  return dificultad;
}

export function getDifficultyBadgeClass(dificultad?: string): string {
  const norm = (dificultad || '').trim().toUpperCase();
  if (norm === 'LIGERO') return 'badge-diff badge-diff-light';
  if (norm === 'EXIGENTE') return 'badge-diff badge-diff-hard';
  if (norm === 'MODERADO') return 'badge-diff badge-diff-mod';
  return 'badge-diff';
}
