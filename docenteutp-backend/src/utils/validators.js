import { ApiError } from './errors.js';

const EMAIL_UTP_REGEX = /^[A-Za-z0-9._%+-]+@utp\.edu\.pe$/i;
export const DIFICULTADES_VALIDAS = new Set(['LIGERO', 'MODERADO', 'EXIGENTE']);

export function parsePositiveInt(value, fieldName = 'id') {
  const num = Number(value);
  if (!Number.isInteger(num) || num <= 0) {
    throw new ApiError(400, `${fieldName} inválido`);
  }
  return num;
}

export function validarEmailUtp(correo) {
  if (typeof correo !== 'string' || !correo.trim()) {
    throw new ApiError(400, 'El correo institucional es obligatorio');
  }
  const normalizado = correo.trim().toLowerCase();
  if (!EMAIL_UTP_REGEX.test(normalizado)) {
    throw new ApiError(400, 'Debes usar tu correo institucional @utp.edu.pe');
  }
  return normalizado;
}

export function validarRating(valor, campo) {
  const num = Number(valor);
  if (!Number.isInteger(num) || num < 1 || num > 5) {
    throw new ApiError(400, `${campo} debe ser un entero entre 1 y 5`);
  }
  return num;
}

export function validarDificultad(dificultad) {
  if (typeof dificultad !== 'string' || !DIFICULTADES_VALIDAS.has(dificultad.trim().toUpperCase())) {
    throw new ApiError(400, 'La dificultad debe ser LIGERO, MODERADO o EXIGENTE');
  }
  return dificultad.trim().toUpperCase();
}
