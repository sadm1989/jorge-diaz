-- ═══════════════════════════════════════════════════
-- JORGE DÍAZ · RECASUR · SCHEMA SUPABASE LIMPIO
-- Ejecutar completo en SQL Editor de Supabase
-- ═══════════════════════════════════════════════════

-- TABLA PRINCIPAL
CREATE TABLE IF NOT EXISTS licitaciones (
  id                      BIGSERIAL PRIMARY KEY,
  codigo_externo          TEXT UNIQUE NOT NULL,
  nombre                  TEXT NOT NULL,
  descripcion             TEXT,
  organismo               TEXT,
  codigo_organismo        TEXT,
  region                  TEXT,
  monto_estimado          NUMERIC(15,2) DEFAULT 0,
  moneda                  TEXT DEFAULT 'CLP',
  fecha_publicacion       TIMESTAMPTZ,
  fecha_cierre            TIMESTAMPTZ,
  dias_al_cierre          INTEGER,
  estado                  TEXT,
  tipo                    TEXT,
  score                   INTEGER DEFAULT 0,
  categoria               TEXT CHECK (categoria IN ('hot','warm','cold')),
  rubro_principal         TEXT,
  nivel_rubro             TEXT,
  matches                 TEXT,
  cliente_detectado       TEXT,
  region_detectada        TEXT,
  competidores_detectados TEXT,
  alerta_dimarsa          BOOLEAN DEFAULT FALSE,
  sugerencia_tactica      TEXT,
  decision                TEXT,
  win_probability         TEXT,
  risk_level              TEXT,
  margin_level            TEXT,
  next_action             TEXT,
  pipeline_status         TEXT,
  boss_argument           TEXT,
  internal_deadline       DATE,
  url_ficha               TEXT,
  postulamos              BOOLEAN DEFAULT FALSE,
  resultado               TEXT CHECK (resultado IN ('ganada','perdida','desierta','pendiente') OR resultado IS NULL),
  monto_ofertado          NUMERIC(15,2),
  notas                   TEXT,
  capturado_en            TIMESTAMPTZ DEFAULT NOW(),
  actualizado_en          TIMESTAMPTZ DEFAULT NOW()
);

-- TABLA KEYWORDS
CREATE TABLE IF NOT EXISTS keywords (
  id        BIGSERIAL PRIMARY KEY,
  keyword   TEXT NOT NULL UNIQUE,
  tipo      TEXT CHECK (tipo IN ('hot','warm','exclude')) NOT NULL,
  peso      INTEGER DEFAULT 10,
  activo    BOOLEAN DEFAULT TRUE,
  creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- TABLA COMPETIDORES
CREATE TABLE IF NOT EXISTS competidores (
  id                    BIGSERIAL PRIMARY KEY,
  nombre                TEXT NOT NULL,
  rut                   TEXT,
  nivel_amenaza         TEXT CHECK (nivel_amenaza IN ('archienemigo','alto','medio','bajo')),
  rubro_principal       TEXT,
  patron_detectado      TEXT,
  como_competir         TEXT,
  ultima_victoria       TIMESTAMPTZ,
  notas                 TEXT,
  creado_en             TIMESTAMPTZ DEFAULT NOW()
);

-- TABLA ORDENES DE COMPRA
CREATE TABLE IF NOT EXISTS ordenes_compra (
  id              BIGSERIAL PRIMARY KEY,
  codigo_oc       TEXT UNIQUE NOT NULL,
  organismo       TEXT,
  proveedor       TEXT,
  monto_total     NUMERIC(15,2),
  fecha_envio     TIMESTAMPTZ,
  estado          TEXT,
  capturado_en    TIMESTAMPTZ DEFAULT NOW()
);

-- ÍNDICES
CREATE INDEX IF NOT EXISTS idx_lic_categoria   ON licitaciones(categoria);
CREATE INDEX IF NOT EXISTS idx_lic_score       ON licitaciones(score DESC);
CREATE INDEX IF NOT EXISTS idx_lic_fecha       ON licitaciones(fecha_cierre);
CREATE INDEX IF NOT EXISTS idx_lic_organismo   ON licitaciones(organismo);
CREATE INDEX IF NOT EXISTS idx_lic_region      ON licitaciones(region_detectada);
CREATE INDEX IF NOT EXISTS idx_lic_dimarsa     ON licitaciones(alerta_dimarsa) WHERE alerta_dimarsa = TRUE;

-- TRIGGER actualizado_en
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

-- VISTA DASHBOARD HOY
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
  decision,
  win_probability,
  risk_level,
  margin_level,
  next_action,
  pipeline_status,
  boss_argument,
  internal_deadline,
  url_ficha,
  CASE
    WHEN alerta_dimarsa THEN 'CRITICA'
    WHEN dias_al_cierre <= 3 THEN 'URGENTE'
    WHEN dias_al_cierre <= 7 THEN 'PRONTO'
    ELSE 'NORMAL'
  END AS prioridad
FROM licitaciones
WHERE dias_al_cierre > 0
  AND dias_al_cierre <= 60
ORDER BY alerta_dimarsa DESC, score DESC, dias_al_cierre ASC;

-- VISTA KPIs
CREATE OR REPLACE VIEW vw_kpis AS
SELECT
  COUNT(*) FILTER (WHERE dias_al_cierre > 0)                          AS activas_hoy,
  COUNT(*) FILTER (WHERE capturado_en >= CURRENT_DATE)                AS nuevas_hoy,
  COUNT(*) FILTER (WHERE categoria = 'hot' AND dias_al_cierre > 0)   AS hot_activas,
  COUNT(*) FILTER (WHERE alerta_dimarsa = TRUE AND dias_al_cierre > 0) AS alertas_dimarsa,
  COUNT(*) FILTER (WHERE dias_al_cierre BETWEEN 1 AND 7)             AS cierran_semana,
  COUNT(*) FILTER (WHERE region_detectada IN ('MAGALLANES','ANTARTICA') AND dias_al_cierre > 0) AS oportunidades_magallanes,
  COALESCE(SUM(monto_estimado) FILTER (WHERE dias_al_cierre > 0), 0) AS pipeline_clp,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE resultado = 'ganada') /
    NULLIF(COUNT(*) FILTER (WHERE postulamos = TRUE), 0), 1
  ) AS tasa_adjudicacion_pct
FROM licitaciones;

-- VISTA PERFORMANCE MENSUAL
CREATE OR REPLACE VIEW vw_performance_mensual AS
SELECT
  DATE_TRUNC('month', actualizado_en)                                  AS mes,
  COUNT(*) FILTER (WHERE postulamos = TRUE)                            AS postuladas,
  COUNT(*) FILTER (WHERE resultado = 'ganada')                         AS ganadas,
  COUNT(*) FILTER (WHERE resultado = 'perdida')                        AS perdidas,
  COALESCE(SUM(monto_ofertado) FILTER (WHERE resultado = 'ganada'), 0) AS monto_ganado_clp,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE resultado = 'ganada') /
    NULLIF(COUNT(*) FILTER (WHERE postulamos = TRUE), 0), 1
  ) AS tasa_exito_pct
FROM licitaciones
WHERE postulamos = TRUE
GROUP BY mes
ORDER BY mes DESC;

-- SEEDS KEYWORDS RECASUR
INSERT INTO keywords (keyword, tipo, peso) VALUES
  ('buceo',                   'hot', 15),
  ('buzo',                    'hot', 15),
  ('rebreather',              'hot', 15),
  ('regulador de buceo',      'hot', 12),
  ('traje de buceo',          'hot', 15),
  ('traje seco',              'hot', 15),
  ('compresor alta presion',  'hot', 12),
  ('compresor buceo',         'hot', 12),
  ('banco de aire',           'hot', 12),
  ('cilindro buceo',          'hot', 12),
  ('umbilical',               'hot', 12),
  ('chaleco salvavidas',      'hot', 13),
  ('balsa salvavidas',        'hot', 13),
  ('salvataje maritimo',      'hot', 13),
  ('embarcacion',             'hot', 12),
  ('motor fuera de borda',    'hot', 12),
  ('motor yamaha',            'hot', 11),
  ('motor centrado',          'hot', 11),
  ('neumatico',               'hot', 11),
  ('lubricante',              'hot', 10),
  ('repuesto automotriz',     'hot', 10),
  ('filtro motor',            'hot', 10),
  ('maquinaria agricola',     'hot', 12),
  ('maquinaria pesada',       'hot', 12),
  ('grua horquilla',          'hot', 12),
  ('generador electrico',     'hot', 11),
  ('motobomba',               'hot', 11),
  ('vhf',                     'hot', 11),
  ('uhf',                     'hot', 11),
  ('radio maritima',          'hot', 11),
  ('gps marino',              'hot', 11),
  ('radar marino',            'hot', 11),
  ('rov',                     'hot', 13),
  ('ropa termica',            'warm', 8),
  ('ropa de seguridad',       'warm', 8),
  ('ferreteria',              'warm', 7),
  ('herramientas',            'warm', 7),
  ('arriendo',                'exclude', 0),
  ('alquiler',                'exclude', 0),
  ('consultoria',             'exclude', 0),
  ('capacitacion',            'exclude', 0)
ON CONFLICT (keyword) DO NOTHING;

-- SEEDS COMPETIDORES RECASUR
INSERT INTO competidores (nombre, nivel_amenaza, rubro_principal, patron_detectado, como_competir) VALUES
  ('DIMARSA',              'archienemigo', 'náutico/HDPE/buceo',   'Fabrican propio, bajan precio agresivamente', 'No competir por precio. Defender con logística local Magallanes, entrega 48h, técnico en Punta Arenas'),
  ('SALFA',                'alto',         'maquinarias/vehículos', 'Precio competitivo en maquinaria pesada',     'Destacar soporte técnico local y plazo de entrega'),
  ('MOBIL',                'alto',         'lubricantes',           'Marca global, precios muy competitivos',      'Ofrecer servicio técnico incluido y entrega inmediata'),
  ('STARLINE',             'alto',         'náutico/electrónico',   'Fuerte en electrónica marítima',              'Destacar stock local y garantía de servicio'),
  ('KAUFFMAN',             'alto',         'vehículos/equipos',     'Especialistas en equipos especializados',     'Competir con plazo de entrega y soporte regional'),
  ('Importadora Hevia SpA','medio',        'náutico',               'Regional, precios medios',                    'Destacar experiencia y trayectoria de Recasur'),
  ('KRILL EIRL',           'medio',        'regional',              'Competidor local pequeño',                    'Mejor servicio técnico y respaldo de marca'),
  ('ITURRI S.A.',          'bajo',         'seguridad industrial',  'Precios altos, marca reconocida',             'Competir agresivamente en precio')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════
-- FIN DEL SCHEMA · JORGE DÍAZ · RECASUR
-- ═══════════════════════════════════════════════════
