# Jorge Díaz · Radar de Licitaciones

Sistema de inteligencia de licitaciones para ferretería industrial naval y buceo profesional, alimentado por la API pública de ChileCompra.

> Automatiza la detección de oportunidades de venta al Estado chileno, calcula un score de fit por licitación, y entrega alertas en tiempo real de las oportunidades HOT.

---

## 🧭 Qué hace

- **Captura automática diaria** de licitaciones publicadas en Mercado Público vía API
- **Filtrado inteligente** por rubro (buceo, ferretería naval, equipos marítimos)
- **Scoring 0–100** por oportunidad según keywords, organismo, monto y urgencia
- **Alertas por email** cuando aparece una licitación HOT
- **Dashboard ejecutivo** con KPIs, top clientes, inteligencia competitiva y heatmap de estacionalidad

---

## 📂 Estructura del proyecto

```
jorge-diaz/
├── index.html                      ← Landing / Dashboard principal
├── cuestionario/
│   └── index.html                  ← Formulario de levantamiento de información
├── docs/
│   ├── guia-implementacion.md      ← Guía paso a paso para desplegar el sistema
│   └── supabase-schema.sql         ← Schema SQL completo de la base de datos
├── automation/
│   └── n8n-workflow.json           ← Workflow automatizado de n8n
└── README.md                       ← Este archivo
```

---

## 🚀 Links del proyecto

- **Dashboard:** https://TU-USUARIO.github.io/jorge-diaz/
- **Cuestionario:** https://TU-USUARIO.github.io/jorge-diaz/cuestionario/

---

## 🛠️ Stack

| Componente     | Tecnología                     |
|----------------|--------------------------------|
| Frontend       | HTML + CSS + Vanilla JS        |
| Base de datos  | Supabase (PostgreSQL)          |
| Automatización | n8n                            |
| API fuente     | api.mercadopublico.cl          |
| Hosting        | GitHub Pages                   |

---

## 📖 Documentación

Toda la guía de implementación está en [`docs/guia-implementacion.md`](docs/guia-implementacion.md).

---

## 📝 Licencia

Proyecto privado. Todos los derechos reservados.

---

*Desarrollado por Seba · 2026*
