# Sistema de Triaje de Soporte — Checkpoint 4

Lautaro Bustos Raiz

Sistema multi-agente de triaje de soporte al cliente construido en n8n. El intake es por email (Gmail), con clasificación por IA, memoria de largo plazo, sincronización con CRM (Salesforce), asignación de técnicos, y notificaciones a humanos vía Gmail y Slack.

---

## 1. Tecnologías utilizadas

| Tecnología | Uso |
|---|---|
| **n8n** (Docker) | Orquestador de todos los workflows |
| **Gmail** | Trigger de entrada (casilla de soporte) y salida (borradores de notificación) |
| **Salesforce** | CRM — búsqueda/creación/actualización de contactos |
| **Airtable** | Memoria de largo plazo por sesión (resumen consolidado, estado del caso) |
| **Postgres** | Tabla de técnicos disponibles y asignación |
| **Google Sheets** | Registro/logging de casos |
| **Slack** | Observabilidad — logs de trazabilidad y alertas al equipo |
| **Ollama** (local) | Modelos de IA (ver sección 4) |
| **OrbStack** | Runtime de Docker en Mac |

---

## 2. Arquitectura

El sistema está compuesto por **4 workflows** independientes que se invocan entre sí mediante `Execute Workflow`.

```
                         Gmail Trigger: Casilla de Soporte
                                     │
                                     ▼
                    ① IF ¿Es Auto-Reply?  ── Sí ──▶ Descartar
                                     │ No
                                     ▼
                    ④ Set - Extraer DNI, Tipo y Mensaje del Reclamo
                                     ▼
                    ④ Set - Construir Session ID y Body (DNI+Tipo)
                       session_id = dni_cliente + "_" + tipo_reclamo
                                     ▼
                    ¿Reclamo Válido?  ── No ──▶ Descartar Payload Inválido
                                     │ Sí
                                     ▼
                    ② Buscar Contacto en Salesforce (por email)
                                     ▼
                    ¿Contacto Existe?  ── Sí → Actualizar | No → Crear
                                     ▼
                    Restaurar Contexto Post-CRM
                                     ▼
                    Execute Workflow: Cerebro de Clasificación ──┐
                                     ▼                            │
                    Router de Intención (switch por categoría)   │
                       ├─ TECH_SUPPORT → Worker 1                │
                       ├─ BILLING      → Worker 2                │
                       └─ ESCALATE_HUMAN → ③ Gmail Draft + Slack │
                                                                   │
   ┌───────────────────────────────────────────────────────────┘
   ▼
Cerebro de Clasificación (sub-workflow):
   Execute Workflow Trigger (chatInput, session_id)
        ▼
   Leer Memoria Airtable (por session_id)
        ▼
   ¿Tiene historial previo? → Set Contexto (recurrente) / (nuevo)
        ▼
   AI Agent Router (clasifica en TECH_SUPPORT | BILLING | ESCALATE_HUMAN)
        ▼
   Parsear Clasificación
        ▼
   Contrato de Salida → {status, data: {categoria, tipo_consulta, urgencia,
      resumen, mensaje, session_id, tecnico_asignado_previo,
      airtable_record_id, tiene_memoria, mensaje_count, contexto_previo}}
```

**Worker 1** (registro de caso): busca un técnico disponible en Postgres según el tipo de consulta, lo asigna (evitando reasignar en casos reabiertos), y registra el caso en Google Sheets.

**Worker 2** (redacción de respuesta): genera una respuesta sugerida según la categoría (BILLING/otro) para que el equipo la revise.

Después de cada Worker, el Manager actualiza la memoria en Airtable (crea el registro si es sesión nueva, actualiza si es recurrente) y, si la sesión supera 5 mensajes, dispara un **Summarization Agent** que comprime el historial.

---

## 3. Los 4 workflows

| Archivo | Rol |
|---|---|
| `checkpoint4_bustosraiz_lautaro.json` | **Manager** — intake por Gmail, sincronización con Salesforce, routing, notificaciones por Gmail/Slack |
| `cerebro_clasificacion_bustosraiz_lautaro.json` | **Sub-workflow** — memoria (Airtable) + clasificación por IA |
| `worker1_modulo3_bustosraiz_lautaro.json` | **Sub-workflow** — registro de caso y asignación de técnico |
| `worker2_modulo2_bustosraiz_lautaro.json` | **Sub-workflow** — redacción de respuesta sugerida |

---

## 4. Modelos de IA

Se usan dos modelos distintos, uno por tarea, priorizando latencia y costo:

- **AI Agent Router**: `qwen2.5:3b` vía **Ollama** (local, sin costo de API). Clasifica cada consulta contra una taxonomía cerrada (`TECH_SUPPORT` / `BILLING` / `ESCALATE_HUMAN`), devolviendo un JSON con categoría, tipo de consulta, urgencia y resumen. Es una tarea de clasificación simple que no necesita razonamiento complejo, así que alcanza con un modelo liviano corriendo en local.
- **Summarization Agent**: `gpt-5-mini` (OpenAI). Comprime el historial de la sesión cuando supera 5 mensajes, para mantener el contexto sin que crezca indefinidamente.

---

## 5. Setup

### 5.1 Requisitos previos
- Docker / OrbStack corriendo
- n8n vía Docker
- Ollama corriendo localmente con el modelo descargado (usado por el AI Agent Router):
  ```
  ollama pull qwen2.5:3b
  ```
- API Key de OpenAI con acceso a `gpt-5-mini` (usada por el Summarization Agent)
- Postgres en la misma red Docker que n8n, seedeado con una tabla `tecnicos`
- Cuentas: Airtable, Google Sheets, Gmail, Salesforce, Slack

### 5.2 Credenciales en n8n

| Servicio | Tipo de credencial |
|---|---|
| Ollama | Ollama API — host `host.docker.internal:11434` |
| OpenAI | API Key (usada solo por el Summarization Agent) |
| Postgres | host `postgres` (nombre del servicio Docker, no `localhost`) |
| Google Sheets | OAuth2 / Service Account |
| Airtable | Personal Access Token |
| Slack | Bot Token (scope `chat:write`) |
| Gmail | OAuth2 (Gmail API habilitada, scopes `gmail.readonly` + `gmail.compose`) |
| Salesforce | OAuth2 — Connected App con scopes `api`, `refresh_token/offline_access`, `full` |

### 5.3 Orden de importación

1. `worker1_modulo3_bustosraiz_lautaro.json`
2. `worker2_modulo2_bustosraiz_lautaro.json`
3. `cerebro_clasificacion_bustosraiz_lautaro.json`
4. `checkpoint4_bustosraiz_lautaro.json`
5. En el Manager, abrir los 3 nodos `Execute Workflow: ...` (Worker 1, Worker 2, Cerebro de Clasificación) y reasignar el `workflowId` a los IDs reales que asignó tu instancia al importar.
6. Reasignar todas las credenciales a las tuyas.
7. Activar el workflow del Manager para que el Gmail Trigger empiece a escuchar.

---

## 6. Formato del email de entrada

El cuerpo del email debe incluir, en líneas separadas:

```
DNI: 30123456
Tipo: Facturacion

<mensaje del cliente>
```

- El **Tipo** se extrae como un único token (letras/guion bajo, sin espacios). Para tipos de dos palabras usar guion bajo: `Tipo: Soporte_Tecnico`.
- El `session_id` resultante es `DNI + "_" + tipo` (ej. `30123456_facturacion`).

---

## 7. Cómo probar

Con el workflow del Manager **activo**, cualquier email nuevo en la casilla conectada dispara el `Gmail Trigger` automáticamente (polling cada 1 minuto).

Para testear sin esperar un email real, abrí el nodo `Gmail Trigger: Casilla de Soporte` y usá **"Fetch Test Event"** (trae el último email real de la bandeja), o **"set mock data"** con un JSON como:

```json
{
  "Subject": "No me llegó la factura de agosto",
  "From": "Nombre Apellido <mail@dominio.com>",
  "snippet": "DNI: 30123456\nTipo: Facturacion\n\nHola, hace una semana que no me llega la factura..."
}
```

### Escenarios de prueba sugeridos

| Escenario | Cómo probarlo | Resultado esperado |
|---|---|---|
| Reclamo de facturación | Mail con `Tipo: Facturacion` | Clasifica BILLING, Worker 2 redacta respuesta |
| Reclamo técnico | Mail con `Tipo: Soporte_Tecnico` | Clasifica TECH_SUPPORT, Worker 1 asigna técnico |
| Caso ambiguo/urgente | Mensaje con doble cobro, tono urgente | Clasifica ESCALATE_HUMAN, genera Draft + alerta Slack |
| Auto-reply | Asunto `Out of Office` o remitente `no-reply@...` | Se descarta, no genera ninguna acción |
| Sin DNI/Tipo | Mail sin ese formato en el cuerpo | Se descarta como payload inválido |
| Cliente recurrente | Mismo DNI+Tipo que un mail anterior | Actualiza el contacto en Salesforce (no duplica), reconoce historial previo en Airtable |
