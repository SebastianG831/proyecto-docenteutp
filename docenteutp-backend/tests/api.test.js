import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import 'dotenv/config';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { closePool, getPool, query } from '../src/db/pool.js';
import { initDatabase } from '../src/db/init.js';

let app;
const TEST_USER_EMAIL = 'u21209999@utp.edu.pe';

before(async () => {
  if (!process.env.DATABASE_URL) {
    process.env.DATABASE_URL = 'postgresql://dev:dev@localhost:5432/docenteutp_test';
  }
  const testDbUrl = process.env.TEST_DATABASE_URL || 'postgresql://dev:dev@localhost:5432/docenteutp_test';
  process.env.DATABASE_URL = testDbUrl;

  const pool = getPool();
  await initDatabase(pool);
  // Limpiar datos de pruebas previas idempotentes
  await query('DELETE FROM usuarios WHERE correo = $1', [TEST_USER_EMAIL]);
  await query(
    `DELETE FROM resenas
     WHERE usuario_id = (SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe')
       AND docente_id = (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe')
       AND curso_id = (SELECT id FROM cursos WHERE codigo = 'SIS-201')`
  );
  app = createApp();
});

after(async () => {
  await closePool();
});

describe('DocenteUTP REST API (PostgreSQL + ML)', () => {
  it('GET /api/health responde ok', async () => {
    const res = await request(app).get('/api/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
  });

  it('POST /api/auth/login valida credenciales seeded y rechaza incorrectas', async () => {
    const ok = await request(app)
      .post('/api/auth/login')
      .send({ correo: 'alumno1@utp.edu.pe', password: 'estudiante123' });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.rol, 'ESTUDIANTE');
    assert.equal(ok.body.nombre, 'Ana Torres');

    const admin = await request(app)
      .post('/api/auth/login')
      .send({ correo: 'admin@utp.edu.pe', password: 'admin1234' });
    assert.equal(admin.status, 200);
    assert.equal(admin.body.rol, 'ADMIN');

    const bad = await request(app)
      .post('/api/auth/login')
      .send({ correo: 'alumno1@utp.edu.pe', password: 'wrong' });
    assert.equal(bad.status, 401);
  });

  it('POST /api/auth/registro exige correo @utp.edu.pe y registra estudiante nuevo', async () => {
    const invalid = await request(app)
      .post('/api/auth/registro')
      .send({
        nombre: 'Luis Test',
        correo: 'luis@gmail.com',
        password: 'password123',
        carrera: 'Ingeniería de Sistemas',
        ciclo: 5,
      });
    assert.equal(invalid.status, 400);

    const created = await request(app)
      .post('/api/auth/registro')
      .send({
        nombre: 'Luis Test',
        correo: TEST_USER_EMAIL,
        password: 'password123',
        carrera: 'Ingeniería de Sistemas',
        ciclo: 5,
      });
    assert.equal(created.status, 201);
    assert.equal(created.body.rol, 'ESTUDIANTE');
    assert.ok(created.body.id > 0);
  });

  it('GET /api/docentes y /api/docentes/:id devuelven los 40 docentes, filtros y criterios', async () => {
    const all = await request(app).get('/api/docentes');
    assert.equal(all.status, 200);
    assert.equal(all.body.length, 40);

    const filtered = await request(app).get('/api/docentes?q=carlos&dificultad=MODERADO');
    assert.equal(filtered.status, 200);
    assert.ok(filtered.body.some((d) => d.nombre === 'Carlos Ramírez Salazar'));

    const carlos = filtered.body.find((d) => d.nombre === 'Carlos Ramírez Salazar');
    const detail = await request(app).get(`/api/docentes/${carlos.id}`);
    assert.equal(detail.status, 200);
    assert.equal(detail.body.criterios.length, 3);
    assert.equal(detail.body.criteriosExtendidos.length, 3);
    assert.ok(detail.body.totalResenas >= 10);
    assert.ok(detail.body.perfilMl);
  });

  it('GET /api/cursos y /api/cursos/:id/docentes permiten comparar docentes', async () => {
    const cursos = await request(app).get('/api/cursos?q=SIS-201');
    assert.equal(cursos.status, 200);
    assert.equal(cursos.body.length, 1);

    const comp = await request(app).get(`/api/cursos/${cursos.body[0].id}/docentes`);
    assert.equal(comp.status, 200);
    assert.ok(comp.body.length >= 2);
  });

  it('GET /api/estadisticas devuelve perfiles K-Means, Mean Shift, DBSCAN y métricas consumibles', async () => {
    const res = await request(app).get('/api/estadisticas');
    assert.equal(res.status, 200);
    assert.equal(res.body.resumen.totalDocentes, 40);
    assert.ok(res.body.resumen.totalResenasAprobadas >= 390);
    assert.equal(res.body.perfilesDocentes.kmeans.nClusters, 4);
    assert.equal(res.body.perfilesDocentes.meanshift.nClusters, 6);
    assert.equal(res.body.perfilesEstudiantes.nClusters, 3);
    assert.equal(res.body.mapaDocentes.length, 40);
    assert.equal(res.body.alertasCalidad.docentesAtipicos.length, 4);
    assert.ok(res.body.distribuciones.porSede.length === 3);
    assert.ok(res.body.distribuciones.porPeriodo.length === 3);
  });

  it('Flujo completo de reseñas, moderación admin con auditoría y guardados', async () => {
    const userRes = await query("SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'");
    const docRes = await query("SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'");
    const curRes = await query("SELECT id FROM cursos WHERE codigo = 'SIS-201'");
    const adminRes = await query("SELECT id FROM usuarios WHERE correo = 'admin@utp.edu.pe'");

    const usuarioId = userRes.rows[0].id;
    const docenteId = docRes.rows[0].id;
    const cursoId = curRes.rows[0].id;
    const adminId = adminRes.rows[0].id;

    // Publicar nueva reseña con campos extendidos
    const pub = await request(app).post('/api/resenas').send({
      usuarioId,
      docenteId,
      cursoId,
      dominio: 5,
      claridad: 4,
      empatia: 3,
      retroalimentacion: 4,
      organizacion: 5,
      puntualidad: 5,
      dificultad: 'EXIGENTE',
      horasEstudioSemanal: 8.5,
      recomienda: true,
      notaObtenida: 16.5,
      comentario: 'Explica rápido pero si repasas sus ejercicios de clase se aprende bastante.',
    });
    assert.equal(pub.status, 201);
    assert.equal(pub.body.estado, 'PENDIENTE');

    // Duplicado en el mismo periodo bloqueado
    const dup = await request(app).post('/api/resenas').send({
      usuarioId,
      docenteId,
      cursoId,
      dominio: 5,
      claridad: 4,
      empatia: 3,
      dificultad: 'EXIGENTE',
      comentario: 'Intento de reseña duplicada para el mismo docente y curso en UTP.',
    });
    assert.equal(dup.status, 409);

    // Admin aprueba y trigger guarda en moderacion_historial
    const pendientes = await request(app).get('/api/admin/resenas/pendientes');
    assert.equal(pendientes.status, 200);
    assert.ok(pendientes.body.some((r) => r.id === pub.body.id));

    const aprobar = await request(app)
      .put(`/api/admin/resenas/${pub.body.id}/aprobar`)
      .send({ adminId });
    assert.equal(aprobar.status, 200);

    const historial = await request(app).get('/api/admin/moderacion/historial');
    assert.equal(historial.status, 200);
    assert.ok(historial.body.some((h) => h.resenaId === pub.body.id && h.estadoNuevo === 'APROBADA'));

    // Reporte B2B
    const rep = await request(app).get('/api/admin/reportes/docentes');
    assert.equal(rep.status, 200);
    assert.equal(rep.body.length, 40);
  });
});
