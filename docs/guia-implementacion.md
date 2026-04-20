# Jorge Díaz · Guía de Implementación

Sistema de inteligencia de licitaciones para ferretería industrial naval + buceo profesional, alimentado por la API de ChileCompra.

---

## Arquitectura del sistema

```
┌─────────────────┐      ┌──────────┐      ┌──────────────┐      ┌──────────────┐
│ API ChileCompra │ ───▶ │   n8n    │ ───▶ │   Supabase   │ ───▶ │  Dashboard   │
│ api.mp.cl       │      │ workflow │      │   Postgres   │      │   Jorge Díaz │
└─────────────────┘      └──────────┘      └──────────────┘      └──────────────┘
                              │
                              ▼
                         Email / WhatsApp
                         (alertas HOT)
```

**Flujo diario automático (7:00 AM hora Chile):**

1. n8n consulta la API de Mercado Público.
2. Filtra licitaciones del día por keywords del rubro (buceo, naval, ferretería marítima).
3. Calcula un score 0–100 por cada una (categoría hot/warm/cold).
4. Guarda/actualiza en Supabase con upsert sobre `codigo_externo`.
5. Si la licitación es HOT → dispara alerta por email.
6. El dashboard de Jorge Díaz consume la data desde Supabase.

---

## Paso 1 · Solicitar ticket de API ChileCompra

1. Entra a https://www.chilecompra.cl/api/
2. Inicia sesión con Clave Única de tu papá (el titular de la empresa).
3. Acepta términos y solicita ticket vía formulario.
4. El ticket llega al correo registrado en minutos.
5. Guárdalo seguro — es como una API key.

**Para pruebas durante desarrollo** puedes usar el ticket público:
`F8537A18-6766-4DEF-9E59-426B4FEE2844`

---

## Paso 2 · Configurar Supabase

1. Entra a https://supabase.com y crea un proyecto nuevo (región: South America para menor latencia).
2. Ve a **SQL Editor** y pega el contenido completo de `supabase-schema-jorge-diaz.sql`.
3. Ejecuta. Debería crear 4 tablas + 3 vistas + seeds de keywords.
4. Anota estos datos del proyecto (los necesitas para n8n):
   - **Project URL:** `https://xxxxx.supabase.co`
   - **service_role key:** (en Settings → API → `service_role` secret)

---

## Paso 3 · Configurar n8n

### Opción A — n8n Cloud (recomendado para empezar rápido)

1. Crea cuenta en https://n8n.cloud (tiene plan gratuito generoso).
2. Importa el workflow: **Workflows → Import from File** → sube `n8n-workflow-jorge-diaz.json`.

### Opción B — Self-hosted (si ya tienes n8n corriendo para Workii)

1. Abre tu instancia de n8n.
2. **Import from File** → sube el JSON.

### Configurar variables de entorno en n8n

En **Settings → Variables** (o como variables globales), agrega:

| Variable       | Valor                                      |
|----------------|--------------------------------------------|
| `MP_TICKET`    | Tu ticket de ChileCompra                   |
| `EMAIL_JORGE`  | Email donde llegan las alertas HOT         |

### Configurar credenciales

- **Supabase:** crea una credencial nueva tipo Supabase con la Project URL + service_role key.
- **Email:** credencial SMTP (puede ser Gmail con App Password, SendGrid, Resend, etc.).

### Asignar credenciales a los nodos

Abre el workflow importado y asigna las credenciales a:
- Nodo "Guardar en Supabase" → tu credencial Supabase
- Nodo "Alerta email (HOT)" → tu credencial SMTP

---

## Paso 4 · Probar el workflow

1. Antes de activar el cron, ejecuta el workflow manualmente: botón **Execute Workflow**.
2. Revisa cada nodo:
   - "API ChileCompra" → debe devolver un JSON con `Listado` array.
   - "Filtrar + Score" → debe pasar solo las licitaciones del rubro.
   - "Guardar en Supabase" → verifica en Supabase que se crearon registros.
3. Si algo falla, revisa logs del nodo y ajusta.

### Verificar en Supabase

```sql
-- Cuántas licitaciones capturadas
SELECT COUNT(*), categoria FROM licitaciones GROUP BY categoria;

-- Las HOT de hoy
SELECT codigo_externo, nombre, organismo, score
FROM licitaciones
WHERE categoria = 'hot'
ORDER BY score DESC;

-- KPIs agregados
SELECT * FROM vw_kpis;
```

---

## Paso 5 · Conectar el dashboard

En el HTML de Jorge Díaz (el que ya tienes), reemplaza los datos hardcodeados por un fetch a Supabase.

Agrega al `<script>` del dashboard:

```javascript
const SUPABASE_URL = 'https://xxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'tu_anon_key_publica';

async function cargarLicitaciones() {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/vw_dashboard_hoy?order=score.desc&limit=20`,
    {
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
      }
    }
  );
  const data = await res.json();
  renderOpportunities(data);
}

async function cargarKPIs() {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/vw_kpis`,
    { headers: { 'apikey': SUPABASE_ANON_KEY } }
  );
  const [kpis] = await res.json();
  document.querySelector('[data-kpi="activas"]').textContent = kpis.activas_hoy;
  document.querySelector('[data-kpi="pipeline"]').textContent =
    `$${(kpis.pipeline_clp / 1000000).toFixed(0)}M CLP`;
  // etc.
}

cargarLicitaciones();
cargarKPIs();
// Auto-refresh cada 5 minutos
setInterval(cargarLicitaciones, 5 * 60 * 1000);
```

---

## Paso 6 · Ajustar keywords al catálogo real de tu papá

Esto es **clave** para que el score sea preciso.

Conecta con tu papá y haz una sesión de 30 min para:

1. Listar sus 20–30 productos principales con los términos exactos que usan los organismos en licitaciones (ojo: a veces el lenguaje técnico de los pliegos difiere del comercial).
2. Revisar el historial de licitaciones que ha ganado los últimos 2 años → extraer qué palabras clave aparecen en los títulos.
3. Identificar los 10 organismos con los que más trabaja.

Luego actualiza la tabla `keywords` en Supabase directamente (sin tocar código):

```sql
-- Agregar una keyword nueva
INSERT INTO keywords (keyword, tipo, peso) VALUES ('valvula antirretorno', 'hot', 12);

-- Desactivar una que está generando ruido
UPDATE keywords SET activo = FALSE WHERE keyword = 'buceo';

-- Ajustar peso
UPDATE keywords SET peso = 20 WHERE keyword = 'rebreather';
```

(Nota: para que el workflow lea de la tabla en vez del array hardcodeado, podemos hacer una segunda iteración del workflow cuando ya esté corriendo. Por ahora el JS del nodo "Filtrar + Score" tiene los arrays inline, que es más simple para arrancar.)

---

## Paso 7 · Activar el cron

Cuando el workflow corra bien en manual:

1. Activa el toggle **Active** del workflow en n8n.
2. Verifica que la timezone esté en `America/Santiago`.
3. Confirma el cron: `0 7 * * *` = todos los días a las 7:00 AM hora Chile.

---

## Extensiones futuras (roadmap)

### Fase 2 — Órdenes de compra e inteligencia competitiva
- Duplicar el workflow pero apuntando a `/servicios/v1/publico/ordenesdecompra.json`.
- Poblar tabla `ordenes_compra` y `competidores`.
- Identificar patrones: "Náutica Austral siempre baja precio 48h antes del cierre".

### Fase 3 — Alertas WhatsApp
- Cambiar el nodo "Alerta email" por un nodo HTTP a WhatsApp Business API o Twilio.

### Fase 4 — IA para propuestas
- Al detectar una licitación HOT, disparar un workflow secundario que llama a Claude API.
- Claude genera: borrador de propuesta técnica, precio óptimo sugerido, checklist de requisitos.

### Fase 5 — App móvil
- React Native consumiendo las mismas vistas de Supabase.
- Notificaciones push nativas.

---

## Costos mensuales estimados

| Servicio            | Plan inicial       | USD / mes |
|---------------------|--------------------|-----------|
| n8n Cloud           | Starter            | ~$20      |
| Supabase            | Free (hasta 500MB) | $0        |
| Email (Resend)      | Free (3000/mes)    | $0        |
| API ChileCompra     | Gratis             | $0        |
| **TOTAL**           |                    | **~$20**  |

Con Supabase free y n8n self-hosted puedes llevarlo a $0 los primeros meses.

---

## Archivos incluidos

- `n8n-workflow-jorge-diaz.json` — workflow completo listo para importar
- `supabase-schema-jorge-diaz.sql` — schema SQL completo
- `radar-licitaciones-naval.html` — dashboard frontend (Jorge Díaz)
- `guia-implementacion.md` — este documento

---

*Versión 1.0 · Abril 2026*
