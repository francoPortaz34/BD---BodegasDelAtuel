# Etapa 8 - Despliegue en la nube

El sistema quedó publicado con tres servicios: la base en **Supabase**, la API y el front en
**Render**. Este documento explica cómo está armado, cómo se accede, qué se cambió en el
código para desplegarlo y cómo diagnosticar problemas. El backup y la restauración de prueba
están en [`etapa8_backup_restauracion.md`](etapa8_backup_restauracion.md).

> Convención: lo **verificado** se comprobó en el código, en el historial de Git, en los
> archivos de backup o con una consulta de solo lectura el 10/11/2026. Lo marcado
> **pendiente de confirmación** no se pudo comprobar desde el repositorio (por ejemplo,
> configuraciones que solo se ven en los paneles de Render o Supabase).

## 1. Acceso al sistema

| Para qué | Dirección |
|---|---|
| **Usar el sistema (front, desde el navegador)** | **<https://bd-bodegasdelatuel-1.onrender.com>** |
| API REST (backend) | <https://bd-bodegasdelatuel.onrender.com> |
| Documentación interactiva de la API (Swagger) | <https://bd-bodegasdelatuel.onrender.com/docs> |
| Estado de la API y de la base | <https://bd-bodegasdelatuel.onrender.com/salud> |

Para usar el sistema alcanza con abrir la **dirección del front**. La API es para pruebas
técnicas: el front ya se comunica con ella solo.

> **Plan gratuito de Render:** si un servicio estuvo un rato sin uso, Render lo suspende y la
> primera visita lo vuelve a levantar. Esa primera respuesta puede tardar bastante (en la
> verificación del 10/11/2026 tardó unos 14 s la API y unos 13 s el front; puede ser más).
> Si la página queda cargando, esperar y recargar. Ver [sección 8](#8-operación-y-diagnóstico).

## 2. Arquitectura

```text
Navegador
   │  https://bd-bodegasdelatuel-1.onrender.com
   ▼
Front (Render, contenedor Docker de front/)            servidor.py: archivos estáticos
   │  /api/*  →  reenvía a la API (proxy)                + proxy /api (un solo origen, sin CORS)
   ▼
API (Render, contenedor Docker de api/)                FastAPI + uvicorn + psycopg
   │  https://bd-bodegasdelatuel.onrender.com
   │  conexión PostgreSQL con SSL, rol bodegas_api
   ▼
Supabase (PostgreSQL 17.11)                            esquema bodegas: tablas, triggers,
                                                       funciones, procedimientos, vistas
```

- El navegador **nunca** se conecta a la base: habla con el front, que reenvía `/api/*` a la API.
- La API se conecta a Supabase **siempre** con el rol `bodegas_api` (privilegios mínimos).
- Los cálculos (precios, descuentos, totales, stock) siguen en la base: triggers, funciones y
  procedimientos de las etapas 2 a 5. Ni la API ni el front los replican.

## 3. Base de datos (Supabase)

| Dato | Valor | Estado |
|---|---|---|
| Servicio | Supabase (PostgreSQL administrado) | Verificado |
| Motor | **PostgreSQL 17.11** | Verificado (encabezado de los backups: *Dumped from database version: 17.11*) |
| Base de datos | `postgres` (la base por defecto del proyecto Supabase) | Verificado (encabezado de los backups: *dbname: postgres*) |
| Esquema del sistema | `bodegas` (dueño `bodegas_owner`) | Verificado (backup) |
| Región | — | **Pendiente de confirmación** (se ve en *Project Settings* de Supabase) |
| Tipo de conexión de la API (directa o *pooler*, host y puerto) | — | **Pendiente de confirmación** |
| SSL | La API y la carga masiva admiten `sslmode` por variable de entorno; según el procedimiento informado, los backups se hicieron con SSL | `sslmode` verificado en el código; el valor usado en Render queda **pendiente de confirmación** (se recomienda `require`) |

### 3.1 Roles

Los crea y configura `db/migrations/007_roles.sql` (Etapa 2). Los tres existían en el backup
de Supabase: todos los objetos del esquema `bodegas` (359 entradas del backup) pertenecen a
`bodegas_owner`.

| Rol | Login | Responsabilidad | Permisos |
|---|---|---|---|
| `bodegas_owner` | No (`NOLOGIN`) | Dueño del esquema y de todos sus objetos. Los procedimientos y triggers `SECURITY DEFINER` corren con sus permisos | Todos sobre su esquema. Un administrador lo usa con `SET ROLE bodegas_owner` |
| `bodegas_api` | Sí | Rol con el que se conecta la API | `SELECT/INSERT/UPDATE/DELETE` en las tablas de negocio; **solo lectura** en `stock_sala`, `stock_deposito`, `auditoria_precio` y las vistas; `EXECUTE` solo en las funciones y procedimientos de negocio |
| `bodegas_reportes` | Sí | Consultas y reportes | Solo lectura (tablas, vistas y funciones de consulta) |

Además, `007_roles.sql` quita los privilegios de `PUBLIC` y fija `search_path = bodegas` para
los tres roles, para que encuentren las tablas sin escribir `bodegas.` adelante.

**Credenciales administrativas y credenciales de la API son distintas:**

- *Administrativas:* el usuario administrador del proyecto Supabase. Se usaron para ejecutar
  las migraciones, la carga masiva (con `SET ROLE bodegas_owner`) y los backups. **No** se
  configuran en Render.
- *De la API:* usuario `bodegas_api` y su contraseña. Son las únicas credenciales de base que
  tiene el servicio de la API en Render.

Pendiente de confirmación: cómo se asignó en Supabase la contraseña de `bodegas_api` y cómo se
le dio al administrador permiso para `SET ROLE bodegas_owner` (en Supabase el usuario
administrador no es superusuario). No queda registrado en el repositorio.

## 4. Migraciones y datos en Supabase

### 4.1 Migraciones

Se aplican en orden numérico, igual que en local:

| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `001_esquema.sql` | Esquema `bodegas`, tipos, dominios y tablas |
| 2 | `002_constraints.sql` | Claves foráneas, UNIQUE y CHECK |
| 3 | `003_funciones.sql` | Funciones |
| 4 | `004_procedimientos.sql` | Procedimientos (`sp_procesar_ingreso`, `sp_procesar_transferencia`) |
| 5 | `005_triggers.sql` | Triggers de las reglas de negocio |
| 6 | `006_vistas.sql` | Vistas y vista materializada |
| 7 | `007_roles.sql` | Roles, dueños, privilegios y `search_path` |
| 8 | `008_indices.sql` | Índices de la Etapa 4 |

Verificado en el backup del esquema `bodegas` (restaurado en un contenedor aparte, ver el otro
documento): están las 34 tablas, las 15 rutinas, los 10 triggers, las 2 vistas, la vista
materializada, las 124 restricciones y los 6 índices de `008_indices.sql`.

Pendiente de confirmación: con qué herramienta se ejecutaron (editor SQL de Supabase o `psql`)
y con qué usuario.

### 4.2 Carga de datos

Se usó el script de la Etapa 3, `db/seed/carga_masiva.py`, adaptado en esta etapa (ver
[sección 7](#7-cambios-realizados-en-la-etapa-8)) para conectarse a Supabase con SSL y para
cargar como `bodegas_owner`.

La base de Supabase tiene **2.000 comprobantes** (la base local de la Etapa 3 tiene 150.000).
Coincide con el modo de prueba rápida del script (`carga_masiva.py 2000`); el comando exacto
usado queda **pendiente de confirmación**. Con esa cantidad entra holgada en el plan gratuito
de Supabase.

Cantidades del backup del 10/11/2026 (tablas con más filas y tablas relevantes):

| Tabla | Filas | Tabla | Filas |
|---|---:|---|---:|
| cliente | 20.000 | transferencia | 1.195 |
| socio | 16.942 | exportador | 1.025 |
| detalle_comprobante | 6.810 | stock_sala | 722 |
| renglon_transferencia | 6.305 | vino_cepa | 570 |
| renglon_ingreso | 5.090 | vino | 403 |
| analisis_calidad | 4.991 | stock_deposito | 321 |
| permiso_exportacion | 3.049 | localidad | 269 |
| lote_de_uva | 2.499 | sala_de_ventas | 25 |
| distribuidor | 2.033 | bodega | 21 |
| **comprobante** | **2.000** | cepa / maridaje | 12 / 8 |
| ingreso | 1.459 | | |

### 4.3 Controles de integridad

`db/seed/validaciones.sql` (Etapa 3) ejecutado sobre la copia restaurada del backup (solo
consultas `SELECT`, 10/11/2026):

| Control | Resultado |
|---|---|
| Filas en cada una de las 34 tablas | OK (todas con datos) |
| Renglones sin comprobante, comprobantes sin renglones, clientes sin subtipo | 0 — OK |
| Stock negativo; stock distinto de lo ingresado − transferido (depósito) y de lo transferido − vendido (salas) | 0 — OK |
| Totales de comprobante distintos de la suma de renglones; descuentos distintos del tipo de cliente | 0 — OK |
| Ventas anteriores al alta del cliente o a la primera transferencia; fechas futuras | 0 — OK |
| Vinos cuyas cepas no suman 100 | 0 — OK |
| Tablas con más de 10.000 / 100.000 filas | INFO (2 y 0): con menos de 100.000 comprobantes el control de volumen no aplica |

Ese último punto es el cambio de `validaciones.sql` de esta etapa: los mínimos de volumen eran
un requisito de la carga masiva local; en una base reducida dejaban el control en "falla" sin
que hubiera un problema de datos.

## 5. Backend (API en Render)

| Dato | Valor | Estado |
|---|---|---|
| URL pública | <https://bd-bodegasdelatuel.onrender.com> | Verificado (responde 200) |
| Tecnología | Python 3.12 (`python:3.12-slim`), FastAPI 0.162.2, uvicorn 0.54.0, psycopg 3.2.3 con psycopg-pool 3.3.3 | Verificado (`api/Dockerfile`, `api/requirements.txt`) |
| Forma de despliegue | Contenedor Docker construido desde `api/Dockerfile` | El Dockerfile está preparado para Render; la configuración del servicio en el panel queda **pendiente de confirmación** |
| Puerto | El que asigna Render en la variable `PORT` (8000 si no existe) | Verificado (`api/Dockerfile`) |

### 5.1 Variables de entorno

Se leen en `api/db.py`. **No se documentan valores reales.**

| Variable | Para qué | Por defecto | ¿Sensible? |
|---|---|---|---|
| `API_DB_HOST` | Host de Supabase | `localhost` | No |
| `API_DB_PORT` | Puerto de Supabase | `5432` | No |
| `API_DB_NAME` | Base de datos | `bodegas_atuel` (en Supabase debe ser `postgres`) | No |
| `API_DB_USER` | Usuario de la API | `bodegas_api` | No |
| `API_DB_PASSWORD` | Contraseña de `bodegas_api` | — | **Sí** |
| `API_DB_SSLMODE` | Modo SSL de la conexión | `prefer` (en la nube se recomienda `require`) | No |
| `PORT` | Puerto de escucha | `8000` | No (lo define Render) |

### 5.2 Endpoints para probarla

Todos están en `api/rutas/` y en el README principal. Para comprobar el servicio alcanzan los
de solo lectura (verificados el 10/11/2026, todos con 200):

```sh
curl https://bd-bodegasdelatuel.onrender.com/salud
# {"api":"ok","base_de_datos":"ok"}   (503 {"api":"ok","base_de_datos":"no disponible"} si no llega a Supabase)

curl https://bd-bodegasdelatuel.onrender.com/salas
curl "https://bd-bodegasdelatuel.onrender.com/vinos?tamanio=2"
curl https://bd-bodegasdelatuel.onrender.com/reportes/top-vinos
curl https://bd-bodegasdelatuel.onrender.com/comprobantes/C-00000001
curl https://bd-bodegasdelatuel.onrender.com/transferencias/TR-000001
```

También desde el navegador: <https://bd-bodegasdelatuel.onrender.com/docs> (Swagger).
Los endpoints `POST`, `PUT` y `DELETE` modifican la base de Supabase: no usarlos para "probar".

### 5.3 Logs en Render

1. Entrar a <https://dashboard.render.com> con la cuenta del proyecto.
2. Abrir el servicio de la API (el de la URL `bd-bodegasdelatuel.onrender.com`).
3. Pestaña **Logs**: muestra la salida de uvicorn (cada petición con su código HTTP) y los
   errores de Python o de conexión a la base.
4. La pestaña **Events** muestra los despliegues y reinicios (útil si el servicio no arranca).

Mientras siga el código de diagnóstico del último commit (ver [sección 7](#7-cambios-realizados-en-la-etapa-8)),
cada `GET /salud` escribe en el log una línea `DIAGNOSTICO_DB: ...` con el usuario, el esquema,
el `search_path` y si encuentra la tabla `sala_de_ventas`.

## 6. Frontend (Render)

| Dato | Valor | Estado |
|---|---|---|
| URL pública | **<https://bd-bodegasdelatuel-1.onrender.com>** | Verificado (responde 200) |
| Tecnología | HTML, CSS y JavaScript nativos (módulos ES), sin dependencias ni compilación; servidor `front/servidor.py` (solo biblioteca estándar de Python) | Verificado |
| Forma de despliegue | Contenedor Docker construido desde `front/Dockerfile` | La configuración del servicio en el panel queda **pendiente de confirmación** |
| Puerto | El de la variable `PORT` de Render; si no existe, `FRONT_PORT`; si no, 5173 | Verificado (`front/servidor.py`) |

### 6.1 Funcionalidades disponibles

Las implementadas en la Etapa 7 (detalle en [`front/README.md`](../front/README.md)):

- **Vinos:** catálogo con filtros (tipo, cepa, bodega, añada) y paginación; detalle; alta y
  edición con composición de cepas y maridajes.
- **Ventas:** registro de una venta (cliente, sala, vinos y cantidades) y consulta de un
  comprobante por número.
- **Transferencias:** del depósito central a una sala; alta, carga de vinos, terminar y
  procesar; consulta por número.
- **Tablero:** vinos más vendidos, ventas por sala, transportista más activo, vinos sin stock
  por sala y trazabilidad de un vino.
- **Catálogos:** salas, bodegas, cepas y maridajes.

> Lo que se registre desde el front (ventas, vinos, transferencias) se guarda en la base real
> de Supabase.

### 6.2 Comunicación con el backend (`/api`)

El front llama siempre a rutas relativas `/api/...` (`front/config.js`: `apiUrl: "/api"`).
`servidor.py` recibe esas peticiones y las reenvía a la URL de la variable **`API_URL`**,
quitando el prefijo `/api`:

```text
https://bd-bodegasdelatuel-1.onrender.com/api/salud  →  {API_URL}/salud
```

Así el navegador usa un único origen y la API no necesita habilitar CORS. Si la API no
responde, el proxy devuelve `502 {"error": "No se pudo conectar con la API en ..."}`.

| Variable | Para qué | Valor en Render |
|---|---|---|
| `API_URL` | URL de la API a la que se reenvía `/api` | URL pública de la API. Que está bien configurada se verificó (`/api/salud` del front responde 200); el valor exacto queda **pendiente de confirmación** |
| `PORT` | Puerto de escucha | Lo asigna Render |
| `FRONT_HOST` | Dirección de escucha | `0.0.0.0` (definido en `front/Dockerfile`) |

**Importante:** `front/Dockerfile` trae `API_URL=http://api:8000`, que es el nombre del servicio
en Docker Compose local. En Render ese nombre no existe, así que `API_URL` **tiene que estar
definida** en el servicio del front.

### 6.3 Corrección para Render en `front/servidor.py` y `front/Dockerfile` (error HTTP 500)

Lo que muestra el historial (commit `2624b2e`, *preparar frontend para despliegue en Render*):

| Archivo | Antes | Después | Motivo |
|---|---|---|---|
| `front/servidor.py` | `PUERTO = int(os.environ.get("FRONT_PORT", "5173"))` | `PUERTO = int(os.environ.get("PORT", os.environ.get("FRONT_PORT", "5173")))` | Render asigna el puerto en `PORT` y envía el tráfico a ese puerto. Antes el servidor escuchaba siempre en 5173 (o `FRONT_PORT`), así que Render no encontraba la aplicación |
| `front/Dockerfile` | Comentario "Etapa 7" | Comentario "Etapa 8" y líneas en blanco | Solo comentarios y formato: las instrucciones (`FROM`, `COPY`, `ENV`, `EXPOSE`, `CMD`) no cambiaron |

Resultado verificado: el front responde 200 en Render y su proxy `/api` llega a la API y a la base.

**Pendiente de confirmación:** la relación exacta entre este cambio y el error **HTTP 500**
observado durante el despliegue. Con el código del repositorio, un puerto equivocado o una
`API_URL` inalcanzable producen otros síntomas (servicio sin puerto abierto o `502` del proxy),
no un `500`. Conviene registrar el mensaje de error que mostraban los logs de Render en ese
momento.

### 6.4 Comprobar que front y API funcionan

1. Abrir <https://bd-bodegasdelatuel-1.onrender.com>. Arriba a la derecha, el indicador debe
   decir **Conectado** (consulta `/api/salud`). Al hacer clic se vuelve a verificar.
2. En *Inicio* deben aparecer las cantidades de salas, bodegas, cepas y maridajes.
3. Desde una terminal:

   ```sh
   curl https://bd-bodegasdelatuel-1.onrender.com/api/salud     # pasa por el front
   curl https://bd-bodegasdelatuel.onrender.com/salud           # directo a la API
   ```

   Las dos deben responder `{"api":"ok","base_de_datos":"ok"}`.

## 7. Cambios realizados en la Etapa 8

Commits del 09/11/2026 posteriores a la Etapa 7 (`f520de3`). La Etapa 8 **no** modificó el
esquema, las migraciones, las reglas de negocio ni las pantallas del front.

| Commit | Archivos | Cambio | Motivo | Resultado |
|---|---|---|---|---|
| `c62a907` | `db/seed/carga_masiva.py` | `conectar()` acepta `POSTGRES_SSLMODE` (por defecto `prefer`) y `POSTGRES_ROLE`; si se define, solo admite `bodegas_owner` y ejecuta `SET ROLE bodegas_owner` | Supabase exige SSL, y el usuario administrador no es dueño del esquema: los datos se cargan como `bodegas_owner` | Carga en Supabase con el mismo script de la Etapa 3 |
| `c62a907` | `db/seed/validaciones.sql` | Los controles de volumen (200 y 201) dan `INFO` cuando hay menos de 100.000 comprobantes | La base de Supabase es reducida (2.000 comprobantes) | Todos los controles de integridad en OK (ver 4.3) |
| `c62a907` | `front/servidor.py` | Se quitó la sangría de una línea del texto de ayuda inicial (*docstring*) | Sin efecto en el funcionamiento (cambio accidental de formato) | — |
| `f470d7c` | `api/db.py` | Nueva variable `API_DB_SSLMODE` (por defecto `prefer`) para la conexión | Conexión cifrada con Supabase | La API se conecta a Supabase |
| `f470d7c` | `api/Dockerfile` | `CMD` ahora es `uvicorn ... --port ${PORT:-8000}` | Render asigna el puerto en `PORT` | La API responde en Render |
| `2624b2e` | `front/servidor.py`, `front/Dockerfile` | Puerto desde `PORT`; comentarios | Ver [6.3](#63-corrección-para-render-en-frontservidorpy-y-frontdockerfile-error-http-500) | El front responde en Render |
| `f13d6bc` | `api/main.py` | `GET /salud` consulta `current_user`, `current_schema()`, `search_path` y `to_regclass('sala_de_ventas')` y lo imprime en el log (`DIAGNOSTICO_DB`) | Diagnosticar en la nube si la API encontraba las tablas del esquema `bodegas` (problema de `search_path`) | La API encuentra las tablas (verificado: responde datos). El código de diagnóstico **sigue en el repositorio** |

Recomendación (no aplicada, porque esta tarea no modifica código): cuando ya no haga falta,
volver `GET /salud` a la versión anterior (`SELECT 1`, sin `print`), para no escribir datos de
la conexión en el log en cada consulta de salud.

Pendiente de confirmación: cómo se resolvió finalmente el problema de `search_path` en
Supabase (por ejemplo, si se volvió a aplicar `ALTER ROLE bodegas_api SET search_path = bodegas`
de `007_roles.sql`). La solución no quedó en el repositorio.

## 8. Operación y diagnóstico

### 8.1 Servicios que tienen que estar activos

| Servicio | Si no está activo |
|---|---|
| Proyecto Supabase (base `postgres`, esquema `bodegas`) | `/salud` responde `503 base_de_datos: no disponible` y el front muestra errores en todas las pantallas |
| API en Render | El front carga, pero el indicador dice **Sin conexión** y las pantallas muestran `502 No se pudo conectar con la API` |
| Front en Render | La dirección del sistema no abre (la API sigue respondiendo directo) |

> Supabase pausa los proyectos gratuitos que pasan un tiempo sin actividad. Si `/salud`
> responde `503`, revisar en el panel de Supabase que el proyecto esté activo
> (pendiente de confirmación el plan contratado).

### 8.2 Cómo ubicar dónde está el problema

| Síntoma | Probable causa | Qué hacer |
|---|---|---|
| La página tarda mucho en abrir la primera vez | Render despertando el servicio (plan gratuito) | Esperar 30-60 s y recargar |
| El front no abre | Servicio del front caído o desplegándose | Logs y Events del servicio del front en Render |
| El front abre, el indicador dice **Sin conexión** y aparece `HTTP 502 · No se pudo conectar con la API en …` | La API está suspendida, caída o `API_URL` está mal | Abrir <https://bd-bodegasdelatuel.onrender.com/salud>; si responde, revisar `API_URL` del front |
| El indicador dice **Sin base de datos** o `/salud` responde `503` | La API no llega a Supabase | Logs de la API; revisar `API_DB_*` (host, puerto, usuario, contraseña, `API_DB_SSLMODE`) y que el proyecto Supabase esté activo |
| Errores `500` en consultas | Error no previsto de la base | Logs de la API en Render (la respuesta no muestra detalles a propósito) |
| `409` con un mensaje de regla (por ejemplo, stock insuficiente) | Regla de negocio de la base | No es una falla: el mensaje explica qué regla no se cumplió |

## 9. Seguridad

- **No se publican contraseñas** ni valores de variables de entorno: este documento solo nombra
  las variables. Los valores están en los paneles de Render y Supabase.
- Las credenciales **administrativas** de Supabase no se cargan en Render; la API usa solo
  `bodegas_api`, sin permisos de dueño y sin escritura directa de stock ni auditoría.
- `.env` y sus variantes están excluidos en `.gitignore` (excepto `.env.example`).
- Los backups (`*.dump`) están excluidos en `.gitignore` y se guardaron **fuera del
  repositorio** (ver el documento de backup).
- La conexión con Supabase debe usar SSL (`sslmode=require` o superior).

## 10. Evidencias

Ubicación propuesta para las capturas: `docs/etapa8/capturas/`. Al revisar el proyecto no se
encontraron capturas del despliegue en Render ni Supabase: las de esta tabla quedan **pendientes
de incorporar**. (Las capturas de la restauración sí existen; están listadas en el documento de
backup.)

| N° | Descripción | Acción | Qué debe demostrar | Estado |
|---|---|---|---|---|
| D-01 | Panel de Render con el servicio de la API activo | Dashboard de Render → servicio de la API | Servicio *Live*, URL pública | Pendiente |
| D-02 | `/salud` de la API | Abrir `https://bd-bodegasdelatuel.onrender.com/salud` | `{"api":"ok","base_de_datos":"ok"}` | Pendiente |
| D-03 | Variables de la API en Render (**valores ocultos**) | Servicio de la API → *Environment* | Nombres de las variables `API_DB_*` | Pendiente |
| D-04 | Panel de Render con el servicio del front activo | Dashboard → servicio del front | Servicio *Live*, URL pública | Pendiente |
| D-05 | Front funcionando | Abrir `https://bd-bodegasdelatuel-1.onrender.com` | Pantalla de inicio con el indicador **Conectado** | Pendiente |
| D-06 | Logs de Render | Servicio → *Logs* | Peticiones respondidas con 200 | Pendiente |
| D-07 | Proyecto Supabase | *Project Settings* | Versión de PostgreSQL y región | Pendiente |

## 11. Pendientes de confirmación

1. Región del proyecto Supabase y plan contratado.
2. Host, puerto y tipo de conexión (directa o *pooler*) que usa la API, y valor de `API_DB_SSLMODE` en Render.
3. Configuración de los servicios en Render (tipo de servicio, carpeta raíz, plan) y valor exacto de `API_URL` del front.
4. Herramienta y usuario con que se ejecutaron las migraciones en Supabase; cómo se asignaron la contraseña de `bodegas_api` y el permiso `SET ROLE bodegas_owner`.
5. Comando exacto de la carga masiva (se infiere `carga_masiva.py 2000` por los 2.000 comprobantes).
6. Causa exacta del error HTTP 500 del front y cómo se resolvió el problema de `search_path` en la nube.
7. Capturas del despliegue (sección 10).
