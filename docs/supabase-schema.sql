-- ═══════════════════════════════════════════════════════════════
-- JORGE DÍAZ · SCHEMA SUPABASE v2.0 (RECASUR)
-- Actualización con scoring multirrubro + alerta Dimarsa
-- Ejecutar en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Si ya tienes la tabla de v1, ejecuta primero estas ALTER:
-- (Si es instalación nueva, salta al CREATE TABLE más abajo)

-- Agregar columnas nuevas a tabla existente
ALTER TABLE licitaciones
  ADD COLUMN IF NOT EXISTS region                TEXT,
  ADD COLUMN IF NOT EXISTS rubro_principal       TEXT,
  ADD COLUMN IF NOT EXISTS nivel_rubro           TEXT CHECK (nivel_rubro IN ('fuerte', 'mixto', 'debil', 'secundario', 'warm_general')),
  ADD COLUMN IF NOT EXISTS cliente_detectado     TEXT,
  ADD COLUMN IF NOT EXISTS region_detectada      TEXT,
  ADD COLUMN IF NOT EXISTS competidores_detectados TEXT,
  ADD COLUMN IF NOT EXISTS alerta_dimarsa        BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sugerencia_tactica    TEXT;

-- ─────────────────────────────────────────────────────────────
-- SCHEMA COMPLETO (para instalación nueva)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS licitaciones (
  id                BIGSERIAL PRIMARY KEY,
  codigo_externo    TEXT UNIQUE NOT NULL,
  nombre            TEXT NOT NULL,
  descripcion       TEXT,
  organismo         TEXT,
  codigo_organismo  TEXT,
  region            TEXT,
  monto_estimado    NUMERIC(15, 2) DEFAULT 0,
  moneda            TEXT DEFAULT 'CLP',
  fecha_publicacion TIMESTAMPTZ,
  fecha_cierre      TIMESTAMPTZ,
  dias_al_cierre    INTEGER,
  estado            TEXT,
  tipo              TEXT,
  -- Scoring
  score             INTEGER DEFAULT 0,
  categoria         TEXT CHECK (categoria IN ('hot', 'warm', 'cold')),
  rubro_principal   TEXT,
  nivel_rubro       TEXT CHECK (nivel_rubro IN ('fuerte', 'mixto', 'debil', 'secundario', 'warm_general')),
  matches           TEXT,
  -- Inteligencia competitiva
  cliente_detectado       TEXT,
  region_detectada        TEXT,
  competidores_detectados TEXT,
  alerta_dimarsa          BOOLEAN DEFAULT FALSE,
  sugerencia_tactica      TEXT,
  -- Links
  url_ficha         TEXT,
  -- Gestión interna Jorge
  postulamos        BOOLEAN DEFAULT FALSE,
  resultado         TEXT CHECK (resultado IN ('ganada', 'perdida', 'desierta', 'pendiente') OR resultado IS NULL),
  monto_ofertado    NUMERIC(15, 2),
  notas             TEXT,
  -- Timestamps
  capturado_en      TIMESTAMPTZ DEFAULT NOW(),
  actualizado_en    TIMESTAMPTZ DEFAULT NOW()
);

-- Índices optimizados
CREATE INDEX IF NOT EXISTS idx_licitaciones_categoria ON licitaciones(categoria);
CREATE INDEX IF NOT EXISTS idx_licitaciones_score ON licitaciones(score DESC);
CREATE INDEX IF NOT EXISTS idx_licitaciones_fecha_cierre ON licitaciones(fecha_cierre);
CREATE INDEX IF NOT EXISTS idx_licitaciones_organismo ON licitaciones(organismo);
CREATE INDEX IF NOT EXISTS idx_licitaciones_rubro ON licitaciones(rubro_principal);
CREATE INDEX IF NOT EXISTS idx_licitaciones_region ON licitaciones(region_detectada);
CREATE INDEX IF NOT EXISTS idx_licitaciones_dimarsa ON licitaciones(alerta_dimarsa) WHERE alerta_dimarsa = TRUE;

-- ═══════════════════════════════════════════════════════════════
-- VISTAS ESPECÍFICAS PARA JORGE DÍAZ · RECASUR
-- ═══════════════════════════════════════════════════════════════

-- Vista principal del dashboard: hoy priorizadas
CREATE OR REPLACE VIEW vw_dashboard_hoy AS
SELECT
  codigo_externo,
  nombre,
  organismo,
  region,
  region_detectada,
  cliente_detectado,
  monto_estimado,
  dias_al_cierre,
  score,
  categoria,
  rubro_principal,
  nivel_rubro,
  matches,
  competidores_detectados,
  alerta_dimarsa,
  sugerencia_tactica,
  url_ficha,
  CASE
    WHEN alerta_dimarsa THEN 'CRÍTICA'
    WHEN dias_al_cierre <= 3 THEN 'URGENTE'
    WHEN dias_al_cierre <= 7 THEN 'PRONTO'
    ELSE 'NORMAL'
  END AS prioridad
FROM licitaciones
WHERE estado IN ('publicada', 'activa')
  AND dias_al_cierre > 0
  AND dias_al_cierre <= 60
ORDER BY
  alerta_dimarsa DESC,
  score DESC,
  dias_al_cierre ASC;

-- Alertas Dimarsa activas
CREATE OR REPLACE VIEW vw_alertas_dimarsa AS
SELECT
  codigo_externo,
  nombre,
  organismo,
  monto_estimado,
  dias_al_cierre,
  rubro_principal,
  competidores_detectados,
  sugerencia_tactica,
  url_ficha
FROM licitaciones
WHERE alerta_dimarsa = TRUE
  AND estado IN ('publicada', 'activa')
  AND dias_al_cierre > 0
ORDER BY score DESC;

-- Oportunidades en Magallanes (ventaja logística)
CREATE OR REPLACE VIEW vw_oportunidades_magallanes AS
SELECT
  codigo_externo,
  nombre,
  organismo,
  monto_estimado,
  dias_al_cierre,
  score,
  rubro_principal,
  sugerencia_tactica,
  url_ficha
FROM licitaciones
WHERE region_detectada IN ('MAGALLANES', 'ANTARTICA', 'AYSEN', 'AYSÉN')
  AND estado IN ('publicada', 'activa')
  AND dias_al_cierre > 0
ORDER BY score DESC;

-- KPIs ejecutivos actualizados
CREATE OR REPLACE VIEW vw_kpis AS
SELECT
  COUNT(*) FILTER (WHERE estado = 'publicada' AND dias_al_cierre > 0) AS activas_hoy,
  COUNT(*) FILTER (WHERE capturado_en >= CURRENT_DATE) AS nuevas_hoy,
  COUNT(*) FILTER (WHERE categoria = 'hot' AND dias_al_cierre > 0) AS hot_activas,
  COUNT(*) FILTER (WHERE alerta_dimarsa = TRUE AND dias_al_cierre > 0) AS alertas_dimarsa_activas,
  COUNT(*) FILTER (WHERE dias_al_cierre BETWEEN 1 AND 7) AS cierran_semana,
  COUNT(*) FILTER (WHERE region_detectada IN ('MAGALLANES','ANTARTICA') AND dias_al_cierre > 0) AS oportunidades_magallanes,
  COALESCE(SUM(monto_estimado) FILTER (WHERE estado = 'publicada' AND dias_al_cierre > 0), 0) AS pipeline_clp,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE resultado = 'ganada') /
    NULLIF(COUNT(*) FILTER (WHERE postulamos = TRUE), 0),
    1
  ) AS tasa_adjudicacion_pct
FROM licitaciones;

-- Pipeline por rubro (para analítica de negocio)
CREATE OR REPLACE VIEW vw_pipeline_por_rubro AS
SELECT
  rubro_principal,
  nivel_rubro,
  COUNT(*) AS total_activas,
  SUM(monto_estimado) AS pipeline_total,
  AVG(score) AS score_promedio,
  COUNT(*) FILTER (WHERE alerta_dimarsa = TRUE) AS con_dimarsa
FROM licitaciones
WHERE estado IN ('publicada', 'activa')
  AND dias_al_cierre > 0
  AND rubro_principal IS NOT NULL
GROUP BY rubro_principal, nivel_rubro
ORDER BY pipeline_total DESC;

-- Performance histórica (para reporte a Jorge Guic)
CREATE OR REPLACE VIEW vw_performance_mensual AS
SELECT
  DATE_TRUNC('month', actualizado_en) AS mes,
  COUNT(*) FILTER (WHERE postulamos = TRUE) AS postuladas,
  COUNT(*) FILTER (WHERE resultado = 'ganada') AS ganadas,
  COUNT(*) FILTER (WHERE resultado = 'perdida') AS perdidas,
  COALESCE(SUM(monto_ofertado) FILTER (WHERE resultado = 'ganada'), 0) AS monto_ganado_clp,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE resultado = 'ganada') /
    NULLIF(COUNT(*) FILTER (WHERE postulamos = TRUE), 0),
    1
  ) AS tasa_exito_pct
FROM licitaciones
WHERE postulamos = TRUE
GROUP BY mes
ORDER BY mes DESC;

-- ═══════════════════════════════════════════════════════════════
-- TRIGGER: actualizar `actualizado_en` en cada cambio
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION touch_actualizado_en()
RETURNS TRIGGER AS $$
BEGIN
  NEW.actualizado_en = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_licitaciones_touch ON licitaciones;
CREATE TRIGGER trg_licitaciones_touch
  BEFORE UPDATE ON licitaciones
  FOR EACH ROW EXECUTE FUNCTION touch_actualizado_en();

-- ═══════════════════════════════════════════════════════════════
-- RLS (Row Level Security)
-- ═══════════════════════════════════════════════════════════════
ALTER TABLE licitaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "lectura_autenticados" ON licitaciones;
CREATE POLICY "lectura_autenticados" ON licitaciones
  FOR SELECT USING (auth.role() = 'authenticated' OR auth.role() = 'anon');

-- ═══════════════════════════════════════════════════════════════
-- QUERIES ÚTILES PARA DEBUG/CONSULTA MANUAL
-- ═══════════════════════════════════════════════════════════════

-- Ver licitaciones HOT activas:
-- SELECT * FROM vw_dashboard_hoy WHERE categoria = 'hot' LIMIT 20;

-- Ver todas las alertas Dimarsa:
-- SELECT * FROM vw_alertas_dimarsa;

-- Ver oportunidades solo en Magallanes:
-- SELECT * FROM vw_oportunidades_magallanes;

-- KPIs del día:
-- SELECT * FROM vw_kpis;

-- Pipeline por rubro:
-- SELECT * FROM vw_pipeline_por_rubro;

-- ═══════════════════════════════════════════════════════════════
-- FIN DEL SCHEMA v2.0
-- ═══════════════════════════════════════════════════════════════
