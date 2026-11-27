-- =============================================================================
-- DocenteUTP - Esquema PostgreSQL Completo + Datos Precargados (Producción + ML)
-- =============================================================================
-- Diseñado para:
--   1. Soportar y escalar el MVP Node.js/Express + React (catálogo, reseñas,
--      moderación con auditoría, comparador por curso, guardados, analítica B2B).
--   2. Garantizar integridad referencial estricta (oferta docente-curso en
--      reseñas, consistencia experimento-cluster en ML) e idempotencia total.
--   3. Habilitar la aplicación directa y sensata de clustering no supervisado:
--        - K-Means    -> Segmentación de perfiles docentes y perfiles de alumnos
--        - Mean Shift -> Descubrimiento automático de modos de enseñanza/evaluación
--        - DBSCAN     -> Detección de anomalías/outliers en docentes (polarización,
--                        carga extrema, desalineación) y en reseñas (spam / brigading)
--
-- Requisitos: PostgreSQL 15+ (por UNIQUE NULLS NOT DISTINCT)
-- Idempotente: Puede ejecutarse múltiples veces sin duplicar tablas ni datos.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. FUNCIONES AUXILIARES DE AUDITORÍA
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_set_actualizado_en()
RETURNS TRIGGER AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_marcar_moderado_en()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    NEW.moderado_en = NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_auditar_moderacion_resena()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO moderacion_historial (
      resena_id, admin_id, estado_anterior, estado_nuevo, observacion
    ) VALUES (
      NEW.id, NEW.moderado_por, OLD.estado, NEW.estado, NEW.motivo_rechazo
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 1. CATÁLOGOS ACADÉMICOS E INSTITUCIONALES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sedes (
  id SERIAL PRIMARY KEY,
  codigo VARCHAR(20) NOT NULL UNIQUE,
  nombre VARCHAR(150) NOT NULL UNIQUE,
  ciudad VARCHAR(80) NOT NULL DEFAULT 'Lima',
  activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS facultades (
  id SERIAL PRIMARY KEY,
  codigo VARCHAR(20) NOT NULL UNIQUE,
  nombre VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS carreras (
  id SERIAL PRIMARY KEY,
  facultad_id INTEGER NOT NULL REFERENCES facultades(id) ON DELETE RESTRICT,
  codigo VARCHAR(20) NOT NULL UNIQUE,
  nombre VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS periodos_academicos (
  id SERIAL PRIMARY KEY,
  codigo VARCHAR(20) NOT NULL UNIQUE, -- Ej: '2025-1', '2025-2', '2026-1'
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  es_actual BOOLEAN NOT NULL DEFAULT FALSE,
  CHECK (fecha_fin > fecha_inicio)
);

-- Garantiza que solo exista un periodo marcado como actual
CREATE UNIQUE INDEX IF NOT EXISTS uq_periodo_actual_unico
  ON periodos_academicos (es_actual)
  WHERE es_actual = TRUE;

CREATE TABLE IF NOT EXISTS cursos (
  id SERIAL PRIMARY KEY,
  carrera_id INTEGER REFERENCES carreras(id) ON DELETE SET NULL,
  codigo VARCHAR(20) NOT NULL UNIQUE,
  nombre VARCHAR(150) NOT NULL,
  creditos SMALLINT NOT NULL DEFAULT 4 CHECK (creditos BETWEEN 1 AND 10),
  ciclo_sugerido SMALLINT CHECK (ciclo_sugerido BETWEEN 1 AND 12),
  tipo VARCHAR(20) NOT NULL DEFAULT 'OBLIGATORIO'
    CHECK (tipo IN ('OBLIGATORIO', 'ELECTIVO', 'GENERAL')),
  activo BOOLEAN NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------------------------------
-- 2. USUARIOS (ESTUDIANTES, MODERADORES Y COORDINACIÓN ADMIN)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS usuarios (
  id SERIAL PRIMARY KEY,
  nombre VARCHAR(150) NOT NULL,
  correo VARCHAR(150) NOT NULL UNIQUE
    CHECK (correo ~* '^[A-Za-z0-9._%+-]+@utp\.edu\.pe$'),
  password VARCHAR(255) NOT NULL,
  carrera_id INTEGER REFERENCES carreras(id) ON DELETE RESTRICT,
  carrera VARCHAR(150) NOT NULL,
  sede_id INTEGER REFERENCES sedes(id) ON DELETE SET NULL,
  ciclo SMALLINT NOT NULL CHECK (ciclo BETWEEN 1 AND 12),
  rol VARCHAR(20) NOT NULL DEFAULT 'ESTUDIANTE'
    CHECK (rol IN ('ESTUDIANTE', 'MODERADOR', 'ADMIN')),
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_usuarios_actualizado_en ON usuarios;
CREATE TRIGGER trg_usuarios_actualizado_en
  BEFORE UPDATE ON usuarios
  FOR EACH ROW EXECUTE FUNCTION fn_set_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3. DOCENTES, OFERTA DE CURSOS Y ETIQUETAS NORMALIZADAS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS docentes (
  id SERIAL PRIMARY KEY,
  codigo_docente VARCHAR(30) UNIQUE,
  nombre VARCHAR(150) NOT NULL UNIQUE,
  facultad_id INTEGER REFERENCES facultades(id) ON DELETE RESTRICT,
  carrera_id INTEGER REFERENCES carreras(id) ON DELETE SET NULL,
  sede_id INTEGER REFERENCES sedes(id) ON DELETE RESTRICT,
  facultad VARCHAR(200) NOT NULL,
  sede VARCHAR(150) NOT NULL DEFAULT 'UTP Lima Centro · Edificio Arequipa',
  verificado BOOLEAN NOT NULL DEFAULT TRUE,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  estilo_ensenanza VARCHAR(100) NOT NULL,
  estilo_evaluacion VARCHAR(150) NOT NULL,
  modalidad_principal VARCHAR(20) NOT NULL DEFAULT 'PRESENCIAL'
    CHECK (modalidad_principal IN ('PRESENCIAL', 'VIRTUAL', 'SEMIPRESENCIAL')),
  anios_experiencia_utp SMALLINT NOT NULL DEFAULT 1 CHECK (anios_experiencia_utp >= 0),
  resumen VARCHAR(500),
  etiquetas VARCHAR(255), -- Resumen textual compatible con MVP; fuente normalizada en docente_etiqueta
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_docentes_actualizado_en ON docentes;
CREATE TRIGGER trg_docentes_actualizado_en
  BEFORE UPDATE ON docentes
  FOR EACH ROW EXECUTE FUNCTION fn_set_actualizado_en();

CREATE TABLE IF NOT EXISTS docente_curso (
  id SERIAL PRIMARY KEY,
  docente_id INTEGER NOT NULL REFERENCES docentes(id) ON DELETE CASCADE,
  curso_id INTEGER NOT NULL REFERENCES cursos(id) ON DELETE CASCADE,
  modalidad VARCHAR(20) NOT NULL DEFAULT 'PRESENCIAL'
    CHECK (modalidad IN ('PRESENCIAL', 'VIRTUAL', 'SEMIPRESENCIAL')),
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (docente_id, curso_id)
);

CREATE TABLE IF NOT EXISTS etiquetas (
  id SERIAL PRIMARY KEY,
  slug VARCHAR(60) NOT NULL UNIQUE,
  nombre VARCHAR(80) NOT NULL UNIQUE,
  categoria VARCHAR(20) NOT NULL DEFAULT 'METODOLOGIA'
    CHECK (categoria IN ('METODOLOGIA', 'EVALUACION', 'TRATO', 'CARGA'))
);

CREATE TABLE IF NOT EXISTS docente_etiqueta (
  docente_id INTEGER NOT NULL REFERENCES docentes(id) ON DELETE CASCADE,
  etiqueta_id INTEGER NOT NULL REFERENCES etiquetas(id) ON DELETE CASCADE,
  peso INTEGER NOT NULL DEFAULT 1 CHECK (peso >= 1),
  PRIMARY KEY (docente_id, etiqueta_id)
);

-- -----------------------------------------------------------------------------
-- 4. RESEÑAS, VOTOS DE UTILIDAD, REPORTES, AUDITORÍA Y GUARDADOS
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS resenas (
  id SERIAL PRIMARY KEY,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  docente_id INTEGER NOT NULL REFERENCES docentes(id) ON DELETE CASCADE,
  curso_id INTEGER NOT NULL REFERENCES cursos(id) ON DELETE CASCADE,
  periodo_id INTEGER REFERENCES periodos_academicos(id) ON DELETE SET NULL,

  -- Rúbrica principal del MVP (1 a 5)
  dominio SMALLINT NOT NULL CHECK (dominio BETWEEN 1 AND 5),
  claridad SMALLINT NOT NULL CHECK (claridad BETWEEN 1 AND 5),
  empatia SMALLINT NOT NULL CHECK (empatia BETWEEN 1 AND 5),

  -- Criterios complementarios para enriquecer el espacio de features ML
  retroalimentacion SMALLINT NOT NULL DEFAULT 3 CHECK (retroalimentacion BETWEEN 1 AND 5),
  organizacion SMALLINT NOT NULL DEFAULT 3 CHECK (organizacion BETWEEN 1 AND 5),
  puntualidad SMALLINT NOT NULL DEFAULT 4 CHECK (puntualidad BETWEEN 1 AND 5),

  -- Dificultad, carga académica y desempeño reportado
  dificultad VARCHAR(20) NOT NULL CHECK (dificultad IN ('LIGERO', 'MODERADO', 'EXIGENTE')),
  dificultad_num SMALLINT GENERATED ALWAYS AS (
    CASE dificultad
      WHEN 'LIGERO' THEN 1
      WHEN 'MODERADO' THEN 2
      WHEN 'EXIGENTE' THEN 3
    END
  ) STORED,
  horas_estudio_semanal NUMERIC(4,1) NOT NULL DEFAULT 4.0
    CHECK (horas_estudio_semanal BETWEEN 0.0 AND 40.0),
  recomienda BOOLEAN NOT NULL DEFAULT TRUE,
  asistencia_obligatoria BOOLEAN NOT NULL DEFAULT TRUE,
  nota_obtenida NUMERIC(4,2) CHECK (nota_obtenida BETWEEN 0.00 AND 20.00),

  -- Contenido textual y métricas derivadas
  comentario VARCHAR(500) NOT NULL CHECK (CHAR_LENGTH(BTRIM(comentario)) >= 30),
  longitud_comentario INTEGER GENERATED ALWAYS AS (CHAR_LENGTH(comentario)) STORED,
  calificacion_promedio NUMERIC(3,2) GENERATED ALWAYS AS (
    ROUND((dominio + claridad + empatia)::NUMERIC / 3.0, 2)
  ) STORED,
  calificacion_integral NUMERIC(3,2) GENERATED ALWAYS AS (
    ROUND((dominio + claridad + empatia + retroalimentacion + organizacion + puntualidad)::NUMERIC / 6.0, 2)
  ) STORED,

  -- Moderación y detección de anomalías
  estado VARCHAR(25) NOT NULL DEFAULT 'PENDIENTE'
    CHECK (estado IN ('PENDIENTE', 'APROBADA', 'RECHAZADA', 'MARCADA_ANOMALIA')),
  es_anomalia_ml BOOLEAN NOT NULL DEFAULT FALSE,
  moderado_en TIMESTAMPTZ,
  moderado_por INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  motivo_rechazo VARCHAR(255),
  fecha TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Integridad: el docente debe dictar efectivamente ese curso
  CONSTRAINT fk_resenas_docente_curso
    FOREIGN KEY (docente_id, curso_id)
    REFERENCES docente_curso(docente_id, curso_id)
    ON DELETE CASCADE,

  -- Una reseña por estudiante, docente, curso y periodo académico
  UNIQUE NULLS NOT DISTINCT (usuario_id, docente_id, curso_id, periodo_id)
);

CREATE TABLE IF NOT EXISTS moderacion_historial (
  id SERIAL PRIMARY KEY,
  resena_id INTEGER NOT NULL REFERENCES resenas(id) ON DELETE CASCADE,
  admin_id INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  estado_anterior VARCHAR(25) NOT NULL,
  estado_nuevo VARCHAR(25) NOT NULL,
  observacion VARCHAR(300),
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_resenas_marcar_moderado_en ON resenas;
CREATE TRIGGER trg_resenas_marcar_moderado_en
  BEFORE UPDATE ON resenas
  FOR EACH ROW EXECUTE FUNCTION fn_marcar_moderado_en();

DROP TRIGGER IF EXISTS trg_resenas_auditar_moderacion ON resenas;
CREATE TRIGGER trg_resenas_auditar_moderacion
  AFTER UPDATE ON resenas
  FOR EACH ROW EXECUTE FUNCTION fn_auditar_moderacion_resena();

CREATE TABLE IF NOT EXISTS resena_votos (
  id SERIAL PRIMARY KEY,
  resena_id INTEGER NOT NULL REFERENCES resenas(id) ON DELETE CASCADE,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  es_util BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (resena_id, usuario_id)
);

CREATE TABLE IF NOT EXISTS resena_reportes (
  id SERIAL PRIMARY KEY,
  resena_id INTEGER NOT NULL REFERENCES resenas(id) ON DELETE CASCADE,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  motivo VARCHAR(30) NOT NULL
    CHECK (motivo IN ('SPAM', 'LENGUAJE_OFENSIVO', 'INFORMACION_FALSA', 'DUPLICADO', 'OTRO')),
  detalle VARCHAR(300),
  resuelto BOOLEAN NOT NULL DEFAULT FALSE,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (resena_id, usuario_id)
);

CREATE TABLE IF NOT EXISTS docentes_guardados (
  id SERIAL PRIMARY KEY,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  docente_id INTEGER NOT NULL REFERENCES docentes(id) ON DELETE CASCADE,
  prioridad SMALLINT NOT NULL DEFAULT 1 CHECK (prioridad BETWEEN 1 AND 5),
  nota_personal VARCHAR(255),
  fecha TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (usuario_id, docente_id)
);

-- -----------------------------------------------------------------------------
-- 5. PERSISTENCIA DE MODELOS DE CLUSTERING (K-MEANS, DBSCAN, MEAN SHIFT)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ml_experimentos (
  id SERIAL PRIMARY KEY,
  nombre VARCHAR(120) NOT NULL UNIQUE,
  algoritmo VARCHAR(20) NOT NULL CHECK (algoritmo IN ('KMEANS', 'DBSCAN', 'MEAN_SHIFT')),
  entidad_objetivo VARCHAR(20) NOT NULL
    CHECK (entidad_objetivo IN ('DOCENTE', 'DOCENTE_CURSO', 'RESENA', 'USUARIO')),
  periodo_id INTEGER REFERENCES periodos_academicos(id) ON DELETE SET NULL,
  hiperparametros JSONB NOT NULL DEFAULT '{}'::jsonb,
  features_usadas TEXT[] NOT NULL,
  escalador VARCHAR(40) NOT NULL DEFAULT 'StandardScaler',
  n_muestras INTEGER NOT NULL CHECK (n_muestras >= 0),
  n_clusters_encontrados INTEGER NOT NULL CHECK (n_clusters_encontrados >= 0),
  n_outliers INTEGER NOT NULL DEFAULT 0 CHECK (n_outliers >= 0),
  silhouette_score DOUBLE PRECISION,
  davies_bouldin_score DOUBLE PRECISION,
  calinski_harabasz_score DOUBLE PRECISION,
  activo BOOLEAN NOT NULL DEFAULT FALSE,
  ejecutado_por INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  ejecutado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Máximo un experimento activo por (algoritmo, entidad_objetivo)
CREATE UNIQUE INDEX IF NOT EXISTS uq_ml_experimento_activo
  ON ml_experimentos (algoritmo, entidad_objetivo)
  WHERE activo = TRUE;

CREATE TABLE IF NOT EXISTS ml_clusters (
  id SERIAL PRIMARY KEY,
  experimento_id INTEGER NOT NULL REFERENCES ml_experimentos(id) ON DELETE CASCADE,
  cluster_label INTEGER NOT NULL, -- -1 reservado para ruido/outliers en DBSCAN
  etiqueta_negocio VARCHAR(120),
  descripcion TEXT,
  tamano INTEGER NOT NULL DEFAULT 0 CHECK (tamano >= 0),
  centroide_original JSONB NOT NULL DEFAULT '{}'::jsonb,
  centroide_escalado DOUBLE PRECISION[],
  radio_dispersion DOUBLE PRECISION,
  UNIQUE (experimento_id, cluster_label)
);

CREATE TABLE IF NOT EXISTS ml_asignaciones (
  id SERIAL PRIMARY KEY,
  experimento_id INTEGER NOT NULL REFERENCES ml_experimentos(id) ON DELETE CASCADE,
  cluster_label INTEGER NOT NULL,
  docente_id INTEGER REFERENCES docentes(id) ON DELETE CASCADE,
  curso_id INTEGER REFERENCES cursos(id) ON DELETE CASCADE,
  resena_id INTEGER REFERENCES resenas(id) ON DELETE CASCADE,
  usuario_id INTEGER REFERENCES usuarios(id) ON DELETE CASCADE,
  es_outlier BOOLEAN NOT NULL DEFAULT FALSE,
  distancia_centroide DOUBLE PRECISION,
  probabilidad_pertenencia DOUBLE PRECISION
    CHECK (probabilidad_pertenencia IS NULL OR (probabilidad_pertenencia BETWEEN 0.0 AND 1.0)),
  pca_x DOUBLE PRECISION,
  pca_y DOUBLE PRECISION,
  vector_features JSONB NOT NULL DEFAULT '{}'::jsonb,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Garantiza que el cluster asignado pertenece al mismo experimento
  CONSTRAINT fk_ml_asignaciones_cluster
    FOREIGN KEY (experimento_id, cluster_label)
    REFERENCES ml_clusters(experimento_id, cluster_label)
    ON DELETE CASCADE,

  -- Garantiza exactamente una entidad objetivo bien formada
  CONSTRAINT chk_ml_asignaciones_entidad CHECK (
    (docente_id IS NOT NULL AND curso_id IS NULL     AND resena_id IS NULL     AND usuario_id IS NULL) OR
    (docente_id IS NOT NULL AND curso_id IS NOT NULL AND resena_id IS NULL     AND usuario_id IS NULL) OR
    (docente_id IS NULL     AND curso_id IS NULL     AND resena_id IS NOT NULL AND usuario_id IS NULL) OR
    (docente_id IS NULL     AND curso_id IS NULL     AND resena_id IS NULL     AND usuario_id IS NOT NULL)
  )
);

-- Evita asignaciones duplicadas por entidad dentro de un mismo experimento
CREATE UNIQUE INDEX IF NOT EXISTS uq_ml_asig_docente
  ON ml_asignaciones (experimento_id, docente_id)
  WHERE docente_id IS NOT NULL AND curso_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ml_asig_docente_curso
  ON ml_asignaciones (experimento_id, docente_id, curso_id)
  WHERE docente_id IS NOT NULL AND curso_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ml_asig_resena
  ON ml_asignaciones (experimento_id, resena_id)
  WHERE resena_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_ml_asig_usuario
  ON ml_asignaciones (experimento_id, usuario_id)
  WHERE usuario_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 6. ÍNDICES DE RENDIMIENTO (CONSULTAS WEB Y EXTRACCIÓN ML)
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_usuarios_carrera_ciclo ON usuarios (carrera_id, ciclo);
CREATE INDEX IF NOT EXISTS idx_cursos_carrera ON cursos (carrera_id);
CREATE INDEX IF NOT EXISTS idx_cursos_codigo_lower ON cursos (LOWER(codigo));
CREATE INDEX IF NOT EXISTS idx_docentes_nombre_lower ON docentes (LOWER(nombre));
CREATE INDEX IF NOT EXISTS idx_docentes_facultad_estilo ON docentes (facultad_id, estilo_ensenanza);
CREATE INDEX IF NOT EXISTS idx_docentes_sede ON docentes (sede_id);
CREATE INDEX IF NOT EXISTS idx_docente_curso_curso ON docente_curso (curso_id, docente_id);

CREATE INDEX IF NOT EXISTS idx_resenas_docente_estado ON resenas (docente_id, estado, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_resenas_docente_curso_estado ON resenas (docente_id, curso_id, estado);
CREATE INDEX IF NOT EXISTS idx_resenas_usuario_fecha ON resenas (usuario_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_resenas_estado_fecha ON resenas (estado, fecha ASC);
CREATE INDEX IF NOT EXISTS idx_resenas_periodo ON resenas (periodo_id);
CREATE INDEX IF NOT EXISTS idx_resenas_anomalia ON resenas (es_anomalia_ml) WHERE es_anomalia_ml = TRUE;

CREATE INDEX IF NOT EXISTS idx_resena_votos_resena ON resena_votos (resena_id, es_util);
CREATE INDEX IF NOT EXISTS idx_resena_reportes_pendientes ON resena_reportes (resena_id) WHERE resuelto = FALSE;
CREATE INDEX IF NOT EXISTS idx_docentes_guardados_usuario ON docentes_guardados (usuario_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_docentes_guardados_docente ON docentes_guardados (docente_id);

CREATE INDEX IF NOT EXISTS idx_ml_asig_exp_cluster ON ml_asignaciones (experimento_id, cluster_label);
CREATE INDEX IF NOT EXISTS idx_ml_asig_outliers ON ml_asignaciones (experimento_id) WHERE es_outlier = TRUE;

-- -----------------------------------------------------------------------------
-- 7. VISTAS OPERATIVAS Y MATRICES DE FEATURES PARA K-MEANS, DBSCAN Y MEAN SHIFT
-- -----------------------------------------------------------------------------

-- 7.1 Vista operativa que reemplaza las consultas N+1 del backend Express
CREATE OR REPLACE VIEW vw_docentes_resumen AS
WITH stats_resenas AS (
  SELECT
    r.docente_id,
    COUNT(*) FILTER (WHERE r.estado = 'APROBADA')::INTEGER AS total_resenas,
    COUNT(*) FILTER (WHERE r.estado = 'PENDIENTE')::INTEGER AS resenas_pendientes,
    COALESCE(ROUND(AVG(r.dominio) FILTER (WHERE r.estado = 'APROBADA'), 2), 0.00) AS promedio_dominio,
    COALESCE(ROUND(AVG(r.claridad) FILTER (WHERE r.estado = 'APROBADA'), 2), 0.00) AS promedio_claridad,
    COALESCE(ROUND(AVG(r.empatia) FILTER (WHERE r.estado = 'APROBADA'), 2), 0.00) AS promedio_empatia,
    COALESCE(ROUND(AVG(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 1), 0.0) AS calificacion_general,
    COALESCE(ROUND(AVG(r.calificacion_integral) FILTER (WHERE r.estado = 'APROBADA'), 2), 0.00) AS calificacion_integral,
    MODE() WITHIN GROUP (ORDER BY r.dificultad) FILTER (WHERE r.estado = 'APROBADA') AS dificultad_predominante
  FROM resenas r
  GROUP BY r.docente_id
),
primer_curso AS (
  SELECT DISTINCT ON (dc.docente_id)
    dc.docente_id,
    c.nombre AS curso_principal
  FROM docente_curso dc
  JOIN cursos c ON c.id = dc.curso_id
  WHERE dc.activo = TRUE
  ORDER BY dc.docente_id, dc.id ASC
)
SELECT
  d.id,
  d.codigo_docente,
  d.nombre,
  d.facultad,
  d.sede,
  d.verificado,
  d.activo,
  d.estilo_ensenanza,
  d.estilo_evaluacion,
  d.modalidad_principal,
  d.resumen,
  d.etiquetas,
  COALESCE(pc.curso_principal, 'Sin curso asignado') AS curso_principal,
  COALESCE(sr.calificacion_general, 0.0) AS calificacion,
  COALESCE(sr.calificacion_integral, 0.00) AS calificacion_integral,
  COALESCE(sr.promedio_dominio, 0.00) AS promedio_dominio,
  COALESCE(sr.promedio_claridad, 0.00) AS promedio_claridad,
  COALESCE(sr.promedio_empatia, 0.00) AS promedio_empatia,
  COALESCE(sr.total_resenas, 0) AS total_resenas,
  COALESCE(sr.resenas_pendientes, 0) AS resenas_pendientes,
  COALESCE(sr.dificultad_predominante, 'SIN_DATOS') AS nivel_dificultad
FROM docentes d
LEFT JOIN stats_resenas sr ON sr.docente_id = d.id
LEFT JOIN primer_curso pc ON pc.docente_id = d.id;

-- 7.2 Matriz ML de Docentes (K-Means, Mean Shift y DBSCAN sobre perfiles docentes)
CREATE OR REPLACE VIEW vw_ml_docentes_features AS
WITH nota_global AS (
  SELECT COALESCE(AVG(nota_obtenida), 14.5)::DOUBLE PRECISION AS avg_global_nota
  FROM resenas
  WHERE estado = 'APROBADA' AND nota_obtenida IS NOT NULL
),
votos_por_resena AS (
  SELECT
    rv.resena_id,
    COUNT(*) FILTER (WHERE rv.es_util = TRUE)::INTEGER AS votos_utiles
  FROM resena_votos rv
  GROUP BY rv.resena_id
),
agg_resenas AS (
  SELECT
    r.docente_id,
    COUNT(*) FILTER (WHERE r.estado = 'APROBADA')::INTEGER AS total_resenas_aprobadas,
    COUNT(*) FILTER (WHERE r.estado = 'PENDIENTE')::INTEGER AS total_resenas_pendientes,
    COUNT(*) FILTER (WHERE r.estado = 'RECHAZADA')::INTEGER AS total_resenas_rechazadas,
    COUNT(*)::INTEGER AS total_resenas_brutas,

    COALESCE(AVG(r.dominio) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_dominio,
    COALESCE(AVG(r.claridad) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_claridad,
    COALESCE(AVG(r.empatia) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_empatia,
    COALESCE(AVG(r.retroalimentacion) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_retroalimentacion,
    COALESCE(AVG(r.organizacion) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_organizacion,
    COALESCE(AVG(r.puntualidad) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_puntualidad,
    COALESCE(AVG(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_general,
    COALESCE(AVG(r.calificacion_integral) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_integral,

    -- Dispersión y polarización de evaluaciones (clave para DBSCAN)
    COALESCE(STDDEV_POP(r.dominio) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS std_dominio,
    COALESCE(STDDEV_POP(r.claridad) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS std_claridad,
    COALESCE(STDDEV_POP(r.empatia) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS std_empatia,
    COALESCE(STDDEV_POP(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS indice_polarizacion,

    -- Dificultad continua [1.0..3.0] y proporciones descriptivas
    COALESCE(AVG(r.dificultad_num) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS dificultad_score,
    COALESCE(AVG(CASE WHEN r.dificultad = 'LIGERO' THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS pct_ligero,
    COALESCE(AVG(CASE WHEN r.dificultad = 'MODERADO' THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS pct_moderado,
    COALESCE(AVG(CASE WHEN r.dificultad = 'EXIGENTE' THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS pct_exigente,

    -- Carga académica, recomendación y desempeño
    COALESCE(AVG(r.horas_estudio_semanal) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_horas_estudio,
    COALESCE(AVG(CASE WHEN r.recomienda THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS tasa_recomendacion,
    AVG(r.nota_obtenida) FILTER (WHERE r.estado = 'APROBADA' AND r.nota_obtenida IS NOT NULL)::DOUBLE PRECISION AS avg_nota_raw,
    COALESCE(AVG(CASE WHEN r.nota_obtenida IS NOT NULL THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS pct_reporta_nota,
    COALESCE(AVG(r.longitud_comentario) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_longitud_comentario,
    COALESCE(AVG(COALESCE(v.votos_utiles, 0)) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_votos_utiles
  FROM resenas r
  LEFT JOIN votos_por_resena v ON v.resena_id = r.id
  GROUP BY r.docente_id
),
agg_guardados AS (
  SELECT docente_id, COUNT(*)::INTEGER AS total_guardados
  FROM docentes_guardados
  GROUP BY docente_id
),
agg_cursos AS (
  SELECT docente_id, COUNT(*)::INTEGER AS total_cursos
  FROM docente_curso
  WHERE activo = TRUE
  GROUP BY docente_id
)
SELECT
  d.id AS docente_id,
  d.nombre,
  d.facultad,
  d.sede,
  d.estilo_ensenanza,
  d.modalidad_principal,
  d.anios_experiencia_utp::INTEGER AS anios_experiencia_utp,

  COALESCE(ar.total_resenas_aprobadas, 0) AS total_resenas_aprobadas,
  COALESCE(ar.total_resenas_pendientes, 0) AS total_resenas_pendientes,
  COALESCE(ar.total_resenas_rechazadas, 0) AS total_resenas_rechazadas,
  COALESCE(ar.total_resenas_rechazadas::DOUBLE PRECISION / NULLIF(COALESCE(ar.total_resenas_brutas, 0), 0), 0.0)::DOUBLE PRECISION AS tasa_rechazo_bruta,
  COALESCE(ag.total_guardados, 0) AS total_guardados,
  COALESCE(ac.total_cursos, 0) AS total_cursos,
  COALESCE(ag.total_guardados::DOUBLE PRECISION / NULLIF(COALESCE(ar.total_resenas_aprobadas, 0), 0), 0.0)::DOUBLE PRECISION AS ratio_guardados_resena,

  COALESCE(ar.avg_dominio, 0.0) AS avg_dominio,
  COALESCE(ar.avg_claridad, 0.0) AS avg_claridad,
  COALESCE(ar.avg_empatia, 0.0) AS avg_empatia,
  COALESCE(ar.avg_retroalimentacion, 0.0) AS avg_retroalimentacion,
  COALESCE(ar.avg_organizacion, 0.0) AS avg_organizacion,
  COALESCE(ar.avg_puntualidad, 0.0) AS avg_puntualidad,
  COALESCE(ar.avg_general, 0.0) AS avg_general,
  COALESCE(ar.avg_integral, 0.0) AS avg_integral,

  COALESCE(ar.std_dominio, 0.0) AS std_dominio,
  COALESCE(ar.std_claridad, 0.0) AS std_claridad,
  COALESCE(ar.std_empatia, 0.0) AS std_empatia,
  COALESCE(ar.indice_polarizacion, 0.0) AS indice_polarizacion,

  COALESCE(ar.dificultad_score, 0.0) AS dificultad_score,
  COALESCE(ar.pct_ligero, 0.0) AS pct_ligero,
  COALESCE(ar.pct_moderado, 0.0) AS pct_moderado,
  COALESCE(ar.pct_exigente, 0.0) AS pct_exigente,
  COALESCE(ar.avg_horas_estudio, 0.0) AS avg_horas_estudio,
  COALESCE(ar.tasa_recomendacion, 0.0) AS tasa_recomendacion,
  COALESCE(ar.avg_nota_raw, ng.avg_global_nota) AS avg_nota_obtenida,
  COALESCE(ar.pct_reporta_nota, 0.0) AS pct_reporta_nota,
  COALESCE(ar.avg_longitud_comentario, 0.0) AS avg_longitud_comentario,
  COALESCE(ar.avg_votos_utiles, 0.0) AS avg_votos_utiles,

  (COALESCE(ar.total_resenas_aprobadas, 0) >= 3) AS tiene_suficientes_datos
FROM docentes d
CROSS JOIN nota_global ng
LEFT JOIN agg_resenas ar ON ar.docente_id = d.id
LEFT JOIN agg_guardados ag ON ag.docente_id = d.id
LEFT JOIN agg_cursos ac ON ac.docente_id = d.id
WHERE d.activo = TRUE;

-- 7.3 Matriz ML por par (Docente, Curso)
CREATE OR REPLACE VIEW vw_ml_docente_curso_features AS
WITH nota_global AS (
  SELECT COALESCE(AVG(nota_obtenida), 14.5)::DOUBLE PRECISION AS avg_global_nota
  FROM resenas
  WHERE estado = 'APROBADA' AND nota_obtenida IS NOT NULL
)
SELECT
  dc.docente_id,
  dc.curso_id,
  d.nombre AS docente_nombre,
  c.codigo AS curso_codigo,
  c.nombre AS curso_nombre,
  dc.modalidad,
  COUNT(r.id) FILTER (WHERE r.estado = 'APROBADA')::INTEGER AS total_resenas_aprobadas,
  COALESCE(AVG(r.dominio) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_dominio,
  COALESCE(AVG(r.claridad) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_claridad,
  COALESCE(AVG(r.empatia) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_empatia,
  COALESCE(AVG(r.retroalimentacion) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_retroalimentacion,
  COALESCE(AVG(r.organizacion) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_organizacion,
  COALESCE(AVG(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_general,
  COALESCE(AVG(r.calificacion_integral) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_integral,
  COALESCE(STDDEV_POP(r.calificacion_promedio) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS indice_polarizacion,
  COALESCE(AVG(r.dificultad_num) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS dificultad_score,
  COALESCE(AVG(r.horas_estudio_semanal) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS avg_horas_estudio,
  COALESCE(AVG(CASE WHEN r.recomienda THEN 1.0 ELSE 0.0 END) FILTER (WHERE r.estado = 'APROBADA'), 0.0)::DOUBLE PRECISION AS tasa_recomendacion,
  COALESCE(AVG(r.nota_obtenida) FILTER (WHERE r.estado = 'APROBADA' AND r.nota_obtenida IS NOT NULL), ng.avg_global_nota)::DOUBLE PRECISION AS avg_nota_obtenida,
  (COUNT(r.id) FILTER (WHERE r.estado = 'APROBADA') >= 3) AS tiene_suficientes_datos
FROM docente_curso dc
CROSS JOIN nota_global ng
JOIN docentes d ON d.id = dc.docente_id
JOIN cursos c ON c.id = dc.curso_id
LEFT JOIN resenas r ON r.docente_id = dc.docente_id AND r.curso_id = dc.curso_id
WHERE dc.activo = TRUE AND d.activo = TRUE
GROUP BY dc.docente_id, dc.curso_id, d.nombre, c.codigo, c.nombre, dc.modalidad, ng.avg_global_nota;

-- 7.4 Matriz ML de Reseñas (optimizada con ventanas nativas para DBSCAN de anomalías/spam)
CREATE OR REPLACE VIEW vw_ml_resenas_features AS
WITH docente_baseline AS (
  SELECT
    docente_id,
    COUNT(*)::INTEGER AS doc_n,
    SUM(calificacion_promedio)::DOUBLE PRECISION AS doc_sum,
    AVG(calificacion_promedio)::DOUBLE PRECISION AS doc_avg,
    COALESCE(NULLIF(STDDEV_POP(calificacion_promedio), 0.0), 0.5)::DOUBLE PRECISION AS doc_std
  FROM resenas
  WHERE estado = 'APROBADA'
  GROUP BY docente_id
),
usuario_baseline AS (
  SELECT
    usuario_id,
    AVG(calificacion_promedio)::DOUBLE PRECISION AS usr_avg
  FROM resenas
  GROUP BY usuario_id
),
votos_resena AS (
  SELECT
    resena_id,
    COUNT(*) FILTER (WHERE es_util = TRUE)::INTEGER AS votos_utiles
  FROM resena_votos
  GROUP BY resena_id
),
reportes_resena AS (
  SELECT
    resena_id,
    COUNT(*)::INTEGER AS total_reportes
  FROM resena_reportes
  GROUP BY resena_id
),
rafaga_24h AS (
  SELECT
    id AS resena_id,
    COUNT(*) OVER (
      PARTITION BY usuario_id
      ORDER BY fecha
      RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND INTERVAL '24 hours' FOLLOWING
    )::INTEGER AS resenas_usuario_24h
  FROM resenas
)
SELECT
  r.id AS resena_id,
  r.docente_id,
  r.curso_id,
  r.usuario_id,
  r.estado,
  u.ciclo::INTEGER AS usuario_ciclo,
  r.dominio::DOUBLE PRECISION AS dominio,
  r.claridad::DOUBLE PRECISION AS claridad,
  r.empatia::DOUBLE PRECISION AS empatia,
  r.retroalimentacion::DOUBLE PRECISION AS retroalimentacion,
  r.organizacion::DOUBLE PRECISION AS organizacion,
  r.puntualidad::DOUBLE PRECISION AS puntualidad,
  r.calificacion_promedio::DOUBLE PRECISION AS calificacion_promedio,
  r.calificacion_integral::DOUBLE PRECISION AS calificacion_integral,
  r.dificultad_num::DOUBLE PRECISION AS dificultad_num,
  r.horas_estudio_semanal::DOUBLE PRECISION AS horas_estudio_semanal,
  r.longitud_comentario::DOUBLE PRECISION AS longitud_comentario,
  (
    GREATEST(r.dominio, r.claridad, r.empatia, r.retroalimentacion, r.organizacion, r.puntualidad)
    - LEAST(r.dominio, r.claridad, r.empatia, r.retroalimentacion, r.organizacion, r.puntualidad)
  )::DOUBLE PRECISION AS rango_interno_rubrica,
  COALESCE(
    LENGTH(REGEXP_REPLACE(r.comentario, '[^A-ZÁÉÍÓÚÑ]', '', 'g'))::DOUBLE PRECISION
    / NULLIF(LENGTH(REGEXP_REPLACE(r.comentario, '[^A-Za-zÁÉÍÓÚáéíóúÑñ]', '', 'g')), 0),
    0.0
  )::DOUBLE PRECISION AS ratio_mayusculas,
  COALESCE(vr.votos_utiles, 0)::INTEGER AS votos_utiles,
  COALESCE(rr.total_reportes, 0)::INTEGER AS total_reportes,

  -- Desviación Leave-One-Out respecto al consenso del docente
  COALESCE(
    ABS(
      r.calificacion_promedio::DOUBLE PRECISION -
      CASE
        WHEN r.estado = 'APROBADA' AND db.doc_n > 1
          THEN (db.doc_sum - r.calificacion_promedio::DOUBLE PRECISION) / (db.doc_n - 1)
        ELSE db.doc_avg
      END
    ),
    0.0
  )::DOUBLE PRECISION AS desviacion_abs_vs_docente,

  COALESCE(
    (
      r.calificacion_promedio::DOUBLE PRECISION -
      CASE
        WHEN r.estado = 'APROBADA' AND db.doc_n > 1
          THEN (db.doc_sum - r.calificacion_promedio::DOUBLE PRECISION) / (db.doc_n - 1)
        ELSE db.doc_avg
      END
    ) / db.doc_std,
    0.0
  )::DOUBLE PRECISION AS zscore_vs_docente,

  COALESCE(ABS(r.calificacion_promedio::DOUBLE PRECISION - ub.usr_avg), 0.0)::DOUBLE PRECISION AS desviacion_abs_vs_usuario,
  rf.resenas_usuario_24h,
  (EXTRACT(EPOCH FROM (NOW() - r.fecha)) / 86400.0)::DOUBLE PRECISION AS antiguedad_dias
FROM resenas r
JOIN usuarios u ON u.id = r.usuario_id
JOIN rafaga_24h rf ON rf.resena_id = r.id
LEFT JOIN docente_baseline db ON db.docente_id = r.docente_id
LEFT JOIN usuario_baseline ub ON ub.usuario_id = r.usuario_id
LEFT JOIN votos_resena vr ON vr.resena_id = r.id
LEFT JOIN reportes_resena rr ON rr.resena_id = r.id;

-- 7.5 Matriz ML de Estudiantes (K-Means / Mean Shift / DBSCAN de perfiles de alumno)
CREATE OR REPLACE VIEW vw_ml_usuarios_features AS
WITH agg_res AS (
  SELECT
    r.usuario_id,
    COUNT(*)::INTEGER AS total_resenas,
    COALESCE(AVG(r.dominio), 0.0)::DOUBLE PRECISION AS avg_dominio_dado,
    COALESCE(AVG(r.claridad), 0.0)::DOUBLE PRECISION AS avg_claridad_dada,
    COALESCE(AVG(r.empatia), 0.0)::DOUBLE PRECISION AS avg_empatia_dada,
    COALESCE(AVG(r.calificacion_promedio), 0.0)::DOUBLE PRECISION AS avg_calificacion_dada,
    COALESCE(STDDEV_POP(r.calificacion_promedio), 0.0)::DOUBLE PRECISION AS std_calificacion_dada,
    COALESCE(AVG(r.dificultad_num), 0.0)::DOUBLE PRECISION AS avg_dificultad_dada,
    COALESCE(AVG(r.horas_estudio_semanal), 0.0)::DOUBLE PRECISION AS avg_horas_reportadas,
    COALESCE(AVG(CASE WHEN r.recomienda THEN 1.0 ELSE 0.0 END), 0.0)::DOUBLE PRECISION AS tasa_recomendacion_dada,
    COALESCE(AVG(r.longitud_comentario), 0.0)::DOUBLE PRECISION AS avg_longitud_comentario,
    COALESCE(AVG(CASE WHEN r.estado = 'RECHAZADA' THEN 1.0 ELSE 0.0 END), 0.0)::DOUBLE PRECISION AS tasa_resenas_rechazadas
  FROM resenas r
  GROUP BY r.usuario_id
),
agg_guard AS (
  SELECT usuario_id, COUNT(*)::INTEGER AS total_guardados
  FROM docentes_guardados
  GROUP BY usuario_id
),
agg_votos AS (
  SELECT usuario_id, COUNT(*)::INTEGER AS total_votos_emitidos
  FROM resena_votos
  GROUP BY usuario_id
),
agg_reportes_recibidos AS (
  SELECT r.usuario_id, COUNT(rep.id)::INTEGER AS total_reportes_recibidos
  FROM resenas r
  JOIN resena_reportes rep ON rep.resena_id = r.id
  GROUP BY r.usuario_id
)
SELECT
  u.id AS usuario_id,
  u.carrera,
  u.ciclo::INTEGER AS ciclo,
  COALESCE(ar.total_resenas, 0) AS total_resenas,
  COALESCE(ag.total_guardados, 0) AS total_guardados,
  COALESCE(av.total_votos_emitidos, 0) AS total_votos_emitidos,
  COALESCE(arr.total_reportes_recibidos, 0) AS total_reportes_recibidos,
  COALESCE(ar.avg_dominio_dado, 0.0) AS avg_dominio_dado,
  COALESCE(ar.avg_claridad_dada, 0.0) AS avg_claridad_dada,
  COALESCE(ar.avg_empatia_dada, 0.0) AS avg_empatia_dada,
  COALESCE(ar.avg_calificacion_dada, 0.0) AS avg_calificacion_dada,
  COALESCE(ar.std_calificacion_dada, 0.0) AS std_calificacion_dada,
  COALESCE(ar.avg_dificultad_dada, 0.0) AS avg_dificultad_dada,
  COALESCE(ar.avg_horas_reportadas, 0.0) AS avg_horas_reportadas,
  COALESCE(ar.tasa_recomendacion_dada, 0.0) AS tasa_recomendacion_dada,
  COALESCE(ar.avg_longitud_comentario, 0.0) AS avg_longitud_comentario,
  COALESCE(ar.tasa_resenas_rechazadas, 0.0) AS tasa_resenas_rechazadas,
  (COALESCE(ar.total_resenas, 0) >= 2) AS tiene_actividad
FROM usuarios u
LEFT JOIN agg_res ar ON ar.usuario_id = u.id
LEFT JOIN agg_guard ag ON ag.usuario_id = u.id
LEFT JOIN agg_votos av ON av.usuario_id = u.id
LEFT JOIN agg_reportes_recibidos arr ON arr.usuario_id = u.id
WHERE u.rol = 'ESTUDIANTE' AND u.activo = TRUE;

-- 7.6 Vistas de consumo rápido para Backend Node.js / Admin UI
CREATE OR REPLACE VIEW vw_docentes_clusters_activos AS
SELECT
  e.algoritmo,
  e.id AS experimento_id,
  e.nombre AS experimento_nombre,
  e.silhouette_score,
  a.docente_id,
  d.nombre AS docente_nombre,
  a.cluster_label,
  c.etiqueta_negocio,
  a.es_outlier,
  a.distancia_centroide,
  a.pca_x,
  a.pca_y,
  e.ejecutado_en
FROM ml_asignaciones a
JOIN ml_experimentos e ON e.id = a.experimento_id
JOIN docentes d ON d.id = a.docente_id
JOIN ml_clusters c ON c.experimento_id = a.experimento_id AND c.cluster_label = a.cluster_label
WHERE e.activo = TRUE
  AND e.entidad_objetivo = 'DOCENTE';

CREATE OR REPLACE VIEW vw_resenas_anomalias_activas AS
SELECT
  e.algoritmo,
  e.id AS experimento_id,
  a.resena_id,
  r.docente_id,
  d.nombre AS docente_nombre,
  r.usuario_id,
  u.correo AS usuario_correo,
  r.estado,
  r.calificacion_promedio,
  r.comentario,
  a.cluster_label,
  a.es_outlier,
  a.distancia_centroide,
  e.ejecutado_en
FROM ml_asignaciones a
JOIN ml_experimentos e ON e.id = a.experimento_id
JOIN resenas r ON r.id = a.resena_id
JOIN docentes d ON d.id = r.docente_id
JOIN usuarios u ON u.id = r.usuario_id
WHERE e.activo = TRUE
  AND e.entidad_objetivo = 'RESENA'
  AND a.es_outlier = TRUE;

-- -----------------------------------------------------------------------------
-- 8. DATOS PRECARGADOS (IDEMPOTENTES) PARA OPERACIÓN Y CLUSTERING ML
-- -----------------------------------------------------------------------------
-- Incluye:
--   * 3 sedes, 3 facultades, 6 carreras, 3 periodos académicos, 14 cursos, 12 etiquetas
--   * 52 usuarios (admin, moderador + 50 estudiantes en 3 perfiles + 2 cuentas spam)
--   * 40 docentes distribuidos en 4 arquetipos bien definidos + 4 outliers para DBSCAN
--   * 67 asignaciones docente-curso y >430 reseñas realistas (incluyendo anomalías diversas)
--   * Votos de utilidad, reportes de abuso, historial de moderación y guardados
-- -----------------------------------------------------------------------------

-- 8.1 Sedes, Facultades, Carreras y Periodos Académicos
INSERT INTO sedes (codigo, nombre, ciudad) VALUES
  ('LIM-CTR', 'UTP Lima Centro · Edificio Arequipa', 'Lima'),
  ('LIM-NOR', 'UTP Lima Norte · Panamericana Norte', 'Lima'),
  ('AQP-CTR', 'UTP Arequipa · Av. Parra', 'Arequipa')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO facultades (codigo, nombre) VALUES
  ('FING', 'Facultad de Ingeniería'),
  ('FNEG', 'Facultad de Negocios'),
  ('FDCH', 'Facultad de Derecho y Ciencias Humanas')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO carreras (facultad_id, codigo, nombre) VALUES
  ((SELECT id FROM facultades WHERE codigo = 'FING'), 'ISI', 'Ingeniería de Sistemas'),
  ((SELECT id FROM facultades WHERE codigo = 'FING'), 'ISW', 'Ingeniería de Software'),
  ((SELECT id FROM facultades WHERE codigo = 'FING'), 'IIN', 'Ingeniería Industrial'),
  ((SELECT id FROM facultades WHERE codigo = 'FING'), 'ICV', 'Ingeniería Civil'),
  ((SELECT id FROM facultades WHERE codigo = 'FNEG'), 'ADM', 'Administración de Empresas'),
  ((SELECT id FROM facultades WHERE codigo = 'FDCH'), 'PSI', 'Psicología')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO periodos_academicos (codigo, fecha_inicio, fecha_fin, es_actual) VALUES
  ('2025-1', '2025-03-17', '2025-07-19', FALSE),
  ('2025-2', '2025-08-18', '2025-12-20', FALSE),
  ('2026-1', '2026-03-16', '2026-07-18', TRUE)
ON CONFLICT (codigo) DO NOTHING;

-- 8.2 Cursos (conserva los 4 del MVP y añade 10 cursos adicionales UTP)
INSERT INTO cursos (carrera_id, codigo, nombre, creditos, ciclo_sugerido, tipo) VALUES
  ((SELECT id FROM carreras WHERE codigo = 'ISI'), 'SIS-201', 'Algoritmos y Estructuras de Datos', 4, 3, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'IIN'), 'MAT-101', 'Cálculo I', 4, 1, 'GENERAL'),
  ((SELECT id FROM carreras WHERE codigo = 'ISI'), 'SIS-301', 'Base de Datos', 4, 5, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'ISW'), 'SOF-401', 'Desarrollo Web Integrado', 4, 7, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'ISI'), 'SIS-101', 'Introducción a la Programación', 4, 1, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'IIN'), 'MAT-102', 'Cálculo II', 4, 2, 'GENERAL'),
  ((SELECT id FROM carreras WHERE codigo = 'IIN'), 'IND-201', 'Estadística Inferencial', 4, 4, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'IIN'), 'IND-305', 'Investigación de Operaciones', 4, 6, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'ISW'), 'SOF-302', 'Arquitectura de Software', 4, 6, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'ISI'), 'SIS-402', 'Inteligencia Artificial', 4, 8, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'ISI'), 'SIS-501', 'Machine Learning Aplicado', 4, 9, 'ELECTIVO'),
  ((SELECT id FROM carreras WHERE codigo = 'ICV'), 'CIV-202', 'Mecánica de Materiales', 4, 4, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'ADM'), 'ADM-201', 'Gestión de Proyectos', 3, 5, 'OBLIGATORIO'),
  ((SELECT id FROM carreras WHERE codigo = 'PSI'), 'PSI-101', 'Psicología Organizacional', 3, 3, 'OBLIGATORIO')
ON CONFLICT (codigo) DO NOTHING;

-- 8.3 Etiquetas normalizadas
INSERT INTO etiquetas (slug, nombre, categoria) VALUES
  ('metodologia-clara', 'Metodología clara', 'METODOLOGIA'),
  ('practica-semanal', 'Práctica semanal', 'EVALUACION'),
  ('evaluacion-continua', 'Evaluación continua', 'EVALUACION'),
  ('accesible', 'Accesible', 'TRATO'),
  ('alto-nivel-exigencia', 'Alto nivel de exigencia', 'CARGA'),
  ('dominio-del-tema', 'Dominio del tema', 'METODOLOGIA'),
  ('explicacion-dinamica', 'Explicación dinámica', 'METODOLOGIA'),
  ('ejemplos-reales', 'Ejemplos reales', 'METODOLOGIA'),
  ('laboratorios-guiados', 'Laboratorios guiados', 'EVALUACION'),
  ('aprendizaje-por-proyecto', 'Aprendizaje por proyecto', 'EVALUACION'),
  ('retroalimentacion', 'Retroalimentación', 'TRATO'),
  ('clases-desorganizadas', 'Clases desorganizadas', 'CARGA')
ON CONFLICT (slug) DO NOTHING;

-- 8.4 Usuarios (admin, moderador + 50 estudiantes UTP)
INSERT INTO usuarios (nombre, correo, password, carrera_id, carrera, sede_id, ciclo, rol) VALUES
  ('Coordinación Académica', 'admin@utp.edu.pe', '$2a$10$n/ROWDM17JXpydYh1mNeuualIcai5ShrOBQvhITi9f/4rkcbwFIp6', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ADMIN'),
  ('Moderación UTP', 'moderador@utp.edu.pe', '$2a$10$n/ROWDM17JXpydYh1mNeuualIcai5ShrOBQvhITi9f/4rkcbwFIp6', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'MODERADOR'),
  ('Ana Torres', 'alumno1@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 5, 'ESTUDIANTE'),
  ('Diego Rojas', 'alumno2@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 6, 'ESTUDIANTE'),
  ('Camila Flores', 'alumno3@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 2, 'ESTUDIANTE'),
  ('Mateo Castro', 'alumno4@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 9, 'ESTUDIANTE'),
  ('Sofía Gutiérrez', 'alumno5@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ESTUDIANTE'),
  ('Sebastián Vargas', 'alumno6@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ESTUDIANTE'),
  ('Valeria Chávez', 'alumno7@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 2, 'ESTUDIANTE'),
  ('Alejandro Paredes', 'alumno8@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 1, 'ESTUDIANTE'),
  ('Lucía Salazar', 'alumno9@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ESTUDIANTE'),
  ('Gabriel Quispe', 'alumno10@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ICV'), 'Ingeniería Civil', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ESTUDIANTE'),
  ('Martina Mendoza', 'alumno11@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 1, 'ESTUDIANTE'),
  ('Daniel Herrera', 'alumno12@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 1, 'ESTUDIANTE'),
  ('Paula Ramos', 'alumno13@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 2, 'ESTUDIANTE'),
  ('Nicolás Flores', 'alumno14@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ESTUDIANTE'),
  ('Fernanda Cruz', 'alumno15@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 1, 'ESTUDIANTE'),
  ('Rodrigo Morales', 'alumno16@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ICV'), 'Ingeniería Civil', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 1, 'ESTUDIANTE'),
  ('Andrea Ortiz', 'alumno17@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ESTUDIANTE'),
  ('Joaquín Delgado', 'alumno18@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 1, 'ESTUDIANTE'),
  ('Isabella Castillo', 'alumno19@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 1, 'ESTUDIANTE'),
  ('Adrián Navarro', 'alumno20@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 1, 'ESTUDIANTE'),
  ('Mariana Ríos', 'alumno21@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 6, 'ESTUDIANTE'),
  ('Bruno Silva', 'alumno22@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ICV'), 'Ingeniería Civil', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 5, 'ESTUDIANTE'),
  ('Renata Aguilar', 'alumno23@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 6, 'ESTUDIANTE'),
  ('Emilio Campos', 'alumno24@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 6, 'ESTUDIANTE'),
  ('Claudia Vega', 'alumno25@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 5, 'ESTUDIANTE'),
  ('Mauricio Medina', 'alumno26@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 5, 'ESTUDIANTE'),
  ('Natalia Romero', 'alumno27@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 6, 'ESTUDIANTE'),
  ('Esteban Sánchez', 'alumno28@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ICV'), 'Ingeniería Civil', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 6, 'ESTUDIANTE'),
  ('Karla León', 'alumno29@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 6, 'ESTUDIANTE'),
  ('Alonso Espinoza', 'alumno30@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 5, 'ESTUDIANTE'),
  ('Ximena Peña', 'alumno31@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 5, 'ESTUDIANTE'),
  ('Franco Cabrera', 'alumno32@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 6, 'ESTUDIANTE'),
  ('Mónica Núñez', 'alumno33@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 5, 'ESTUDIANTE'),
  ('Ignacio Guzmán', 'alumno34@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ICV'), 'Ingeniería Civil', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 5, 'ESTUDIANTE'),
  ('Jimena Huamán', 'alumno35@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 6, 'ESTUDIANTE'),
  ('Fabián Cárdenas', 'alumno36@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 5, 'ESTUDIANTE'),
  ('Bianca Pacheco', 'alumno37@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 10, 'ESTUDIANTE'),
  ('César Lozano', 'alumno38@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 10, 'ESTUDIANTE'),
  ('Adriana Palacios', 'alumno39@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 10, 'ESTUDIANTE'),
  ('Piero Córdova', 'alumno40@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ICV'), 'Ingeniería Civil', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 9, 'ESTUDIANTE'),
  ('Romina Serrano', 'alumno41@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 10, 'ESTUDIANTE'),
  ('Renzo Zavala', 'alumno42@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 9, 'ESTUDIANTE'),
  ('Fiorella Reyes', 'alumno43@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 10, 'ESTUDIANTE'),
  ('Gino Bautista', 'alumno44@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 9, 'ESTUDIANTE'),
  ('Daniela Carrasco', 'alumno45@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'IIN'), 'Ingeniería Industrial', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 10, 'ESTUDIANTE'),
  ('Óscar Figueroa', 'alumno46@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ICV'), 'Ingeniería Civil', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 10, 'ESTUDIANTE'),
  ('Alessandra Benítez', 'alumno47@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ADM'), 'Administración de Empresas', (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 9, 'ESTUDIANTE'),
  ('Kevin Tapia', 'alumno48@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'PSI'), 'Psicología', (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 9, 'ESTUDIANTE'),
  ('Melissa Miranda', 'alumno49@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISI'), 'Ingeniería de Sistemas', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 3, 'ESTUDIANTE'),
  ('Bryan Valdivia', 'alumno50@utp.edu.pe', '$2a$10$xZiAvKG.YU0AAi0e/IHxueJoAFWMBhx7SHgmeznPTgWPrxdn.onH.', (SELECT id FROM carreras WHERE codigo = 'ISW'), 'Ingeniería de Software', (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 3, 'ESTUDIANTE')
ON CONFLICT (correo) DO NOTHING;

-- 8.5 Docentes (40 perfiles: 4 arquetipos naturales + 4 outliers para DBSCAN)
INSERT INTO docentes (codigo_docente, nombre, facultad_id, carrera_id, sede_id, facultad, sede, verificado, estilo_ensenanza, estilo_evaluacion, modalidad_principal, anios_experiencia_utp, resumen, etiquetas) VALUES
  ('DOC-001', 'Carlos Ramírez Salazar', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación clara', 'Prácticas y exámenes', 'PRESENCIAL', 7, 'Explica los conceptos paso a paso y los conecta con ejercicios similares a las evaluaciones. Las clases son participativas; practicar semanalmente ayuda a llegar con confianza.', 'Metodología clara,Práctica semanal'),
  ('DOC-002', 'María Fernanda Paredes', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Evaluación continua', 'Controles semanales y proyecto', 'PRESENCIAL', 6, 'Evalúa de forma continua con controles cortos, lo que evita acumular contenido. Muy accesible para resolver dudas dentro y fuera de clase.', 'Evaluación continua,Accesible'),
  ('DOC-005', 'Luis Alberto Torres', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación clara', 'Laboratorios y examen final', 'PRESENCIAL', 8, 'Combina teoría breve con laboratorios guiados. Pide entregas puntuales y revisa el avance de cada práctica.', 'Metodología clara,Laboratorios guiados'),
  ('DOC-006', 'Ana Lucía Vega', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISW'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Proyecto por entregas', 'SEMIPRESENCIAL', 5, 'El curso se trabaja con un proyecto por entregas. Da retroalimentación frecuente y fomenta el trabajo en equipo.', 'Aprendizaje por proyecto,Retroalimentación'),
  ('DOC-007', 'Ricardo Manuel Huertas', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación clara', 'Laboratorios y proyecto integrador', 'PRESENCIAL', 9, 'Domina inteligencia artificial aplicada y guía cada laboratorio con código real y retroalimentación detallada.', 'Metodología clara,Ejemplos reales'),
  ('DOC-008', 'Patricia Elena Solís', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISW'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Evaluación continua', 'Sprints y revisión de código', 'SEMIPRESENCIAL', 6, 'Aplica prácticas de ingeniería real con revisión de código cada semana y tutorías abiertas.', 'Aprendizaje por proyecto,Retroalimentación'),
  ('DOC-009', 'Fernando José Delgado', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación clara', 'Casos prácticos y exámenes', 'PRESENCIAL', 10, 'Conecta estadística e investigación operativa con problemas de empresas peruanas; muy ordenado y puntual.', 'Ejemplos reales,Metodología clara'),
  ('DOC-010', 'Gabriela Sofía Navarro', (SELECT id FROM facultades WHERE codigo = 'FNEG'), (SELECT id FROM carreras WHERE codigo = 'ADM'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Negocios · Administración de Empresas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Proyecto real y sustentaciones', 'SEMIPRESENCIAL', 7, 'Fomenta el análisis crítico con casos reales y entrega feedback constructivo en cada avance.', 'Retroalimentación,Ejemplos reales'),
  ('DOC-011', 'Humberto César Palacios', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Arequipa · Av. Parra', TRUE, 'Explicación clara', 'Prácticas calificadas y labs', 'PRESENCIAL', 8, 'Excelente pedagogo para cursos de algoritmos y programación; siempre deja ejercicios resueltos como guía.', 'Metodología clara,Laboratorios guiados'),
  ('DOC-012', 'Verónica Isabel Cárdenas', (SELECT id FROM facultades WHERE codigo = 'FDCH'), (SELECT id FROM carreras WHERE codigo = 'PSI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Derecho y Ciencias Humanas · Psicología', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Talleres y ensayos reflexivos', 'PRESENCIAL', 6, 'Clases sumamente participativas con talleres aplicados a organizaciones reales y trato muy empático.', 'Explicación dinámica,Accesible'),
  ('DOC-013', 'Martín Eduardo Chávez', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ICV'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Civil', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación clara', 'Laboratorios y exámenes parciales', 'PRESENCIAL', 11, 'Explica mecánica de materiales con maquetas y ejemplos de obra; exigencia justa y gran claridad.', 'Metodología clara,Dominio del tema'),
  ('DOC-003', 'Jorge Luis Quispe', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Exámenes y casos complejos', 'PRESENCIAL', 12, 'Domina el tema y exige mucho. Sus exámenes incluyen casos complejos, por lo que conviene estudiar con anticipación y no dejar dudas para el final.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-014', 'Guillermo Arturo Salazar', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Exámenes escritos rigurosos', 'PRESENCIAL', 14, 'Gran dominio matemático pero ritmo muy acelerado. Califica procedimientos al detalle y pide alto esfuerzo fuera de clase.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-015', 'Ernesto Raúl Benítez', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Exámenes prácticos cronometrados', 'PRESENCIAL', 10, 'Muy exigente con el diseño normalizado y consultas complejas en SQL. Se aprende mucho, pero el curso demanda muchas horas.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-016', 'Mónica Liliana Serrano', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Alto nivel de exigencia', 'Casos de optimización y parciales', 'PRESENCIAL', 9, 'Experta en optimización lineal. Sus prácticas son extensas y poco tolerante con errores conceptuales básicos.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-017', 'Víctor Hugo Carrasco', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ICV'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Civil', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Exámenes de cálculo estructural', 'PRESENCIAL', 15, 'Eminencia técnica en estructuras, pero poco paciente en clase. Exige rigor absoluto en cada memoria de cálculo.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-018', 'Alberto Enrique Figueroa', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISW'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Arquitectura y sustentación técnica', 'PRESENCIAL', 11, 'Nivel de industria senior; cuestiona cada decisión de arquitectura y exige documentación formal impecable.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-019', 'César Augusto Mendoza', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Arequipa · Av. Parra', TRUE, 'Alto nivel de exigencia', 'Exámenes teóricos y proyectos', 'PRESENCIAL', 13, 'Fuerte base teórica en algoritmos y machine learning. Evaluaciones difíciles con tiempo ajustado.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-020', 'Rocío del Pilar Valdivia', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Prácticas calificadas rigurosas', 'PRESENCIAL', 8, 'Explica con rigor formal y pide demostraciones completas. Quienes estudian a conciencia logran una gran base.', 'Alto nivel de exigencia,Práctica semanal'),
  ('DOC-021', 'Óscar Javier Tapia', (SELECT id FROM facultades WHERE codigo = 'FNEG'), (SELECT id FROM carreras WHERE codigo = 'ADM'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Negocios · Administración de Empresas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Estudios de caso y defensas orales', 'PRESENCIAL', 12, 'Muy estricto con indicadores financieros y gestión de riesgos; exige preparación previa para cada sesión.', 'Alto nivel de exigencia,Ejemplos reales'),
  ('DOC-022', 'Héctor Darío Córdova', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Alto nivel de exigencia', 'Exámenes de codificación sin apuntes', 'PRESENCIAL', 10, 'Exámenes de programación exigentes desde la primera unidad. Sabe muchísimo pero avanza sin detenerse.', 'Alto nivel de exigencia,Dominio del tema'),
  ('DOC-004', 'Rosa Elena Mendoza', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Prácticas calificadas', 'PRESENCIAL', 5, 'Usa ejemplos cotidianos y dinámicas en clase para explicar los temas. Ideal para quienes sienten que Cálculo es difícil de entender.', 'Explicación dinámica,Ejemplos reales'),
  ('DOC-023', 'Claudia Beatriz Romero', (SELECT id FROM facultades WHERE codigo = 'FDCH'), (SELECT id FROM carreras WHERE codigo = 'PSI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Derecho y Ciencias Humanas · Psicología', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Foros y trabajos grupales', 'VIRTUAL', 4, 'Muy cercana y comprensiva con horarios laborales. Evaluaciones accesibles basadas en casos participativos.', 'Accesible,Explicación dinámica'),
  ('DOC-024', 'Diego Armando Cruz', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Explicación dinámica', 'Laboratorios grupales flexibles', 'VIRTUAL', 3, 'Ideal para iniciarse en programación sin estrés. Responde rápido por mensajería y da oportunidades de recuperación.', 'Accesible,Laboratorios guiados'),
  ('DOC-025', 'Lucía Milagros Ortiz', (SELECT id FROM facultades WHERE codigo = 'FNEG'), (SELECT id FROM carreras WHERE codigo = 'ADM'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Negocios · Administración de Empresas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Evaluación continua', 'Talleres en clase y exposiciones', 'SEMIPRESENCIAL', 4, 'Dinámica y amable; casi todo el avance se resuelve durante las horas de clase con acompañamiento constante.', 'Accesible,Evaluación continua'),
  ('DOC-026', 'Pablo Andrés Lozano', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISW'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Entregables guiados paso a paso', 'VIRTUAL', 3, 'Brinda plantillas base y explica paso a paso cada práctica de desarrollo web; ambiente relajado y colaborativo.', 'Explicación dinámica,Laboratorios guiados'),
  ('DOC-027', 'Silvia Lorena Guzmán', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Arequipa · Av. Parra', TRUE, 'Evaluación continua', 'Cuestionarios breves y talleres', 'SEMIPRESENCIAL', 5, 'Explica con mucha paciencia los fundamentos estadísticos y siempre ofrece sesiones de repaso antes de cada control.', 'Accesible,Explicación dinámica'),
  ('DOC-028', 'Javier Alonso Pacheco', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Proyectos creativos en grupo', 'VIRTUAL', 4, 'Hace entretenidos los temas de IA con demos interactivas; poca carga teórica pesada y trato muy cordial.', 'Explicación dinámica,Ejemplos reales'),
  ('DOC-029', 'Karina Estefanía Ríos', (SELECT id FROM facultades WHERE codigo = 'FDCH'), (SELECT id FROM carreras WHERE codigo = 'PSI'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Derecho y Ciencias Humanas · Psicología', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Explicación dinámica', 'Dinámicas y portafolio digital', 'VIRTUAL', 3, 'Muy empática y flexible con fechas de entrega justificadas. Clases amenas con videos y discusiones guiadas.', 'Accesible,Retroalimentación'),
  ('DOC-030', 'Renzo Fabián Aguilar', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISW'), (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Arequipa · Av. Parra', TRUE, 'Evaluación continua', 'Talleres prácticos en clase', 'SEMIPRESENCIAL', 4, 'Acompaña cada diagrama y entrega con paciencia; carga ligera y calificaciones generalmente favorables.', 'Accesible,Aprendizaje por proyecto'),
  ('DOC-031', 'Paola Cristina Campos', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Explicación dinámica', 'Ejercicios guiados y grupales', 'PRESENCIAL', 5, 'Traduce modelos de investigación operativa a hojas de cálculo sencillas; excelente trato hacia los estudiantes.', 'Explicación dinámica,Accesible'),
  ('DOC-032', 'Rodolfo Segundo Peña', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Exposición tradicional', 'Exámenes memorísticos', 'VIRTUAL', 2, 'Suele leer diapositivas sin profundizar en ejemplos prácticos y tarda en responder consultas por plataforma.', 'Clases desorganizadas'),
  ('DOC-033', 'Nelly Rosario Huamán', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Exposición tradicional', 'Evaluaciones sin rúbrica clara', 'VIRTUAL', 2, 'Cambia criterios de calificación sobre la marcha y sus explicaciones resultan confusas en los temas centrales.', 'Clases desorganizadas'),
  ('DOC-034', 'Marco Antonio Zavala', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ICV'), (SELECT id FROM sedes WHERE codigo = 'AQP-CTR'), 'Facultad de Ingeniería · Ingeniería Civil', 'UTP Arequipa · Av. Parra', TRUE, 'Exposición tradicional', 'Exámenes extensos sin retroalimentación', 'PRESENCIAL', 3, 'Poca organización de sesiones y escasa devolución sobre errores en prácticas calificadas.', 'Clases desorganizadas'),
  ('DOC-035', 'Lourdes Maribel Bautista', (SELECT id FROM facultades WHERE codigo = 'FNEG'), (SELECT id FROM carreras WHERE codigo = 'ADM'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Negocios · Administración de Empresas', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Exposición tradicional', 'Exposiciones sin guía previa', 'VIRTUAL', 1, 'Delega gran parte de la teoría a exposiciones grupales y brinda poca orientación metodológica.', 'Clases desorganizadas'),
  ('DOC-036', 'Enrique Oswaldo Miranda', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISW'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Exposición tradicional', 'Entregas poco especificadas', 'VIRTUAL', 2, 'Material desactualizado en desarrollo web y escaso acompañamiento durante el avance del proyecto.', 'Clases desorganizadas'),
  ('DOC-037', 'Esteban Mauricio León', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Estilo polarizante', 'Evaluación impredecible', 'PRESENCIAL', 6, 'Genera opiniones completamente opuestas: un grupo lo considera brillante y otro reporta experiencias muy negativas.', 'Alto nivel de exigencia,Clases desorganizadas'),
  ('DOC-038', 'Vanessa Lucero Cabrera', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'IIN'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería Industrial', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Estilo polarizante', 'Participación subjetiva', 'SEMIPRESENCIAL', 5, 'Sus evaluaciones dividen drásticamente al salón entre calificaciones máximas y mínimas según afinidad en clase.', 'Explicación dinámica,Clases desorganizadas'),
  ('DOC-039', 'Cristian Omar Espinoza', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISW'), (SELECT id FROM sedes WHERE codigo = 'LIM-NOR'), 'Facultad de Ingeniería · Ingeniería de Software', 'UTP Lima Norte · Panamericana Norte', TRUE, 'Exposición tradicional', 'Proyecto final único', 'VIRTUAL', 2, 'Perfil atípico con alta proporción de reseñas rechazadas en moderación y volumen inusual de guardados.', 'Clases desorganizadas'),
  ('DOC-040', 'Teodoro Nicolás Vargas', (SELECT id FROM facultades WHERE codigo = 'FING'), (SELECT id FROM carreras WHERE codigo = 'ISI'), (SELECT id FROM sedes WHERE codigo = 'LIM-CTR'), 'Facultad de Ingeniería · Ingeniería de Sistemas', 'UTP Lima Centro · Edificio Arequipa', TRUE, 'Alto nivel de exigencia', 'Proyectos maratónicos y exámenes orales', 'PRESENCIAL', 18, 'Carga académica desproporcionada (>20 horas semanales) con altísimo dominio técnico pero mínima empatía y tasas de aprobación muy bajas.', 'Alto nivel de exigencia,Dominio del tema')
ON CONFLICT (nombre) DO NOTHING;

-- 8.6 Oferta Académica (docente_curso)
INSERT INTO docente_curso (docente_id, curso_id, modalidad) VALUES
  ((SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), 'SEMIPRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), 'VIRTUAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), 'PRESENCIAL'),
  ((SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), 'PRESENCIAL')
ON CONFLICT (docente_id, curso_id) DO NOTHING;

-- 8.7 Etiquetas normalizadas por docente (docente_etiqueta)
INSERT INTO docente_etiqueta (docente_id, etiqueta_id, peso) VALUES
  ((SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM etiquetas WHERE slug = 'metodologia-clara'), 20),
  ((SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM etiquetas WHERE slug = 'practica-semanal'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 9),
  ((SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM etiquetas WHERE slug = 'evaluacion-continua'), 21),
  ((SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 11),
  ((SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM etiquetas WHERE slug = 'retroalimentacion'), 21),
  ((SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM etiquetas WHERE slug = 'metodologia-clara'), 9),
  ((SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM etiquetas WHERE slug = 'laboratorios-guiados'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM etiquetas WHERE slug = 'aprendizaje-por-proyecto'), 15),
  ((SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM etiquetas WHERE slug = 'retroalimentacion'), 18),
  ((SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 21),
  ((SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM etiquetas WHERE slug = 'metodologia-clara'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM etiquetas WHERE slug = 'ejemplos-reales'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM etiquetas WHERE slug = 'aprendizaje-por-proyecto'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM etiquetas WHERE slug = 'retroalimentacion'), 11),
  ((SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM etiquetas WHERE slug = 'metodologia-clara'), 18),
  ((SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM etiquetas WHERE slug = 'ejemplos-reales'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM etiquetas WHERE slug = 'metodologia-clara'), 19),
  ((SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 22),
  ((SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM etiquetas WHERE slug = 'retroalimentacion'), 18),
  ((SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM etiquetas WHERE slug = 'ejemplos-reales'), 18),
  ((SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 9),
  ((SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM etiquetas WHERE slug = 'metodologia-clara'), 17),
  ((SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM etiquetas WHERE slug = 'laboratorios-guiados'), 18),
  ((SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 16),
  ((SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 19),
  ((SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM etiquetas WHERE slug = 'retroalimentacion'), 11),
  ((SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM etiquetas WHERE slug = 'metodologia-clara'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 15),
  ((SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM etiquetas WHERE slug = 'ejemplos-reales'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 8),
  ((SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 7),
  ((SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 9),
  ((SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 4),
  ((SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 7),
  ((SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 4),
  ((SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 9),
  ((SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 8),
  ((SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 5),
  ((SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 7),
  ((SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM etiquetas WHERE slug = 'practica-semanal'), 9),
  ((SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 7),
  ((SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM etiquetas WHERE slug = 'ejemplos-reales'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 11),
  ((SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM etiquetas WHERE slug = 'ejemplos-reales'), 11),
  ((SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 6),
  ((SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 8),
  ((SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 6),
  ((SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 7),
  ((SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM etiquetas WHERE slug = 'laboratorios-guiados'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM etiquetas WHERE slug = 'evaluacion-continua'), 8),
  ((SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM etiquetas WHERE slug = 'laboratorios-guiados'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 9),
  ((SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 7),
  ((SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM etiquetas WHERE slug = 'ejemplos-reales'), 6),
  ((SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 11),
  ((SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM etiquetas WHERE slug = 'retroalimentacion'), 5),
  ((SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 4),
  ((SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM etiquetas WHERE slug = 'aprendizaje-por-proyecto'), 5),
  ((SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 6),
  ((SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM etiquetas WHERE slug = 'accesible'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 6),
  ((SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 14),
  ((SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 5),
  ((SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 10),
  ((SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM etiquetas WHERE slug = 'explicacion-dinamica'), 13),
  ((SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 11),
  ((SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM etiquetas WHERE slug = 'clases-desorganizadas'), 12),
  ((SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM etiquetas WHERE slug = 'alto-nivel-exigencia'), 8),
  ((SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM etiquetas WHERE slug = 'dominio-del-tema'), 12)
ON CONFLICT (docente_id, etiqueta_id) DO NOTHING;

-- 8.8 Reseñas (421 registros: aprobadas, pendientes, rechazadas y anomalías diversas para DBSCAN)
INSERT INTO resenas (
  usuario_id, docente_id, curso_id, periodo_id,
  dominio, claridad, empatia, retroalimentacion, organizacion, puntualidad,
  dificultad, horas_estudio_semanal, recomienda, asistencia_obligatoria, nota_obtenida,
  comentario, estado, es_anomalia_ml, fecha
) VALUES
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 4, 5, 4, 'MODERADO', 5.3, TRUE, TRUE, 16.36, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '14 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 4, 5, 5, 5, 4, 'MODERADO', 5.0, TRUE, TRUE, 16.68, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '37 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 5.1, TRUE, TRUE, 16.15, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '76 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 5.5, TRUE, TRUE, 17.39, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '102 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 4, 5, 4, 5, 'LIGERO', 6.1, TRUE, TRUE, 16.45, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '119 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 6.3, TRUE, TRUE, 17.86, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '148 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 4, 5, 'MODERADO', 4.4, TRUE, TRUE, 14.0, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '183 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.5, TRUE, TRUE, 16.05, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '200 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 5, 5, 5, 5, 'MODERADO', 4.0, TRUE, TRUE, 16.51, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '232 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 4, 4, 5, 'EXIGENTE', 4.3, TRUE, TRUE, 15.81, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '256 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 4, 5, 'MODERADO', 6.2, TRUE, TRUE, 18.21, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '11 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.5, TRUE, TRUE, 16.88, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '40 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 4, 5, 5, 'LIGERO', 3.5, FALSE, TRUE, 17.14, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '72 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno25@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.8, FALSE, TRUE, 16.1, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '99 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 4, 5, 5, 5, 5, 'MODERADO', 5.3, TRUE, TRUE, 15.78, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '129 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 4, 'LIGERO', 4.8, TRUE, TRUE, 16.63, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '155 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 4, 5, 5, 'MODERADO', 5.4, TRUE, TRUE, 16.5, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '174 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 4, 5, 4, 'MODERADO', 5.3, TRUE, TRUE, 16.72, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '208 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 6.3, TRUE, TRUE, 15.58, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '237 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.8, TRUE, TRUE, 16.49, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '256 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 5, 5, 4, 'MODERADO', 4.8, TRUE, TRUE, 14.73, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '11 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 4, 5, 'MODERADO', 4.7, TRUE, TRUE, 15.63, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '40 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 4, 4, 'MODERADO', 5.5, TRUE, TRUE, 17.2, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '73 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.9, TRUE, TRUE, 16.1, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '101 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.9, TRUE, TRUE, 15.47, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '126 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 5, 4, 5, 5, 'MODERADO', 6.6, TRUE, TRUE, 17.53, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '148 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno25@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 4, 'MODERADO', 4.4, TRUE, TRUE, 15.64, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '175 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 4, 5, 5, 'MODERADO', 6.1, TRUE, TRUE, 16.02, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '200 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 5.8, TRUE, TRUE, 14.56, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '233 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 5, 4, 4, 'MODERADO', 4.9, TRUE, TRUE, 15.78, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '256 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.8, TRUE, TRUE, 16.71, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '13 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 5, 4, 'MODERADO', 5.8, TRUE, TRUE, 16.03, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '45 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 4, 5, 4, 5, 'MODERADO', 5.6, TRUE, TRUE, 14.92, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '73 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.9, TRUE, TRUE, 16.57, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '96 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 4, 5, 4, 5, 'LIGERO', 5.7, TRUE, TRUE, 16.11, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '118 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.5, TRUE, TRUE, 17.67, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '154 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 4.2, TRUE, TRUE, 17.81, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '183 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 4, 5, 5, 'MODERADO', 4.9, TRUE, TRUE, 17.08, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '209 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 4, 5, 'MODERADO', 5.5, TRUE, TRUE, 16.76, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '230 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 4, 5, 5, 5, 'MODERADO', 4.3, TRUE, TRUE, 16.76, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '259 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 4, 'MODERADO', 5.1, TRUE, TRUE, 15.61, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '11 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 4, 5, 4, 5, 4, 'MODERADO', 5.7, TRUE, TRUE, 16.65, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '47 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 4, 5, 4, 5, 'MODERADO', 5.3, TRUE, TRUE, 16.76, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '75 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 3.8, TRUE, TRUE, 14.86, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '94 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 4, 5, 5, 5, 'MODERADO', 6.2, TRUE, TRUE, 17.59, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '127 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.1, TRUE, TRUE, 16.51, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '147 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 5, 4, 5, 'MODERADO', 4.5, TRUE, TRUE, 15.25, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '176 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 4, 4, 5, 5, 'MODERADO', 5.1, TRUE, TRUE, 15.86, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '201 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 5, 5, 5, 'MODERADO', 5.7, TRUE, TRUE, 16.58, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '235 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno25@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 4, 5, 5, 'MODERADO', 4.9, TRUE, TRUE, 17.7, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '260 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 4, 5, 'MODERADO', 6.1, TRUE, TRUE, 15.36, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '11 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 4, 4, 5, 5, 'MODERADO', 6.4, TRUE, TRUE, 16.68, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '44 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 4, 5, 5, 'MODERADO', 4.7, TRUE, TRUE, 14.74, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '71 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 5, 5, 5, 'MODERADO', 5.5, TRUE, TRUE, 14.52, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '101 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 4, 5, 4, 5, 'LIGERO', 5.3, TRUE, TRUE, 16.77, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '125 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 4, 5, 5, 'MODERADO', 5.5, TRUE, TRUE, 18.01, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '155 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 4, 5, 5, 4, 'MODERADO', 4.7, TRUE, TRUE, 16.02, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '183 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 4, 5, 5, 'MODERADO', 5.2, TRUE, TRUE, 17.04, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '206 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 4, 5, 'MODERADO', 5.8, TRUE, TRUE, 16.22, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '226 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 4, 4, 4, 'EXIGENTE', 5.1, TRUE, TRUE, 16.31, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '258 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 4, 5, 5, 4, 'MODERADO', 5.7, FALSE, TRUE, 17.14, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '19 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 4, 5, 4, 5, 5, 'MODERADO', 5.4, TRUE, TRUE, 14.48, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '40 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 4, 4, 'MODERADO', 4.8, TRUE, TRUE, 14.47, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '68 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 5, 5, 'LIGERO', 5.9, TRUE, TRUE, 15.39, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '93 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 4, 'MODERADO', 5.7, TRUE, TRUE, 17.11, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '122 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 4, 5, 5, 5, 'MODERADO', 5.0, TRUE, TRUE, 16.88, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '155 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 4, 5, 5, 'MODERADO', 5.7, TRUE, TRUE, 15.88, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '184 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 4, 'MODERADO', 6.0, TRUE, TRUE, 17.03, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '199 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 6.1, TRUE, TRUE, 16.1, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '230 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 4, 5, 5, 'MODERADO', 5.4, TRUE, TRUE, 17.64, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '265 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 5, 'MODERADO', 4.3, TRUE, TRUE, 15.45, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '20 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 4, 4, 'MODERADO', 4.3, TRUE, TRUE, 16.61, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '39 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 4.8, TRUE, TRUE, 15.0, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '73 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 4, 5, 5, 'MODERADO', 5.4, TRUE, TRUE, 17.26, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '92 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 4, 5, 5, 5, 'MODERADO', 4.4, TRUE, TRUE, 16.67, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '118 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.7, TRUE, TRUE, 15.71, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '145 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 6.4, TRUE, TRUE, 16.45, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '172 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 4, 5, 5, 5, 'MODERADO', 4.7, TRUE, TRUE, 15.75, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '199 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 4, 'MODERADO', 5.1, TRUE, TRUE, 15.35, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '235 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 4, 4, 5, 'MODERADO', 4.6, TRUE, TRUE, 16.27, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '263 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 5.9, TRUE, TRUE, 16.83, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '12 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 4, 'MODERADO', 4.6, TRUE, TRUE, 15.7, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '43 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 4, 5, 5, 5, 'MODERADO', 5.9, TRUE, TRUE, 16.95, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.4, TRUE, TRUE, 15.05, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '91 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 4, 5, 5, 'MODERADO', 5.2, TRUE, TRUE, 16.01, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '119 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 5, 4, 'MODERADO', 5.5, TRUE, TRUE, 16.45, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '145 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 4.8, TRUE, TRUE, 16.61, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '180 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.3, TRUE, TRUE, 17.1, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '205 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.3, TRUE, TRUE, 15.34, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '231 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 4, 5, 5, 5, 'MODERADO', 4.4, TRUE, TRUE, 15.15, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '259 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 5.7, TRUE, TRUE, 17.24, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '13 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 5, 5, 'MODERADO', 5.9, TRUE, TRUE, 17.54, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '44 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 4, 5, 4, 5, 'MODERADO', 5.9, TRUE, TRUE, 15.35, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '71 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 4, 5, 5, 5, 'LIGERO', 4.9, TRUE, TRUE, 16.84, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '100 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.6, TRUE, TRUE, 17.44, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '125 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 5, 5, 5, 5, 'MODERADO', 6.1, TRUE, TRUE, 16.24, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '150 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 5, 5, 'MODERADO', 4.7, TRUE, TRUE, 15.98, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '181 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.0, TRUE, TRUE, 15.11, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '209 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 5, 4, 5, 4, 'MODERADO', 4.8, TRUE, TRUE, 16.69, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '229 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 5.5, TRUE, TRUE, 14.61, 'Explica los conceptos paso a paso y conecta cada tema con ejercicios parecidos a las prácticas calificadas.', 'APROBADA', FALSE, NOW() - INTERVAL '263 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 4, 5, 5, 5, 'MODERADO', 6.2, TRUE, TRUE, 15.47, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '20 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 4, 5, 5, 'EXIGENTE', 5.6, TRUE, TRUE, 14.4, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '46 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 5, 5, 'MODERADO', 5.6, TRUE, TRUE, 16.82, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'APROBADA', FALSE, NOW() - INTERVAL '72 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 5, 5, 5, 'MODERADO', 5.4, TRUE, TRUE, 15.96, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'APROBADA', FALSE, NOW() - INTERVAL '96 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 4, 5, 5, 5, 'MODERADO', 6.1, TRUE, TRUE, 17.13, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '120 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 4, 'LIGERO', 5.7, TRUE, TRUE, 16.63, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '156 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 5, 5, 'MODERADO', 6.4, TRUE, TRUE, 16.96, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '172 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 5, 4, 5, 'MODERADO', 4.9, TRUE, TRUE, 15.35, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'APROBADA', FALSE, NOW() - INTERVAL '207 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 5, 5, 5, 5, 'MODERADO', 5.3, TRUE, TRUE, 15.45, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'APROBADA', FALSE, NOW() - INTERVAL '237 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 4, 5, 5, 4, 'EXIGENTE', 4.9, TRUE, TRUE, 16.38, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'APROBADA', FALSE, NOW() - INTERVAL '265 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 2, 4, 5, 'EXIGENTE', 11.9, TRUE, TRUE, 12.07, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '14 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 4, 4, 'EXIGENTE', 9.1, TRUE, TRUE, 13.83, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '44 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 3, 1, 3, 4, 4, 'EXIGENTE', 12.0, TRUE, TRUE, 11.98, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '69 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 2, 2, 3, 5, 'EXIGENTE', 12.6, TRUE, TRUE, 12.34, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '92 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 2, 4, 4, 'EXIGENTE', 11.5, TRUE, TRUE, 12.77, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '123 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 3, 3, 3, 5, 'MODERADO', 12.0, TRUE, TRUE, 13.66, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '148 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 1, 3, 4, 5, 'EXIGENTE', 11.7, FALSE, TRUE, 14.21, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '175 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 3, 5, 5, 'EXIGENTE', 12.9, FALSE, TRUE, 12.89, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '207 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 2, 3, 4, 'EXIGENTE', 11.9, TRUE, TRUE, 13.42, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '226 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 2, 4, 4, 'EXIGENTE', 13.0, TRUE, TRUE, 13.0, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '262 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 3, 4, 5, 'EXIGENTE', 10.1, FALSE, TRUE, 12.62, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '16 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 10.1, FALSE, TRUE, 14.76, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '41 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 3, 3, 3, 4, 'EXIGENTE', 11.9, FALSE, TRUE, 12.81, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '69 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 3, 4, 4, 'EXIGENTE', 10.2, TRUE, TRUE, 12.45, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '95 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 2, 4, 5, 'MODERADO', 10.3, TRUE, TRUE, 13.38, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '120 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 3, 3, 3, 5, 'EXIGENTE', 12.0, TRUE, TRUE, 13.41, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '148 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 10.8, TRUE, TRUE, 14.04, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '179 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 3, 3, 5, 'EXIGENTE', 11.2, TRUE, TRUE, 13.23, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '203 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 3, 3, 3, 5, 'MODERADO', 12.6, TRUE, TRUE, 13.37, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '227 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 3, 2, 4, 4, 4, 'EXIGENTE', 10.0, TRUE, TRUE, 13.99, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '265 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 2, 3, 4, 5, 'EXIGENTE', 10.1, TRUE, TRUE, 13.33, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '19 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 4, 2, 2, 3, 5, 'EXIGENTE', 11.2, FALSE, TRUE, 12.27, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '42 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 4, 4, 4, 'EXIGENTE', 11.3, FALSE, TRUE, 14.31, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '73 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 3, 3, 4, 'EXIGENTE', 11.3, FALSE, TRUE, 12.79, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '94 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 3, 3, 5, 'EXIGENTE', 12.3, FALSE, TRUE, 11.82, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '121 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 2, 3, 4, 5, 'EXIGENTE', 10.4, FALSE, TRUE, 14.23, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '154 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 4, 4, 'EXIGENTE', 11.8, TRUE, TRUE, 14.36, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '180 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 4, 4, 'EXIGENTE', 11.5, TRUE, TRUE, 12.5, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '204 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 12.7, TRUE, TRUE, 13.94, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '236 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 3, 3, 5, 'EXIGENTE', 14.1, TRUE, TRUE, 12.45, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '260 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 2, 3, 4, 4, 'EXIGENTE', 9.8, FALSE, TRUE, 12.68, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '16 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 2, 4, 5, 'EXIGENTE', 11.3, TRUE, TRUE, 13.24, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '38 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 2, 3, 5, 4, 'EXIGENTE', 11.6, TRUE, TRUE, 13.41, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '74 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 4, 4, 'EXIGENTE', 10.7, TRUE, TRUE, 12.3, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '92 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 3, 4, 5, 'EXIGENTE', 11.5, TRUE, TRUE, 10.77, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '118 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 3, 3, 4, 5, 'EXIGENTE', 12.6, TRUE, TRUE, 12.14, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '155 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 3, 3, 5, 'EXIGENTE', 10.7, FALSE, TRUE, 11.1, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '184 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 3, 4, 'EXIGENTE', 12.8, FALSE, TRUE, 14.1, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '208 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 9.6, TRUE, TRUE, 12.89, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '232 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 3, 2, 2, 4, 5, 'MODERADO', 11.5, TRUE, TRUE, 13.34, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '261 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 3, 5, 'EXIGENTE', 12.8, TRUE, TRUE, 12.82, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '17 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 4, 2, 2, 4, 4, 'EXIGENTE', 10.2, FALSE, TRUE, 12.74, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '37 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 2, 3, 4, 'EXIGENTE', 10.9, FALSE, TRUE, 13.59, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '64 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 2, 4, 5, 'EXIGENTE', 10.0, FALSE, TRUE, 13.44, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '102 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 4, 4, 5, 'EXIGENTE', 12.1, TRUE, TRUE, 11.66, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '130 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 3, 2, 3, 4, 'EXIGENTE', 10.1, FALSE, TRUE, 12.58, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '155 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 2, 3, 4, 'EXIGENTE', 10.9, TRUE, TRUE, 13.26, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '179 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 4, 4, 'EXIGENTE', 10.9, TRUE, TRUE, 12.83, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '204 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 3, 3, 4, 5, 'EXIGENTE', 9.8, TRUE, TRUE, 11.9, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '237 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 2, 4, 4, 'EXIGENTE', 11.3, FALSE, TRUE, 11.51, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '264 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 11.1, FALSE, TRUE, 13.79, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '11 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 2, 3, 5, 'EXIGENTE', 11.5, TRUE, TRUE, 13.5, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '46 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 3, 4, 4, 'EXIGENTE', 11.1, FALSE, TRUE, 12.36, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '71 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 3, 4, 5, 'EXIGENTE', 12.6, FALSE, TRUE, 12.71, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '101 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 4, 4, 'EXIGENTE', 10.4, FALSE, TRUE, 13.89, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '125 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 3, 3, 4, 'EXIGENTE', 13.2, FALSE, TRUE, 13.18, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '146 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 2, 3, 5, 'MODERADO', 12.5, TRUE, TRUE, 12.75, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '176 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 3, 4, 5, 'EXIGENTE', 10.0, FALSE, TRUE, 13.19, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '206 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 4, 2, 5, 4, 'EXIGENTE', 12.6, FALSE, TRUE, 12.2, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '226 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 2, 4, 5, 'MODERADO', 11.5, FALSE, TRUE, 13.48, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '254 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 2, 4, 4, 'EXIGENTE', 13.3, FALSE, TRUE, 15.07, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '21 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 2, 4, 4, 'EXIGENTE', 11.4, TRUE, TRUE, 12.78, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '44 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 2, 3, 4, 4, 'EXIGENTE', 11.9, TRUE, TRUE, 11.64, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '70 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 5, 5, 'EXIGENTE', 11.4, TRUE, TRUE, 12.58, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '98 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 3, 4, 5, 'EXIGENTE', 10.8, TRUE, TRUE, 13.49, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '129 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 2, 2, 3, 4, 5, 'EXIGENTE', 11.0, TRUE, TRUE, 13.01, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '149 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 2, 3, 5, 'EXIGENTE', 11.5, TRUE, TRUE, 13.08, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '178 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 3, 3, 4, 'EXIGENTE', 10.2, TRUE, TRUE, 12.16, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '205 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 2, 3, 4, 5, 'EXIGENTE', 11.0, FALSE, TRUE, 13.28, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '234 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 3, 4, 4, 'EXIGENTE', 10.8, FALSE, TRUE, 11.44, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '263 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 3, 5, 'EXIGENTE', 10.3, TRUE, TRUE, 12.31, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '18 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 2, 4, 4, 'EXIGENTE', 10.9, FALSE, TRUE, 12.3, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '46 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 1, 4, 5, 'EXIGENTE', 10.2, FALSE, TRUE, 12.93, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 2, 2, 5, 5, 'EXIGENTE', 10.8, TRUE, TRUE, 14.94, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '96 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 4, 2, 3, 4, 5, 'EXIGENTE', 11.7, FALSE, TRUE, 13.11, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '123 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 3, 2, 3, 4, 'EXIGENTE', 10.4, FALSE, TRUE, 13.45, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '147 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 2, 3, 5, 'MODERADO', 11.6, FALSE, TRUE, 13.71, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '181 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 12.2, TRUE, TRUE, 12.83, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '208 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 2, 2, 4, 4, 'EXIGENTE', 11.9, TRUE, TRUE, 13.25, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '227 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 3, 4, 'EXIGENTE', 9.2, FALSE, TRUE, 12.53, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '261 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 4, 5, 'MODERADO', 12.6, FALSE, TRUE, 14.25, 'Tiene enorme experiencia profesional, aunque es poco flexible y exige nivel casi de producción en el curso.', 'APROBADA', FALSE, NOW() - INTERVAL '20 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 4, 5, 'EXIGENTE', 11.4, TRUE, TRUE, 13.23, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '39 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 3, 2, 2, 4, 5, 'EXIGENTE', 11.8, FALSE, TRUE, 12.23, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '76 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 4, 4, 'EXIGENTE', 12.2, FALSE, TRUE, 13.14, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '98 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 3, 2, 3, 5, 'EXIGENTE', 11.7, TRUE, TRUE, 13.43, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '130 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 2, 4, 5, 'EXIGENTE', 12.5, FALSE, TRUE, 12.68, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '147 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 2, 3, 3, 4, 5, 'EXIGENTE', 10.9, FALSE, TRUE, 11.36, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '179 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 3, 3, 4, 'EXIGENTE', 10.6, FALSE, TRUE, 12.93, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '206 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 2, 4, 4, 'EXIGENTE', 11.2, TRUE, TRUE, 13.25, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '232 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 12.7, TRUE, TRUE, 12.06, 'Las prácticas calificadas son difíciles y el tiempo es ajustado, conviene repasar desde la primera semana.', 'APROBADA', FALSE, NOW() - INTERVAL '253 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 1, 3, 2, 5, 'EXIGENTE', 12.0, FALSE, TRUE, 12.49, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '11 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 4, 5, 'EXIGENTE', 11.4, TRUE, TRUE, 12.05, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '37 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 2, 3, 4, 5, 'EXIGENTE', 12.4, TRUE, TRUE, 12.93, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 3, 3, 4, 5, 'EXIGENTE', 12.4, FALSE, TRUE, 12.09, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '99 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 3, 4, 4, 'EXIGENTE', 10.6, TRUE, TRUE, 11.36, 'Domina profundamente el tema, pero avanza muy rápido y sus exámenes tienen casos de alta complejidad.', 'APROBADA', FALSE, NOW() - INTERVAL '120 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 2, 3, 4, 4, 'EXIGENTE', 11.4, FALSE, TRUE, 14.22, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '157 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 3, 2, 4, 4, 'EXIGENTE', 10.3, FALSE, TRUE, 11.75, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '179 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 2, 2, 5, 4, 'EXIGENTE', 12.7, FALSE, TRUE, 14.32, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '207 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 2, 3, 4, 5, 'EXIGENTE', 13.6, TRUE, TRUE, 11.97, 'Pide rigor técnico en cada entrega y no perdona errores básicos; se aprende bastante si estudias diario.', 'APROBADA', FALSE, NOW() - INTERVAL '236 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 2, 2, 3, 4, 'EXIGENTE', 11.0, TRUE, TRUE, 14.0, 'Nivel de exigencia muy elevado. Hay que dedicar muchas horas fuera de clase para aprobar con buena nota.', 'APROBADA', FALSE, NOW() - INTERVAL '261 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 5, 5, 4, 5, 5, 'LIGERO', 2.4, TRUE, FALSE, 17.9, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '19 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.8, TRUE, FALSE, 17.85, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '42 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 4, 4, 'LIGERO', 2.0, FALSE, FALSE, 18.02, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '71 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.2, TRUE, TRUE, 17.6, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '94 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.3, TRUE, FALSE, 17.37, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '122 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 4, 5, 'LIGERO', 1.6, TRUE, FALSE, 18.94, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '150 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 5, 5, 4, 5, 'LIGERO', 1.9, TRUE, TRUE, 17.66, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '184 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 4, 4, 4, 'LIGERO', 1.9, TRUE, FALSE, 19.12, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '200 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 5, 4, 'LIGERO', 3.1, TRUE, FALSE, 17.39, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '233 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 4, 5, 4, 4, 4, 'LIGERO', 2.6, TRUE, FALSE, 18.53, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '264 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.6, TRUE, FALSE, 18.77, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '17 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 5, 5, 5, 4, 5, 'LIGERO', 2.5, TRUE, FALSE, 19.45, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '43 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 4, 5, 4, 'LIGERO', 2.1, TRUE, FALSE, 18.0, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '64 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 3, 5, 5, 4, 5, 'LIGERO', 2.0, TRUE, TRUE, 17.83, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '94 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 4, 5, 5, 'LIGERO', 2.7, TRUE, FALSE, 17.76, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '128 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.3, TRUE, FALSE, 18.69, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '146 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 5, 'LIGERO', 2.7, TRUE, FALSE, 18.18, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '177 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 4, 5, 4, 'LIGERO', 2.5, TRUE, FALSE, 17.36, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '201 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 4, 4, 4, 3, 'MODERADO', 1.5, TRUE, FALSE, 17.19, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '228 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 4, 5, 4, 5, 4, 'MODERADO', 1.8, TRUE, FALSE, 17.75, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '261 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 1.7, TRUE, TRUE, 17.27, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '10 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.1, TRUE, TRUE, 17.11, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '39 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 4, 5, 'LIGERO', 2.8, TRUE, FALSE, 17.48, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '70 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 5, 4, 4, 4, 'LIGERO', 2.4, TRUE, TRUE, 17.2, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '94 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 4, 4, 4, 'LIGERO', 2.9, TRUE, FALSE, 18.68, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '118 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.1, TRUE, FALSE, 18.3, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '153 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.5, TRUE, FALSE, 17.62, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '177 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 5, 4, 4, 'MODERADO', 2.9, TRUE, FALSE, 17.42, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '205 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.2, TRUE, FALSE, 18.61, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '228 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.5, TRUE, FALSE, 18.61, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '265 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 5, 5, 5, 4, 5, 'LIGERO', 2.4, TRUE, TRUE, 18.29, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '19 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.3, TRUE, FALSE, 18.35, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '47 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 5, 4, 4, 'LIGERO', 1.7, FALSE, TRUE, 18.0, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '66 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 5, 5, 4, 4, 'MODERADO', 1.7, TRUE, FALSE, 17.15, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '92 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 4, 5, 4, 4, 4, 'LIGERO', 1.6, TRUE, TRUE, 17.46, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '127 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 5, 4, 4, 'LIGERO', 1.9, TRUE, TRUE, 18.64, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '151 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 4, 5, 5, 4, 4, 'LIGERO', 1.9, TRUE, TRUE, 18.19, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '176 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 3, 4, 5, 'LIGERO', 2.4, TRUE, FALSE, 17.49, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '202 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.5, TRUE, TRUE, 18.61, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '235 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.4, TRUE, TRUE, 18.74, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '263 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 4, 5, 4, 4, 'LIGERO', 2.5, TRUE, TRUE, 17.64, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '16 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.2, TRUE, FALSE, 18.18, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '44 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 4, 4, 'MODERADO', 2.0, TRUE, TRUE, 17.53, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 5, 4, 'MODERADO', 2.6, TRUE, TRUE, 17.34, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '98 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 3, 3, 'LIGERO', 2.5, TRUE, TRUE, 18.88, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '124 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 4, 3, 4, 5, 'LIGERO', 3.0, TRUE, TRUE, 18.34, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '155 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 4, 4, 4, 3, 'LIGERO', 2.5, TRUE, FALSE, 18.31, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '182 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 5, 3, 5, 'LIGERO', 1.9, TRUE, TRUE, 17.7, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '208 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 5, 4, 4, 'LIGERO', 3.1, TRUE, FALSE, 19.87, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '228 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 5, 5, 4, 4, 'LIGERO', 2.0, TRUE, FALSE, 18.24, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '260 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.2, TRUE, FALSE, 16.5, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '13 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 5, 4, 4, 'LIGERO', 2.1, TRUE, TRUE, 17.88, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '44 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 3, 4, 5, 'LIGERO', 2.7, TRUE, FALSE, 19.68, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 3, 'LIGERO', 1.8, TRUE, FALSE, 17.17, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '101 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 4, 4, 5, 'LIGERO', 2.7, TRUE, TRUE, 18.99, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '128 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 5, 5, 5, 'LIGERO', 2.5, TRUE, TRUE, 18.32, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '153 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 5, 4, 'LIGERO', 2.3, TRUE, TRUE, 18.21, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '182 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 4, 4, 4, 4, 'LIGERO', 2.7, TRUE, TRUE, 18.06, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '199 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 4, 4, 3, 'LIGERO', 2.7, TRUE, FALSE, 18.87, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '230 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 3, 4, 'LIGERO', 1.8, TRUE, TRUE, 18.2, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '264 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 4, 5, 5, 3, 4, 'LIGERO', 1.7, TRUE, FALSE, 17.32, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '17 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 4, 4, 5, 'LIGERO', 2.4, TRUE, FALSE, 17.19, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '45 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 4, 5, 3, 4, 'LIGERO', 2.8, TRUE, FALSE, 19.15, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '74 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 4, 5, 4, 4, 4, 'LIGERO', 2.2, TRUE, TRUE, 18.92, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '92 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 5, 5, 5, 4, 5, 'LIGERO', 2.8, TRUE, FALSE, 18.18, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '130 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 4, 5, 'LIGERO', 2.5, TRUE, FALSE, 17.58, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '156 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 3, 'LIGERO', 1.6, TRUE, TRUE, 17.95, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '183 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 5, 4, 5, 'LIGERO', 2.3, TRUE, FALSE, 17.77, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '200 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 3, 5, 4, 4, 5, 4, 'LIGERO', 1.8, TRUE, FALSE, 18.48, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '237 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.2, TRUE, TRUE, 17.61, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '260 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 4, 4, 'LIGERO', 2.3, TRUE, TRUE, 17.21, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '20 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 3, 4, 5, 'LIGERO', 2.1, TRUE, FALSE, 16.95, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '47 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 4, 4, 'LIGERO', 2.2, FALSE, FALSE, 19.32, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '64 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.4, TRUE, FALSE, 19.1, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '102 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 4, 4, 5, 'LIGERO', 2.3, TRUE, FALSE, 19.07, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '128 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 4, 4, 4, 4, 'LIGERO', 2.2, TRUE, FALSE, 17.69, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '145 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 4, 'MODERADO', 3.3, TRUE, FALSE, 18.5, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '182 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 4, 5, 5, 4, 5, 'LIGERO', 2.8, TRUE, FALSE, 18.44, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '204 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 5, 5, 4, 'LIGERO', 1.6, TRUE, TRUE, 17.66, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '233 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 4, 4, 4, 4, 'LIGERO', 2.7, TRUE, TRUE, 17.87, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '265 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 4, 5, 4, 4, 4, 'LIGERO', 3.3, TRUE, FALSE, 19.16, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '13 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 5, 4, 3, 'LIGERO', 1.7, TRUE, TRUE, 16.78, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '48 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 5, 5, 5, 'LIGERO', 1.9, TRUE, TRUE, 18.52, 'Docente súper accesible para resolver dudas por plataforma y flexible ante imprevistos justificados.', 'APROBADA', FALSE, NOW() - INTERVAL '74 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 4, 4, 4, 3, 4, 'LIGERO', 2.5, TRUE, TRUE, 17.96, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '95 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 5, 5, 4, 4, 5, 'LIGERO', 2.5, TRUE, TRUE, 17.63, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '118 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 4, 4, 'LIGERO', 2.6, TRUE, FALSE, 17.73, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '147 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 4, 'LIGERO', 2.3, TRUE, FALSE, 16.5, 'Hace las clases muy dinámicas con ejemplos cotidianos; excelente ambiente y carga bastante llevadera.', 'APROBADA', FALSE, NOW() - INTERVAL '176 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 4, 4, 4, 5, 'LIGERO', 2.3, TRUE, FALSE, 18.36, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '208 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 4, 4, 4, 4, 'LIGERO', 2.5, TRUE, TRUE, 17.02, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '228 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 5, 5, 4, 4, 'LIGERO', 2.8, TRUE, FALSE, 16.94, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '264 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 5, 4, 4, 4, 'LIGERO', 2.3, TRUE, FALSE, 18.29, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '17 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 4, 4, 5, 'LIGERO', 1.9, TRUE, FALSE, 18.6, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '47 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 5, 3, 4, 'LIGERO', 2.2, TRUE, FALSE, 16.5, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '65 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 5, 4, 5, 'LIGERO', 3.5, TRUE, FALSE, 18.67, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '101 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 4, 5, 4, 4, 4, 'LIGERO', 2.6, TRUE, FALSE, 17.37, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '124 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 4, 5, 4, 5, 4, 'LIGERO', 2.4, TRUE, TRUE, 18.93, 'Muy empático y paciente, explica cuantas veces haga falta para que todo el salón entienda el procedimiento.', 'APROBADA', FALSE, NOW() - INTERVAL '150 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 4, 5, 5, 4, 4, 'LIGERO', 2.0, TRUE, TRUE, 17.52, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '174 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 4, 5, 5, 4, 4, 5, 'LIGERO', 2.2, TRUE, FALSE, 18.05, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '200 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 3, 5, 5, 4, 4, 4, 'LIGERO', 2.4, TRUE, TRUE, 17.7, 'Los talleres guiados en clase permiten avanzar sin estrés y obtener buenas calificaciones si asistes.', 'APROBADA', FALSE, NOW() - INTERVAL '233 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 5, 5, 4, 5, 4, 'LIGERO', 2.1, TRUE, FALSE, 17.83, 'Ideal para entender las bases sin abrumarse; las evaluaciones siguen exactamente lo visto en clase.', 'APROBADA', FALSE, NOW() - INTERVAL '261 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 2, 2, 2, 2, 1, 'EXIGENTE', 5.8, FALSE, TRUE, 11.42, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '13 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 2, 2, 2, 'MODERADO', 5.8, FALSE, FALSE, 12.61, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '41 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 3, 2, 2, 2, 2, 2, 'MODERADO', 7.7, FALSE, TRUE, 12.36, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '65 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 2, 1, 2, 'EXIGENTE', 5.9, FALSE, FALSE, 12.66, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '96 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 2, 2, 2, 'EXIGENTE', 5.6, FALSE, FALSE, 11.04, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '119 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 1, 2, 2, 'MODERADO', 5.3, FALSE, TRUE, 11.07, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '146 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 1, 1, 2, 2, 'EXIGENTE', 5.9, TRUE, FALSE, 14.5, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '182 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 1, 2, 3, 'MODERADO', 5.7, FALSE, TRUE, 12.24, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '209 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 2, 2, 2, 'MODERADO', 7.8, FALSE, FALSE, 12.44, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '231 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 3, 2, 2, 2, 2, 'MODERADO', 5.4, FALSE, TRUE, 11.92, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '261 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 3, 2, 2, 2, 'EXIGENTE', 5.4, FALSE, TRUE, 12.56, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '14 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 2, 2, 2, 'MODERADO', 5.0, FALSE, TRUE, 11.99, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '47 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 3, 1, 1, 3, 'MODERADO', 7.7, FALSE, TRUE, 11.85, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 3, 2, 2, 'EXIGENTE', 6.7, FALSE, TRUE, 12.55, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '103 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 2, 2, 2, 2, 2, 'MODERADO', 6.3, FALSE, FALSE, 12.87, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '121 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 1, 1, 2, 'MODERADO', 6.2, FALSE, FALSE, 11.79, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '150 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 2, 2, 2, 1, 3, 'MODERADO', 6.3, FALSE, TRUE, 13.01, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '179 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 3, 1, 2, 2, 3, 'MODERADO', 5.8, TRUE, TRUE, 12.0, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '207 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'MAT-102'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 1, 2, 2, 'MODERADO', 7.7, FALSE, FALSE, 13.72, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '238 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 2, 2, 2, 'EXIGENTE', 5.1, FALSE, TRUE, 12.49, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '258 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 2, 1, 3, 'MODERADO', 5.2, FALSE, FALSE, 11.69, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '15 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 1, 2, 1, 1, 3, 'MODERADO', 6.7, FALSE, TRUE, 12.73, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '38 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 2, 2, 3, 'MODERADO', 4.7, FALSE, FALSE, 12.91, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '70 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 1, 2, 2, 'MODERADO', 6.6, TRUE, FALSE, 12.66, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '91 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 2, 2, 3, 'EXIGENTE', 6.2, FALSE, FALSE, 12.93, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '126 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 3, 2, 2, 1, 1, 3, 'MODERADO', 6.3, FALSE, FALSE, 13.27, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '154 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 1, 1, 2, 'EXIGENTE', 5.8, TRUE, TRUE, 12.37, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '176 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 1, 1, 3, 'MODERADO', 8.3, FALSE, TRUE, 11.27, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '211 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 1, 2, 2, 2, 2, 'MODERADO', 6.1, FALSE, TRUE, 11.03, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '232 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Marco Antonio Zavala'), (SELECT id FROM cursos WHERE codigo = 'CIV-202'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 3, 3, 1, 2, 2, 'EXIGENTE', 6.7, FALSE, TRUE, 11.43, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '254 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 1, 2, 3, 'EXIGENTE', 8.5, FALSE, TRUE, 12.63, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '21 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 2, 1, 3, 'EXIGENTE', 4.8, FALSE, FALSE, 12.66, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '37 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 2, 2, 2, 'EXIGENTE', 7.5, FALSE, FALSE, 13.37, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 2, 2, 2, 2, 2, 'MODERADO', 8.4, FALSE, FALSE, 11.79, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '95 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 3, 1, 2, 3, 'MODERADO', 6.2, FALSE, TRUE, 12.79, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '118 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 1, 2, 2, 'MODERADO', 6.1, FALSE, FALSE, 11.55, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '145 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 1, 2, 1, 2, 4, 'EXIGENTE', 6.5, FALSE, TRUE, 10.67, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '177 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 3, 2, 2, 2, 3, 'MODERADO', 6.7, FALSE, TRUE, 13.07, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '200 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 3, 2, 2, 2, 2, 2, 'MODERADO', 6.5, FALSE, FALSE, 12.46, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '231 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 1, 2, 2, 1, 2, 'MODERADO', 5.8, TRUE, FALSE, 13.46, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '253 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 2, 2, 3, 'MODERADO', 5.1, FALSE, TRUE, 12.38, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '19 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 3, 2, 2, 2, 2, 2, 'EXIGENTE', 7.5, FALSE, TRUE, 12.73, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '49 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 3, 2, 1, 2, 2, 2, 'MODERADO', 6.0, FALSE, TRUE, 12.25, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '72 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 2, 2, 3, 'MODERADO', 5.8, FALSE, FALSE, 13.08, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '103 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 1, 1, 2, 'EXIGENTE', 4.5, FALSE, TRUE, 11.35, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '129 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 1, 2, 2, 2, 2, 'EXIGENTE', 5.5, FALSE, FALSE, 12.59, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '153 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 4, 2, 2, 2, 2, 1, 'EXIGENTE', 7.3, FALSE, FALSE, 11.78, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '172 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 2, 2, 3, 'MODERADO', 4.8, FALSE, FALSE, 13.48, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '201 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 3, 1, 1, 1, 1, 2, 'EXIGENTE', 6.1, TRUE, FALSE, 12.13, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '232 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), (SELECT id FROM cursos WHERE codigo = 'SOF-302'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 3, 2, 2, 1, 2, 1, 'MODERADO', 6.2, FALSE, TRUE, 12.08, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '258 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 18.9, 'Para mí fue espectacular, exige a su manera pero conecté genial con su metodología y saqué sobresaliente.', 'APROBADA', FALSE, NOW() - INTERVAL '10 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 10.83, 'No lo recomiendo para nada, clases caóticas y calificaciones que no reflejan el esfuerzo entregado.', 'APROBADA', FALSE, NOW() - INTERVAL '44 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 17.68, 'Excelente experiencia en clase, muy inspirador y resolvió todas mis dudas sobre el proyecto final.', 'APROBADA', FALSE, NOW() - INTERVAL '68 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 9.99, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '96 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 18.45, 'Para mí fue espectacular, exige a su manera pero conecté genial con su metodología y saqué sobresaliente.', 'APROBADA', FALSE, NOW() - INTERVAL '126 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 9.66, 'No lo recomiendo para nada, clases caóticas y calificaciones que no reflejan el esfuerzo entregado.', 'APROBADA', FALSE, NOW() - INTERVAL '153 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 19.05, 'Para mí fue espectacular, exige a su manera pero conecté genial con su metodología y saqué sobresaliente.', 'APROBADA', FALSE, NOW() - INTERVAL '184 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 10.2, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '206 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 18.8, 'Para mí fue espectacular, exige a su manera pero conecté genial con su metodología y saqué sobresaliente.', 'APROBADA', FALSE, NOW() - INTERVAL '234 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 11.49, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '256 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 18.03, 'Excelente experiencia en clase, muy inspirador y resolvió todas mis dudas sobre el proyecto final.', 'APROBADA', FALSE, NOW() - INTERVAL '15 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 11.31, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '38 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 18.35, 'Excelente experiencia en clase, muy inspirador y resolvió todas mis dudas sobre el proyecto final.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 9.86, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '103 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 17.84, 'Excelente experiencia en clase, muy inspirador y resolvió todas mis dudas sobre el proyecto final.', 'APROBADA', FALSE, NOW() - INTERVAL '127 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 10.11, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '152 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 19.35, 'Para mí fue espectacular, exige a su manera pero conecté genial con su metodología y saqué sobresaliente.', 'APROBADA', FALSE, NOW() - INTERVAL '175 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 9.39, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '200 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'IND-305'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'LIGERO', 3.5, TRUE, TRUE, 17.99, 'Para mí fue espectacular, exige a su manera pero conecté genial con su metodología y saqué sobresaliente.', 'APROBADA', FALSE, NOW() - INTERVAL '230 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 12.0, FALSE, TRUE, 9.86, 'Experiencia pésima en el curso, criterios totalmente inconsistentes y cero apoyo cuando pedí orientación.', 'APROBADA', FALSE, NOW() - INTERVAL '257 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 2, 2, 2, 2, 1, 2, 'MODERADO', 5.3, FALSE, FALSE, 12.75, 'Poca organización con las fechas de entregas y retroalimentación muy escasa sobre los exámenes corregidos.', 'APROBADA', FALSE, NOW() - INTERVAL '21 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 2, 2, 2, 2, 'MODERADO', 4.8, FALSE, FALSE, 12.89, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '37 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 2, 2, 2, 2, 2, 'MODERADO', 5.8, FALSE, FALSE, 11.54, 'Material desactualizado y clases monótonas; terminé estudiando casi todo el temario por cuenta propia.', 'APROBADA', FALSE, NOW() - INTERVAL '67 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 1, 2, 2, 2, 2, 2, 'MODERADO', 4.8, FALSE, FALSE, 13.43, 'Suele leer diapositivas sin explicar ejemplos paso a paso y cuesta seguir el hilo durante la sesión.', 'APROBADA', FALSE, NOW() - INTERVAL '91 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 2, 2, 1, 2, 2, 2, 'MODERADO', 5.0, FALSE, FALSE, 12.1, 'Las instrucciones de los trabajos resultan ambiguas y rara vez se resuelven consultas a tiempo.', 'APROBADA', FALSE, NOW() - INTERVAL '130 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 1, 5, 1, 'LIGERO', 0.5, TRUE, FALSE, 20.0, 'SUPER RECOMENDADO EL MEJOR PROFE DEL PERU MATRICULENSE TODOS YA MISMO SIN PENSARLO!!', 'RECHAZADA', TRUE, NOW() - INTERVAL '20 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 5, 5, 2, 5, 2, 'LIGERO', 0.9, TRUE, FALSE, 20.0, 'INCREIBLE DOCENTE PONE VEINTE A TODOS SIEMPRE PASAS FACILISIMO SIN ESTUDIAR NADA!!', 'RECHAZADA', TRUE, NOW() - INTERVAL '25 days' - INTERVAL '1 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 1, 5, 3, 'LIGERO', 1.3, TRUE, FALSE, 20.0, 'EXCELENTE CURSO REGALA PUNTOS EXTRA EN CADA PRACTICA EL MEJOR DE TODA LA UTP SIN DUDA', 'RECHAZADA', TRUE, NOW() - INTERVAL '30 days' - INTERVAL '2 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 5, 5, 2, 5, 1, 'LIGERO', 1.7, TRUE, FALSE, 20.0, 'EL MAS FACIL DE APROBAR NO DEJA TAREAS Y TODOS SACAN BUENA NOTA ASEGURADA GARANTIZADO', 'RECHAZADA', TRUE, NOW() - INTERVAL '35 days' - INTERVAL '3 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 1, 5, 2, 'LIGERO', 2.1, TRUE, FALSE, 20.0, 'LO MAXIMO EN DESARROLLO WEB INSCRIBANSE RAPIDO ANTES QUE SE ACABEN LOS CUPOS HOY MISMO', 'RECHAZADA', TRUE, NOW() - INTERVAL '40 days' - INTERVAL '4 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 2, 5, 3, 'LIGERO', 2.5, TRUE, FALSE, 20.0, 'APROBADO GARANTIZADO CON ESTE PROFE NO IMPORTA SI NO ASISTES NUNCA A LAS CLASES VIRTUALES', 'RECHAZADA', TRUE, NOW() - INTERVAL '45 days' - INTERVAL '5 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 26.0, FALSE, TRUE, 11.13, 'El profesor es una eminencia pero exige más de veinte horas semanales entre lecturas y proyectos maratónicos.', 'APROBADA', FALSE, NOW() - INTERVAL '18 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 22.6, FALSE, TRUE, 10.18, 'Dominio impecable del tema, sin embargo el trato es muy frío y la carga de trabajos resulta casi inhumana.', 'APROBADA', FALSE, NOW() - INTERVAL '47 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 26.3, FALSE, TRUE, 10.72, 'El profesor es una eminencia pero exige más de veinte horas semanales entre lecturas y proyectos maratónicos.', 'APROBADA', FALSE, NOW() - INTERVAL '70 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 24.4, FALSE, TRUE, 10.35, 'Dominio impecable del tema, sin embargo el trato es muy frío y la carga de trabajos resulta casi inhumana.', 'APROBADA', FALSE, NOW() - INTERVAL '100 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 24.8, FALSE, TRUE, 10.66, 'El profesor es una eminencia pero exige más de veinte horas semanales entre lecturas y proyectos maratónicos.', 'APROBADA', FALSE, NOW() - INTERVAL '120 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 24.9, FALSE, TRUE, 11.3, 'El profesor es una eminencia pero exige más de veinte horas semanales entre lecturas y proyectos maratónicos.', 'APROBADA', FALSE, NOW() - INTERVAL '151 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 22.3, FALSE, TRUE, 9.64, 'El profesor es una eminencia pero exige más de veinte horas semanales entre lecturas y proyectos maratónicos.', 'APROBADA', FALSE, NOW() - INTERVAL '174 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-2'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 25.7, FALSE, TRUE, 9.79, 'El profesor es una eminencia pero exige más de veinte horas semanales entre lecturas y proyectos maratónicos.', 'APROBADA', FALSE, NOW() - INTERVAL '211 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-501'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 23.6, FALSE, TRUE, 10.39, 'Dominio impecable del tema, sin embargo el trato es muy frío y la carga de trabajos resulta casi inhumana.', 'APROBADA', FALSE, NOW() - INTERVAL '228 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2025-1'), 5, 3, 1, 1, 4, 5, 'EXIGENTE', 22.4, FALSE, TRUE, 9.76, 'El profesor es una eminencia pero exige más de veinte horas semanales entre lecturas y proyectos maratónicos.', 'APROBADA', FALSE, NOW() - INTERVAL '265 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 4, 5, 5, 'LIGERO', 6.3, TRUE, TRUE, 17.05, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'PENDIENTE', FALSE, NOW() - INTERVAL '1 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 5, 5, 5, 5, 'MODERADO', 3.9, TRUE, TRUE, 17.59, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'PENDIENTE', FALSE, NOW() - INTERVAL '2 days' - INTERVAL '1 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 5, 'MODERADO', 4.6, TRUE, TRUE, 15.38, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'PENDIENTE', FALSE, NOW() - INTERVAL '3 days' - INTERVAL '2 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 4, 5, 4, 4, 5, 4, 'EXIGENTE', 4.6, TRUE, TRUE, 15.81, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'PENDIENTE', FALSE, NOW() - INTERVAL '1 days' - INTERVAL '3 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 4, 5, 5, 5, 'MODERADO', 4.5, TRUE, TRUE, 17.19, 'Se nota su dominio del curso y su vocación docente; las rúbricas son transparentes y justas.', 'PENDIENTE', FALSE, NOW() - INTERVAL '2 days' - INTERVAL '4 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 4, 5, 5, 5, 4, 'MODERADO', 5.6, TRUE, TRUE, 16.95, 'Uno de los mejores docentes de la facultad: explica con calma, revisa avances y motiva a participar.', 'PENDIENTE', FALSE, NOW() - INTERVAL '3 days' - INTERVAL '5 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 4, 5, 5, 'MODERADO', 6.2, TRUE, TRUE, 15.77, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'PENDIENTE', FALSE, NOW() - INTERVAL '1 days' - INTERVAL '6 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 4, 5, 5, 4, 'LIGERO', 4.9, TRUE, TRUE, 17.46, 'Excelente organización semanal; responde todas las dudas con paciencia y da retroalimentación oportuna.', 'PENDIENTE', FALSE, NOW() - INTERVAL '2 days' - INTERVAL '7 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 4, 5, 'MODERADO', 5.5, TRUE, TRUE, 15.26, 'Combina teoría precisa con casos aplicados reales. Muy puntual y siempre dispuesto a orientar al grupo.', 'PENDIENTE', FALSE, NOW() - INTERVAL '3 days' - INTERVAL '8 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 5, 5, 5, 5, 4, 'MODERADO', 6.0, TRUE, TRUE, 17.52, 'Las sesiones son muy claras y participativas. Si resuelves los talleres semanales llegas preparado al examen.', 'PENDIENTE', FALSE, NOW() - INTERVAL '1 days' - INTERVAL '9 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), (SELECT id FROM cursos WHERE codigo = 'SIS-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 1, 1, 1, 5, 'EXIGENTE', 28.0, FALSE, TRUE, 3.0, 'PESIMO PESIMO NO SIRVE PARA NADA NO SE METAN CON ESTE DOCENTE NUNCA JAMAS!!', 'PENDIENTE', TRUE, NOW() - INTERVAL '1 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), (SELECT id FROM cursos WHERE codigo = 'MAT-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 2, 5, 1, 5, 'EXIGENTE', 34.0, FALSE, TRUE, 2.5, 'HORRIBLE CLASE PERDIDA DE TIEMPO TOTAL NO EXPLICO NADA DE NADA REPROBADOS TODOS', 'PENDIENTE', TRUE, NOW() - INTERVAL '1 days' - INTERVAL '1 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), (SELECT id FROM cursos WHERE codigo = 'SIS-301'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 2, 1, 1, 5, 1, 'LIGERO', 1.0, FALSE, TRUE, 19.5, 'TERRIBLE EXPERIENCIA CERO RECOMENDADO CAMBIENSE DE SECCION INMEDIATAMENTE TODOS Y YA', 'PENDIENTE', TRUE, NOW() - INTERVAL '1 days' - INTERVAL '2 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 5, 1, 1, 5, 1, 1, 'EXIGENTE', 39.0, FALSE, TRUE, 5.0, 'NO RECOMIENDO PARA NADA ES LO PEOR DE LA UNIVERSIDAD EVITEN MATRICULARSE AQUI AHORA MISMO!!', 'PENDIENTE', TRUE, NOW() - INTERVAL '1 days' - INTERVAL '3 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno49@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), (SELECT id FROM cursos WHERE codigo = 'SIS-402'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 1, 1, 1, 1, 'EXIGENTE', 22.0, FALSE, TRUE, 1.0, 'BASURA DE CURSO NO APRENDI ABSOLUTAMENTE NADA Y PONE PUROS CEROS SIN MOTIVO ALGUNO EN EXAMEN', 'PENDIENTE', TRUE, NOW() - INTERVAL '1 days' - INTERVAL '4 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), (SELECT id FROM cursos WHERE codigo = 'SOF-401'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 5, 1, 5, 1, 5, 'EXIGENTE', 31.0, FALSE, TRUE, 4.0, 'DESASTRE TOTAL NO SABE ENSENAR NADA PERDIDA COMPLETA DE DINERO Y TIEMPO EN TODO EL CICLO!!', 'PENDIENTE', TRUE, NOW() - INTERVAL '2 days' - INTERVAL '0 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), (SELECT id FROM cursos WHERE codigo = 'IND-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 1, 4, 1, 5, 'LIGERO', 0.5, FALSE, TRUE, 1.5, 'EVITEN ESTE DOCENTE POR FAVOR TODO MAL DESDE LA SEMANA UNO HASTA EL EXAMEN FINAL DE CURSO', 'PENDIENTE', TRUE, NOW() - INTERVAL '2 days' - INTERVAL '1 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), (SELECT id FROM cursos WHERE codigo = 'ADM-201'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 2, 1, 1, 1, 5, 5, 'EXIGENTE', 36.0, FALSE, TRUE, 6.0, 'FATAL FATAL FATAL NO ENTIENDO COMO SIGUE DICTANDO EN LA FACULTAD NADIE APRUEBA CON EL NUNCA', 'PENDIENTE', TRUE, NOW() - INTERVAL '2 days' - INTERVAL '2 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), (SELECT id FROM cursos WHERE codigo = 'SIS-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 2, 1, 1, 4, 'EXIGENTE', 26.5, FALSE, TRUE, 3.5, 'PESIMA EXPERIENCIA NO LO ELIJAN JAMAS EN MATRICULA ES UNA TRAMPA TOTAL PARA BAJAR PROMEDIO', 'PENDIENTE', TRUE, NOW() - INTERVAL '2 days' - INTERVAL '3 hours'),
  ((SELECT id FROM usuarios WHERE correo = 'alumno50@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), (SELECT id FROM cursos WHERE codigo = 'PSI-101'), (SELECT id FROM periodos_academicos WHERE codigo = '2026-1'), 1, 1, 1, 5, 5, 1, 'EXIGENTE', 33.0, FALSE, TRUE, 0.5, 'CERO ESTRELLAS SI SE PUDIERA PONER UN DESASTRE ABSOLUTO EN CLASES Y EN CALIFICACION FINAL!!', 'PENDIENTE', TRUE, NOW() - INTERVAL '2 days' - INTERVAL '4 hours')
ON CONFLICT (usuario_id, docente_id, curso_id, periodo_id) DO NOTHING;

-- 8.9 Docentes guardados (373 favoritos de pre-matrícula)
INSERT INTO docentes_guardados (usuario_id, docente_id, prioridad) VALUES
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno25@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Carlos Ramírez Salazar'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'María Fernanda Paredes'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Luis Alberto Torres'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ana Lucía Vega'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ricardo Manuel Huertas'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Patricia Elena Solís'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno25@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Fernando José Delgado'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Gabriela Sofía Navarro'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno25@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno27@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Humberto César Palacios'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno25@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno32@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Verónica Isabel Cárdenas'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno34@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno28@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Martín Eduardo Chávez'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Jorge Luis Quispe'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Guillermo Arturo Salazar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Ernesto Raúl Benítez'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Mónica Liliana Serrano'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Víctor Hugo Carrasco'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Alberto Enrique Figueroa'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno37@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'César Augusto Mendoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno48@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rocío del Pilar Valdivia'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Óscar Javier Tapia'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno38@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno46@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Héctor Darío Córdova'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rosa Elena Mendoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Claudia Beatriz Romero'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Diego Armando Cruz'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lucía Milagros Ortiz'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Pablo Andrés Lozano'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Silvia Lorena Guzmán'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Javier Alonso Pacheco'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Karina Estefanía Ríos'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Renzo Fabián Aguilar'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno13@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Paola Cristina Campos'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Rodolfo Segundo Peña'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Nelly Rosario Huamán'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Lourdes Maribel Bautista'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno11@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Enrique Oswaldo Miranda'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Esteban Mauricio León'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno2@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Vanessa Lucero Cabrera'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno29@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno45@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno43@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno22@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno20@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno14@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno8@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno1@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno7@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno26@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno39@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno40@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno44@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno15@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno30@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno6@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno19@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno10@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno21@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno16@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno47@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno4@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno42@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno41@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno17@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno33@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 5),
  ((SELECT id FROM usuarios WHERE correo = 'alumno24@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno18@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno12@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno5@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 4),
  ((SELECT id FROM usuarios WHERE correo = 'alumno3@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno35@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Cristian Omar Espinoza'), 1),
  ((SELECT id FROM usuarios WHERE correo = 'alumno36@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), 3),
  ((SELECT id FROM usuarios WHERE correo = 'alumno23@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno9@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), 2),
  ((SELECT id FROM usuarios WHERE correo = 'alumno31@utp.edu.pe'), (SELECT id FROM docentes WHERE nombre = 'Teodoro Nicolás Vargas'), 5)
ON CONFLICT (usuario_id, docente_id) DO NOTHING;

-- 8.10 Votos de utilidad en reseñas aprobadas (muestra determinística)
INSERT INTO resena_votos (resena_id, usuario_id, es_util)
SELECT r.id, u.id, TRUE
FROM resenas r
JOIN usuarios u ON u.rol = 'ESTUDIANTE' AND u.id <> r.usuario_id
WHERE r.estado = 'APROBADA'
  AND ((r.id * 7 + u.id * 13) % 19 = 0)
ON CONFLICT (resena_id, usuario_id) DO NOTHING;

-- 8.11 Reportes de abuso sobre reseñas sospechosas/spam (con intensidad variada para DBSCAN)
INSERT INTO resena_reportes (resena_id, usuario_id, motivo, detalle)
SELECT r.id, u.id, 'SPAM', 'Comentario en mayúsculas y calificación extrema inconsistente.'
FROM resenas r
JOIN usuarios u ON u.correo IN (
  'alumno1@utp.edu.pe', 'alumno2@utp.edu.pe', 'alumno3@utp.edu.pe',
  'alumno4@utp.edu.pe', 'alumno5@utp.edu.pe', 'alumno6@utp.edu.pe'
)
WHERE r.es_anomalia_ml = TRUE
  AND u.id <> r.usuario_id
  AND ((r.id + u.id) % 5 <> 0)
ON CONFLICT (resena_id, usuario_id) DO NOTHING;

-- 8.12 Historial de moderación inicial para reseñas rechazadas
INSERT INTO moderacion_historial (resena_id, admin_id, estado_anterior, estado_nuevo, observacion)
SELECT
  r.id,
  (SELECT id FROM usuarios WHERE correo = 'admin@utp.edu.pe'),
  'PENDIENTE',
  'RECHAZADA',
  'Contenido promocional o sospechoso detectado en revisión inicial.'
FROM resenas r
WHERE r.estado = 'RECHAZADA'
  AND NOT EXISTS (
    SELECT 1 FROM moderacion_historial mh WHERE mh.resena_id = r.id
  );

COMMIT;
