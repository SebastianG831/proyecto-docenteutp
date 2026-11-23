# DocenteUTP

Plataforma web interactiva para la gestión de recomendaciones y evaluación docente en la **Universidad Tecnológica del Perú (UTP) – Sede Lima Centro**.

## Arquitectura

- **Backend (`docenteutp-backend/`)**: Node.js + Express + PostgreSQL (`pg`), con esquema SQL, datos iniciales (`sql/schema.sql`, `sql/seed.sql`) y pruebas de integración (`npm test`).
- **Frontend (`docenteutp-frontend/`)**: React + Vite + TypeScript, diseñado en base al prototipo validado en Figma y la rúbrica de 3 criterios (Dominio, Claridad, Empatía), comparador por curso, publicación verificada con correo `@utp.edu.pe` y panel B2B de moderación y analítica docente.

## Arranque rápido

### 1. Backend
```bash
cd docenteutp-backend
npm install
cp .env.example .env
# Configura DATABASE_URL en .env y ejecuta:
npm run db:init
npm run dev
```
> Para pruebas locales rápidas sin servidor PostgreSQL externo: `npm run demo`

### 2. Frontend
```bash
cd docenteutp-frontend
npm install
npm run dev
```

Abre `http://localhost:5173` en tu navegador.
