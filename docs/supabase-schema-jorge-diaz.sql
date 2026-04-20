-- ═══════════════════════════════════════════════════════════════
-- JORGE DÍAZ · SCHEMA SUPABASE
-- Sistema de inteligencia de licitaciones ChileCompra
-- Rubro: Ferretería industrial naval + buceo profesional
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. TABLA PRINCIPAL: LICITACIONES
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS licitaciones (
  id                BIGSERIAL PRIMARY KEY,
  codigo_externo    TEXT UNIQUE NOT NULL,
  nombre            TEXT NOT NULL,
  descripcion       TEXT,
  organismo         TEXT,
  codigo_organismo  TEXT,
  monto_estimado    NUMERIC(15, 2) DEFAULT 0,
  moneda            TEXT DEFAULT 'CLP',
  fecha_publicacion TIMESTAMPTZ,
  fecha_cierre      TIMESTAMPTZ,
  dias_al_cierre    INTEGER,
  estado            TEXT,
  tipo              TEXT,
  score             INTEGER DEFAULT 0,
  categoria         TEXT CHECK (categoria IN ('hot', 'warm', 'cold')),
  matches           TEXT,
  url_ficha         TEXT,
  -- Gestión interna
  postulamos        BOOLEAN DEFAULT FALSE,
  resultado         TEXT CHECK (resultado IN ('ganada', 'perdida', 'desierta', 'pendiente') OR resultado IS NULL),
  monto_ofertado    NUMERIC(15, 2),
  notas             TEXT,
  -- Timestamps
  capturado_en      TIMESTAMPTZ DEFAULT NOW(),
  actualizado_en    TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_licitaciones_categoria ON licitaciones(categoria);
CREATE INDEX IF NOT EXISTS idx_licitaciones_score ON licitaciones(score DESC);
CREATE INDEX IF NOT EXISTS idx_licitaciones_fecha_cierre ON licitaciones(fecha_cierre);
CREATE INDEX IF NOT EXISTS idx_licitaciones_organismo ON licitaciones(organismo);
CREATE INDEX IF NOT EXISTS idx_licitaciones_busqueda ON licitaciones
  USING GIN (to_tsvector('spanish', nombre || ' ' || COALESCE(descripcion, '')));

-- Trigger para actualizar `actualizado_en`
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

-- ─────────────────────────────────────────────────────────────
-- 2. TABLA: ÓRDENES DE COMPRA (histórico de adjudicaciones)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ordenes_compra (
  id                BIGSERIAL PRIMARY KEY,
  codigo_oc         TEXT UNIQUE NOT NULL,
  codigo_licitacion TEXT,
  organismo         TEXT,
  proveedor         TEXT,
  rut_proveedor     TEXT,
  monto_total       NUMERIC(15, 2),
  moneda            TEXT DEFAULT 'CLP',
  fecha_envio       TIMESTAMPTZ,
  estado            TEXT,
  items             JSONB,
  capturado_en      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_oc_proveedor ON ordenes_compra(proveedor);
CREATE INDEX IF NOT EXISTS idx_oc_organismo ON ordenes_compra(organismo);
CREATE INDEX IF NOT EXISTS idx_oc_fecha ON ordenes_compra(fecha_envio DESC);

-- ─────────────────────────────────────────────────────────────
-- 3. TABLA: COMPETIDORES IDENTIFICADOS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS competidores (
  id             BIGSERIAL PRIMARY KEY,
  nombre         TEXT NOT NULL,
  rut            TEXT UNIQUE,
  codigo_mp      TEXT,
  licitaciones_ganadas  INTEGER DEFAULT 0,
  monto_total_ganado    NUMERIC(15, 2) DEFAULT 0,
  nivel_amenaza  TEXT CHECK (nivel_amenaza IN ('alto', 'medio', 'bajo')) DEFAULT 'medio',
  patron_detectado TEXT,
  ultima_victoria TIMESTAMPTZ,
  notas          TEXT,
  creado_en      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────
-- 4. TABLA: KEYWORDS CONFIGURABLES (para ajustar el filtro sin tocar código)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS keywords (
  id         BIGSERIAL PRIMARY KEY,
  keyword    TEXT NOT NULL UNIQUE,
  tipo       TEXT CHECK (tipo IN ('hot', 'warm', 'exclude')) NOT NULL,
  peso       INTEGER DEFAULT 10,
  activo     BOOLEAN DEFAULT TRUE,
  creado_en  TIMESTAMPTZ DEFAULT NOW()
);

-- Seeds iniciales del rubro naval
INSERT INTO keywords (keyword, tipo, peso) VALUES
  ('buceo', 'hot', 15),
  ('buzo', 'hot', 15),
  ('rebreather', 'hot', 15),
  ('regulador', 'hot', 12),
  ('traje seco', 'hot', 15),
  ('compresor aire', 'hot', 12),
  ('banco aire', 'hot', 12),
  ('cilindro buceo', 'hot', 12),
  ('umbilical', 'hot', 12),
  ('ferreteria naval', 'warm', 8),
  ('amarre', 'warm', 8),
  ('cabos', 'warm', 8),
  ('nautico', 'warm', 8),
  ('salvamento', 'warm', 10),
  ('chaleco salvavidas', 'warm', 10),
  ('grillete', 'warm', 8)
ON CONFLICT (keyword) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 5. VISTA: DASHBOARD — lo que consume el frontend de Jorge Díaz
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_dashboard_hoy AS
SELECT
  codigo_externo,
  nombre,
  organismo,
  monto_estimado,
  dias_al_cierre,
  score,
  categoria,
  matches,
  url_ficha,
  CASE
    WHEN dias_al_cierre <= 3 THEN 'URGENTE'
    WHEN dias_al_cierre <= 7 THEN 'PRONTO'
    ELSE 'NORMAL'
  END AS urgencia
FROM licitaciones
WHERE estado IN ('publicada', 'activa')
  AND dias_al_cierre > 0
  AND dias_al_cierre <= 30
ORDER BY score DESC, dias_al_cierre ASC;

-- ─────────────────────────────────────────────────────────────
-- 6. VISTA: KPIs EJECUTIVOS
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_kpis AS
SELECT
  COUNT(*) FILTER (WHERE estado = 'publicada' AND dias_al_cierre > 0) AS activas_hoy,
  COUNT(*) FILTER (WHERE capturado_en >= CURRENT_DATE) AS nuevas_hoy,
  COUNT(*) FILTER (WHERE dias_al_cierre BETWEEN 1 AND 7) AS cierran_semana,
  COALESCE(SUM(monto_estimado) FILTER (WHERE estado = 'publicada' AND dias_al_cierre > 0), 0) AS pipeline_clp,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE resultado = 'ganada') /
    NULLIF(COUNT(*) FILTER (WHERE postulamos = TRUE), 0),
    1
  ) AS tasa_adjudicacion_pct
FROM licitaciones;

-- ─────────────────────────────────────────────────────────────
-- 7. VISTA: TOP CLIENTES (histórico)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_top_clientes AS
SELECT
  organismo,
  COUNT(*) AS total_adjudicadas,
  SUM(monto_ofertado) AS monto_total,
  MAX(actualizado_en) AS ultima_compra
FROM licitaciones
WHERE resultado = 'ganada'
GROUP BY organismo
ORDER BY monto_total DESC NULLS LAST
LIMIT 10;

-- ─────────────────────────────────────────────────────────────
-- 8. POLÍTICAS RLS (Row Level Security) — ajustar según auth
-- ─────────────────────────────────────────────────────────────
ALTER TABLE licitaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE ordenes_compra ENABLE ROW LEVEL SECURITY;
ALTER TABLE competidores ENABLE ROW LEVEL SECURITY;
ALTER TABLE keywords ENABLE ROW LEVEL SECURITY;

-- Lectura permitida a usuarios autenticados
CREATE POLICY "lectura_autenticados" ON licitaciones
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "lectura_autenticados_oc" ON ordenes_compra
  FOR SELECT USING (auth.role() = 'authenticated');

-- Escritura solo vía service_role (n8n usa service_role)
-- No se necesita policy adicional; service_role bypasea RLS.

-- ═══════════════════════════════════════════════════════════════
-- FIN — Ejecutar este script en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════
