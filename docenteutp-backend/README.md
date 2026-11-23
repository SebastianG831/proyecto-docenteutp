# DocenteUTP Backend (Node.js / Express / PostgreSQL)

API REST para la plataforma **DocenteUTP** (gestión de recomendaciones, evaluaciones verificadas y analítica B2B docente para la Universidad Tecnológica del Perú – Sede Lima Centro).

## Requisitos

- Node.js 20+
- PostgreSQL 14+ (para ejecución productiva)

## Configuración

1. Instala dependencias:
   ```bash
   npm install
   ```
2. Crea tu archivo `.env` a partir de `.env.example`:
   ```bash
   cp .env.example .env
   ```
   Configura `DATABASE_URL=postgresql://usuario:password@localhost:5432/docenteutpdb`.
3. Inicializa el esquema y los datos de prueba:
   ```bash
   npm run db:init
   ```
4. Inicia el servidor:
   ```bash
   npm run dev
   ```
   (O usa `npm run demo` para levantar una instancia temporal con PostgreSQL en memoria si aún no tienes una base externa configurada.)

## Pruebas

```bash
npm test
```

## Endpoints principales

- `GET /api/health`
- `POST /api/auth/registro` y `POST /api/auth/login`
- `GET /api/docentes` (`?q=&estilo=&dificultad=&sort=`) y `GET /api/docentes/:id`
- `GET /api/cursos` (`?q=`) y `GET /api/cursos/:id/docentes`
- `POST /api/resenas`, `GET /api/resenas/docente/:docenteId`, `GET /api/resenas/usuario/:usuarioId`, `DELETE /api/resenas/:id`
- `GET/POST/DELETE /api/guardados/usuario/:usuarioId...`
- `GET /api/admin/resenas/pendientes`, `PUT /api/admin/resenas/:id/aprobar|rechazar`, `GET /api/admin/reportes/docentes`, `GET/POST /api/admin/docentes`, `GET /api/admin/usuarios`
