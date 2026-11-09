# Bodegas del Atuel

Trabajo Práctico Integrador de Bases de Datos (UTN FRSR): sistema de gestión de una
empresa vitivinícola sobre PostgreSQL 16, con una API REST en FastAPI.

| Carpeta | Contenido |
|---|---|
| `db/migrations/` | Esquema, restricciones, funciones, procedimientos, triggers, vistas, roles e índices (001 a 008) |
| `db/seed/` | Carga masiva de datos (Etapa 3). Ver [`db/seed/README.md`](db/seed/README.md) |
| `db/rendimiento/` | Mediciones de índices (Etapa 4) |
| `consultas/` | Consultas SQL de la Etapa 5 |
| `tests/` | Pruebas SQL de la base (Etapa 2) |
| `api/` | API REST (Etapa 6) |
| `docs/` | DER, esquema relacional, diccionario de datos e informes de cada etapa |

## Requisitos

- Docker y Docker Compose.
- Para correr las pruebas de la API fuera de Docker: Python 3.12.

## Configuración (.env)

```sh
cp .env.example .env
```

Completar en `.env`:

- `POSTGRES_PASSWORD`: contraseña del superusuario del contenedor de PostgreSQL.
- `API_DB_PASSWORD`: contraseña del rol `bodegas_api`. La API se conecta **siempre** con
  ese rol (lectura/escritura, sin privilegios de propietario), nunca con el superusuario.
  En una instalación limpia se asigna sola en el primer arranque (ver
  [Inicialización de la base](#inicialización-de-la-base)).

El archivo `.env` no se sube al repositorio.

## Levantar el proyecto

```sh
docker compose up
```

Levanta dos servicios:

| Servicio | Contenedor | Dirección |
|---|---|---|
| `db` (PostgreSQL 16) | `bodegas_atuel_db` | `127.0.0.1:55432` (puerto configurable con `POSTGRES_PORT`) |
| `api` (FastAPI) | `bodegas_atuel_api` | `http://127.0.0.1:8000` |

La API espera a que PostgreSQL esté saludable (`healthcheck`) y se conecta al servicio
`db` por la red interna de Docker.

### Inicialización de la base

**Primer arranque (volumen vacío).** PostgreSQL ejecuta `db/init/01_inicializar.sh`, que:

1. Crea los roles `bodegas_owner`, `bodegas_api` y `bodegas_reportes`.
2. Restaura `dump_completo.sql.gz`: esquema, datos cargados, triggers, índices y permisos.
3. Aplica `db/migrations/007_roles.sql` (el volcado no guarda el `search_path` de los roles).
4. Asigna a `bodegas_api` la contraseña de `API_DB_PASSWORD` del `.env`.
5. Ejecuta `ANALYZE`.

Tarda unos minutos; el progreso se ve con `docker compose logs -f db`. La API arranca
cuando la base termina de inicializarse.

**Arranques siguientes o volumen con datos.** El script **no se ejecuta**: PostgreSQL
solo corre la inicialización cuando el volumen está vacío. La base queda como estaba y
cambiar `API_DB_PASSWORD` en el `.env` no modifica la contraseña. En una base ya
existente se asigna a mano una vez:

```sh
docker exec -it bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
\password bodegas_api
```

Para volver a inicializar desde cero hay que borrar el volumen
(`docker compose down -v`), lo que **elimina todos los datos** de la base local.

Las migraciones y la carga masiva también se pueden aplicar a mano, como indica
[`db/seed/README.md`](db/seed/README.md).

Comprobar que la API llega a la base:

```sh
curl -i http://127.0.0.1:8000/salud
```

`200 {"api": "ok", "base_de_datos": "ok"}` si se conecta; `503` si no puede conectarse.

## Documentación de la API

- Swagger: <http://127.0.0.1:8000/docs>
- OpenAPI (JSON): <http://127.0.0.1:8000/openapi.json>

## Endpoints

| Recurso | Método y ruta | Descripción |
|---|---|---|
| Salud | `GET /salud` | Verifica la conexión con la base |
| Vinos | `GET /vinos` | Catálogo paginado (`pagina`, `tamanio`) con filtros `tipo`, `cepa` (nombre), `bodega` (id) y `anada` |
| | `GET /vinos/{cod}` | Detalle con bodega, cepas (porcentajes) y maridajes |
| | `POST /vinos` | Alta del vino con su composición, en una transacción |
| | `PUT /vinos/{cod}` | Modificación (si cambia el precio, el trigger lo audita) |
| | `DELETE /vinos/{cod}` | Baja (409 si tiene movimientos) |
| Clientes | `GET /clientes`, `GET /clientes/{id}` | Listado paginado y detalle con tipo y subtipo |
| | `POST /clientes` | Alta del cliente y de su subtipo (socio, distribuidor o exportador) |
| | `PUT /clientes/{id}`, `DELETE /clientes/{id}` | Modificación y baja (409 si tiene comprobantes) |
| Comprobantes | `POST /comprobantes` | Venta completa (cabecera y renglones) en una transacción |
| | `GET /comprobantes/{nro}` | Cabecera y renglones |
| Transferencias | `POST /transferencias` | Alta (nace en confección) |
| | `POST /transferencias/{nro}/renglones` | Carga de un renglón mientras está en confección |
| | `POST /transferencias/{nro}/terminar` | Pasa a terminado |
| | `POST /transferencias/{nro}/procesar` | Llama a `sp_procesar_transferencia` |
| Ingresos | `POST /ingresos`, `POST /ingresos/{cod}/renglones` | Alta y carga de renglones |
| | `POST /ingresos/{cod}/procesar` | Pasa a terminado y llama a `sp_procesar_ingreso`, en una transacción |
| Reportes | `GET /reportes/top-vinos` | S1: 10 vinos más vendidos |
| | `GET /reportes/ventas-por-sala` | S8: ventas por sala del último trimestre |
| | `GET /reportes/vinos-sin-stock?sala=N` | S6: sin stock en la sala y con stock en el depósito |
| | `GET /reportes/transportista-activo` | S7: transportista con más ingresos del último mes |
| | `GET /reportes/trazabilidad/{cod}` | Recorrido de un vino: ingresos, transferencias y ventas por sala |

La API no calcula totales, descuentos ni stock: los resuelven los triggers, funciones y
procedimientos de la base. Todas las consultas están parametrizadas.

### Errores

Los errores de PostgreSQL se traducen a HTTP según su SQLSTATE (`api/errores.py`):

| SQLSTATE | Situación | HTTP |
|---|---|---|
| 23505 | UNIQUE violado | 409 |
| 23503 | FOREIGN KEY violada | 409 |
| 23514 | CHECK violado | 422 |
| 23502 | NOT NULL violado | 422 |
| P0001 | Regla de negocio (trigger o procedimiento), con su mensaje | 409 |
| 22P02 | Formato inválido para el tipo | 400 |
| 40001 / 40P01 | Serialización o deadlock (reintentar) | 503 |
| Otro | Error no contemplado (sin detalles) | 500 |

## Pruebas automáticas de la API

Desde la carpeta `api/`:

```sh
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt     # en Linux/macOS: .venv/bin/pip
.venv/Scripts/python -m pytest -v
```

O dentro del contenedor: `docker exec bodegas_atuel_api python -m pytest -v`.

Son 33 pruebas y **ninguna necesita PostgreSQL**: reemplazan la conexión por una
conexión falsa (`api/tests/conftest.py`) que registra el SQL enviado y simula las
respuestas de la base. Verifican rutas, paginación, filtros, parámetros SQL (incluida
una inyección SQL que se trata como texto), transacciones, respuestas 404 y la
traducción SQLSTATE → HTTP.

Las pruebas de reglas de negocio (venta sin stock, cambio de estado inválido, precio
negativo, cepas que no suman 100, borrar un cliente con comprobantes) **simulan** el
error exacto que lanza PostgreSQL: comprueban que la API responde el código correcto,
con el mensaje de la regla y sin dejar datos a medias. Que las reglas existan y
funcionen en la base lo prueban las pruebas SQL de la Etapa 2 (`tests/db_tests.sql`).
Probar los endpoints contra la base real requiere la base cargada y la contraseña de
`bodegas_api`.

## Ejecutar la API sin Docker (opcional)

Con la base del contenedor levantada, desde `api/` en PowerShell:

```powershell
$env:API_DB_HOST = "localhost"
$env:API_DB_PORT = "55432"
$env:API_DB_NAME = "bodegas_atuel"
$env:API_DB_USER = "bodegas_api"
$env:API_DB_PASSWORD = "contraseña_de_bodegas_api"
.\.venv\Scripts\python -m uvicorn main:app --reload
```
