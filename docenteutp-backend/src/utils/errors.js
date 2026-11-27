export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

export function errorHandler(err, _req, res, _next) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ mensaje: err.message });
  }

  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ mensaje: 'JSON inválido en la solicitud' });
  }

  // PostgreSQL unique violation
  if (err?.code === '23505') {
    return res.status(409).json({ mensaje: 'Ese registro ya existe' });
  }

  // PostgreSQL foreign key violation
  if (err?.code === '23503') {
    return res.status(400).json({ mensaje: 'Referencia inválida a un recurso inexistente' });
  }

  console.error('Unhandled error:', err);
  return res.status(500).json({ mensaje: 'Error interno del servidor' });
}
