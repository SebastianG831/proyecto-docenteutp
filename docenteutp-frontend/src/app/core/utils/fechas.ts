export function formatearFecha(fechaISO: string): string {
  const fecha = new Date(fechaISO);
  return fecha.toLocaleDateString('es-PE', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });
}

export function formatearFechaCorta(fechaISO: string): string {
  const fecha = new Date(fechaISO);
  return fecha.toLocaleDateString('es-PE', {
    year: 'numeric',
    month: 'short',
    day: 'numeric'
  });
}

export function tiempoTranscurrido(fechaISO: string): string {
  const fecha = new Date(fechaISO);
  const ahora = new Date();
  const diffMs = ahora.getTime() - fecha.getTime();
  const diffDias = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffDias === 0) return 'Hoy';
  if (diffDias === 1) return 'Ayer';
  if (diffDias < 7) return `Hace ${diffDias} días`;
  if (diffDias < 30) return `Hace ${Math.floor(diffDias / 7)} semana${Math.floor(diffDias / 7) > 1 ? 's' : ''}`;
  if (diffDias < 365) return `Hace ${Math.floor(diffDias / 30)} mes${Math.floor(diffDias / 30) > 1 ? 'es' : ''}`;
  return `Hace ${Math.floor(diffDias / 365)} año${Math.floor(diffDias / 365) > 1 ? 's' : ''}`;
}