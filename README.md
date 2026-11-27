# DocenteUTP

Plataforma web interactiva para la gestión de recomendaciones, analítica estudiantil y evaluación docente en la **Universidad Tecnológica del Perú (UTP)** (Lima Centro, Lima Norte y Arequipa).

## Arquitectura

- **Base de datos (`docenteutp-backend/sql/docenteutp_schema.sql`)**: PostgreSQL 15+ con modelo relacional normalizado, vistas operativas (`vw_docentes_resumen`), matrices ML (`vw_ml_docentes_features`, `vw_ml_resenas_features`, `vw_ml_usuarios_features`) y persistencia de clustering (`ml_experimentos`, `ml_clusters`, `ml_asignaciones`).
- **Pipeline ML (`docenteutp-ml/run_clustering.py`)**: Implementación unificada en Python + Scikit-Learn con **K-Means** (perfiles docentes y perfiles de estudiantes), **Mean Shift** (modos naturales) y **DBSCAN** (detección de docentes atípicos y reseñas spam/anómalas).
- **Backend (`docenteutp-backend/`)**: Node.js + Express + PostgreSQL (`pg`), con endpoints REST (`/api/auth`, `/api/docentes`, `/api/cursos`, `/api/resenas`, `/api/guardados`, `/api/estadisticas`, `/api/admin`) y pruebas de integración (`npm test`).
- **Frontend (`docenteutp-frontend/`)**: React + Vite + TypeScript con Explorador de Docentes, Comparador por Curso, Sitio de **Estadísticas Consumibles** (`/estadisticas`), Perfil de Docente, Publicación de Reseñas y Panel B2B de Coordinación/Moderación (`/admin`).

## Arranque rápido

### 1. Base de datos y pipeline ML
```bash
cd docenteutp-backend
npm install
cp .env.example .env
# Configura DATABASE_URL en .env y ejecuta:
npm run db:init
npm run ml:run
```

### 2. Backend
```bash
cd docenteutp-backend
npm run dev
```

### 3. Frontend
```bash
cd docenteutp-frontend
npm install
npm run dev
```

Abre `http://localhost:5173` en tu navegador.
