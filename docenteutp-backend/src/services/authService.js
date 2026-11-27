import bcrypt from 'bcryptjs';
import { query } from '../db/pool.js';
import { ApiError } from '../utils/errors.js';
import { validarEmailUtp } from '../utils/validators.js';

function mapAuthResponse(row) {
  return {
    id: Number(row.id),
    nombre: row.nombre,
    correo: row.correo,
    carrera: row.carrera,
    ciclo: Number(row.ciclo),
    rol: row.rol,
  };
}

export async function registrar({ nombre, correo, password, carrera, ciclo }) {
  if (typeof nombre !== 'string' || !nombre.trim()) {
    throw new ApiError(400, 'El nombre es obligatorio');
  }
  const correoNorm = validarEmailUtp(correo);
  if (typeof password !== 'string' || password.length < 8) {
    throw new ApiError(400, 'La contraseña debe tener al menos 8 caracteres');
  }
  if (typeof carrera !== 'string' || !carrera.trim()) {
    throw new ApiError(400, 'La carrera es obligatoria');
  }
  const cicloNum = Number(ciclo);
  if (!Number.isInteger(cicloNum) || cicloNum < 1 || cicloNum > 12) {
    throw new ApiError(400, 'El ciclo debe estar entre 1 y 12');
  }

  const existe = await query('SELECT id FROM usuarios WHERE correo = $1', [correoNorm]);
  if (existe.rows.length > 0) {
    throw new ApiError(409, 'Ese correo ya está registrado');
  }

  const carreraRes = await query(
    'SELECT id FROM carreras WHERE LOWER(nombre) = LOWER($1) LIMIT 1',
    [carrera.trim()]
  );
  const carreraId = carreraRes.rows[0]?.id ?? null;

  const sedeRes = await query(
    "SELECT id FROM sedes WHERE codigo = 'LIM-CTR' AND activo = TRUE LIMIT 1"
  );
  const sedeId = sedeRes.rows[0]?.id ?? null;

  const hash = await bcrypt.hash(password, 10);
  const res = await query(
    `INSERT INTO usuarios (nombre, correo, password, carrera_id, carrera, sede_id, ciclo, rol)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'ESTUDIANTE')
     RETURNING id, nombre, correo, carrera, ciclo, rol`,
    [nombre.trim(), correoNorm, hash, carreraId, carrera.trim(), sedeId, cicloNum]
  );

  return mapAuthResponse(res.rows[0]);
}

export async function login({ correo, password }) {
  if (typeof correo !== 'string' || !correo.trim() || typeof password !== 'string' || !password) {
    throw new ApiError(400, 'Correo y contraseña obligatorios');
  }
  const correoNorm = correo.trim().toLowerCase();
  const res = await query(
    'SELECT id, nombre, correo, password, carrera, ciclo, rol, activo FROM usuarios WHERE correo = $1',
    [correoNorm]
  );

  if (res.rows.length === 0 || res.rows[0].activo === false) {
    throw new ApiError(401, 'Correo o contraseña incorrectos');
  }

  const user = res.rows[0];
  const ok = await bcrypt.compare(password, user.password);
  if (!ok) {
    throw new ApiError(401, 'Correo o contraseña incorrectos');
  }

  return mapAuthResponse(user);
}

export async function listarUsuariosAdmin() {
  const res = await query(
    `SELECT u.id, u.nombre, u.correo, u.carrera, u.ciclo, u.rol, u.activo, u.creado_en,
            COUNT(r.id)::int AS total_resenas
     FROM usuarios u
     LEFT JOIN resenas r ON r.usuario_id = u.id
     GROUP BY u.id
     ORDER BY u.id ASC`
  );
  return res.rows.map((u) => ({
    id: Number(u.id),
    nombre: u.nombre,
    correo: u.correo,
    carrera: u.carrera,
    ciclo: Number(u.ciclo),
    rol: u.rol,
    activo: Boolean(u.activo),
    creadoEn: u.creado_en,
    totalResenas: Number(u.total_resenas),
  }));
}
