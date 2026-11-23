import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { createInMemoryPgPool } from '../src/demo.js';
import { closePool } from '../src/db/pool.js';

let app;

before(async () => {
  await createInMemoryPgPool();
  app = createApp();
});

after(async () => {
  await closePool();
});

describe('DocenteUTP REST API', () => {
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
        correo: 'u21209999@utp.edu.pe',
        password: 'password123',
        carrera: 'Ingeniería de Sistemas',
        ciclo: 5,
      });
    assert.equal(created.status, 201);
    assert.equal(created.body.rol, 'ESTUDIANTE');
    assert.ok(created.body.id > 5);
  });

  it('GET /api/docentes y /api/docentes/:id devuelven docentes, filtros y criterios', async () => {
    const all = await request(app).get('/api/docentes');
    assert.equal(all.status, 200);
    assert.equal(all.body.length, 6);

    const filtered = await request(app).get('/api/docentes?q=carlos&dificultad=MODERADO');
    assert.equal(filtered.status, 200);
    assert.equal(filtered.body.length, 1);
    assert.equal(filtered.body[0].nombre, 'Carlos Ramírez Salazar');

    const detail = await request(app).get('/api/docentes/1');
    assert.equal(detail.status, 200);
    assert.equal(detail.body.criterios.length, 3);
    assert.equal(detail.body.totalResenas, 3);
    assert.equal(detail.body.nivelDificultad, 'Moderado');
  });

  it('GET /api/cursos y /api/cursos/:id/docentes permiten comparar docentes', async () => {
    const cursos = await request(app).get('/api/cursos?q=SIS-201');
    assert.equal(cursos.status, 200);
    assert.equal(cursos.body.length, 1);

    const comp = await request(app).get('/api/cursos/1/docentes');
    assert.equal(comp.status, 200);
    assert.equal(comp.body.length, 2);
  });

  it('Flujo completo de reseñas, moderación admin y guardados', async () => {
    // Publicar nueva reseña (Ana Torres id=2 sobre docente 3, curso 1)
    const pub = await request(app).post('/api/resenas').send({
      usuarioId: 2,
      docenteId: 3,
      cursoId: 1,
      dominio: 5,
      claridad: 4,
      empatia: 3,
      dificultad: 'EXIGENTE',
      comentario: 'Explica rápido pero si repasas sus ejercicios de clase se aprende bastante.',
    });
    assert.equal(pub.status, 201);
    assert.equal(pub.body.estado, 'PENDIENTE');

    // Duplicado bloqueado
    const dup = await request(app).post('/api/resenas').send({
      usuarioId: 2,
      docenteId: 3,
      cursoId: 1,
      dominio: 5,
      claridad: 4,
      empatia: 3,
      dificultad: 'EXIGENTE',
      comentario: 'Intento de reseña duplicada para el mismo docente y curso en UTP.',
    });
    assert.equal(dup.status, 409);

    // Admin aprueba
    const pendientes = await request(app).get('/api/admin/resenas/pendientes');
    assert.equal(pendientes.status, 200);
    assert.ok(pendientes.body.some((r) => r.id === pub.body.id));

    const aprobar = await request(app).put(`/api/admin/resenas/${pub.body.id}/aprobar`);
    assert.equal(aprobar.status, 200);

    // Guardados
    const save = await request(app).post('/api/guardados/usuario/2/docente/1');
    assert.equal(save.status, 200);
    const savedList = await request(app).get('/api/guardados/usuario/2');
    assert.equal(savedList.status, 200);
    assert.equal(savedList.body.length, 1);

    const unsave = await request(app).delete('/api/guardados/usuario/2/docente/1');
    assert.equal(unsave.status, 200);

    // Reporte B2B
    const rep = await request(app).get('/api/admin/reportes/docentes');
    assert.equal(rep.status, 200);
    assert.equal(rep.body.length, 6);
  });
});
