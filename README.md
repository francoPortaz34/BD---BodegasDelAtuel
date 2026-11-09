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
| | `PUT /vinos/{cod}` | Modificación de la ficha y, opcionalmente, de la composición y los maridajes, en una transacción (si cambia el precio, el trigger lo audita) |
| | `DELETE /vinos/{cod}` | Baja (409 si tiene movimientos) |
| Clientes | `GET /clientes`, `GET /clientes/{id}` | Listado paginado (`pagina`, `tamanio` ≤ 100) con búsqueda opcional `nombre` y `documento`; detalle con tipo y subtipo |
| | `POST /clientes` | Alta del cliente y de su subtipo (socio, distribuidor o exportador) |
| | `PUT /clientes/{id}`, `DELETE /clientes/{id}` | Modificación y baja (409 si tiene comprobantes) |
| Comprobantes | `POST /comprobantes` | Venta completa (cabecera y renglones) en una transacción |
| | `GET /comprobantes/{nro}` | Cabecera y renglones |
| Transferencias | `POST /transferencias` | Alta (nace en confección) |
| | `GET /transferencias/{nro}` | Cabecera, estado actual y renglones (404 si no existe) |
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
| Catálogos | `GET /salas` | Todas las salas (tengan o no ventas) con su localidad |
| | `GET /bodegas` | Bodegas del grupo |
| | `GET /cepas` | Catálogo de cepas |
| | `GET /maridajes` | Catálogo de maridajes |

La API no calcula totales, descuentos ni stock: los resuelven los triggers, funciones y
procedimientos de la base. Todas las consultas están parametrizadas.

### Catálogos (Etapa 7)

Listas de solo lectura para los selectores del front. Son tablas chicas (25 salas,
21 bodegas, 12 cepas, 8 maridajes en el dataset): se devuelven completas, sin paginar,
como un arreglo JSON. Responden `200` (o `500`/`503` si falla la base).

```text
GET /salas      -> [{"id_sala": 1, "calle": "Diag. San Martin", "numero": "502",
                     "dia_cierre_semanal": "domingo", "id_localidad": 203,
                     "localidad": "Ciudad de San Rafael", "provincia": "Mendoza"}, ...]
GET /bodegas    -> [{"id_bodega": 3, "cuit": "30820426546", "razon_social": "Bodega Aguero",
                     "calle": "Diagonal 195 B", "numero": "3802"}, ...]      (por razón social)
GET /cepas      -> [{"id_cepa": 5, "nombre": "Bonarda", "tipo": "tinta"}, ...]   (por nombre)
GET /maridajes  -> [{"id_maridaje": 4, "nombre": "Carnes blancas",
                     "temperatura_sugerida": 12.0}, ...]                     (por nombre)
```

### Detalle de una transferencia

`GET /transferencias/{nro}` (número de solicitud) devuelve lo mismo que las operaciones
`POST` de transferencias; el front usa `estado` (`en_confeccion`, `terminado`,
`procesado`) para habilitar los botones.

```text
200 {"id_transferencia": 1, "num_solicitud": "TR-000001", "fecha_confeccion": "2021-01-02",
     "estado": "procesado", "id_sala": 1,
     "renglones": [{"id_vino": 60, "cod_vino": "V0060", "nombre_comercial": "Malbec Clásico",
                    "cantidad_botellas": 36}, ...]}
404 {"detail": "Transferencia no encontrada"}
```

### Búsqueda de clientes

`GET /clientes?nombre=garc&documento=20&pagina=1&tamanio=20`

- `nombre`: parte de `nombre_o_razon_social`, sin distinguir mayúsculas (`ILIKE`).
- `documento`: parte de `num_documento`.
- Los dos son opcionales y se combinan con AND. Vacíos o solo espacios = sin filtro.
- `%` y `_` se buscan literalmente (se escapan) y el texto viaja como parámetro.
- La paginación la hace PostgreSQL (`LIMIT`/`OFFSET`); `tamanio` sigue siendo 1 a 100
  (`422` si se excede). Sin filtros la consulta es la misma de antes.

```text
200 {"pagina": 1, "tamanio": 20, "clientes": [{"id_cliente": 3, "nombre_o_razon_social": "Garcia-Valdez",
     "num_documento": "30365640427", ...}]}
```

### Edición de vinos

`PUT /vinos/{cod}` recibe la ficha (los mismos campos de antes) y dos campos opcionales:

```json
{"nombre_comercial": "Malbec Clásico", "tipo": "tinto", "anada": 2016, "presentacion_ml": 750,
 "graduacion_alcoholica": 14.0, "precio_venta": 29500, "id_bodega": 3,
 "cepas": [{"id_cepa": 1, "porcentaje_corte": 70}, {"id_cepa": 2, "porcentaje_corte": 30}],
 "maridajes": [1, 2]}
```

| Campo | Omitido o `null` | Lista con elementos | Lista vacía `[]` |
|---|---|---|---|
| `cepas` | La composición no se toca | Reemplaza la composición completa | Quita la composición: la regla RN-05 la rechaza (409) si el vino tenía cepas |
| `maridajes` (ids) | Los maridajes no se tocan | Reemplaza los maridajes | Quita todos los maridajes |

Todo ocurre en una transacción (ficha, composición y maridajes): si algo falla no queda
ningún cambio. La API no valida la suma de porcentajes; la controla el trigger diferido
de la base al hacer COMMIT y su mensaje llega tal cual:

| Situación | HTTP | Cuerpo |
|---|---|---|
| Correcto | 200 | Ficha completa (igual que `GET /vinos/{cod}`) |
| Vino inexistente | 404 | `{"detail": "Vino no encontrado"}` |
| Porcentajes que no suman 100 | 409 | `{"error": "Los porcentajes de corte del vino 60 suman 90.00 y deben sumar 100 (RN-05)", "sqlstate": "P0001"}` |
| Cepa o maridaje inexistente | 409 | `{"error": "El dato referenciado no existe o tiene registros relacionados", "sqlstate": "23503"}` |
| Cepa o maridaje repetido | 409 | `{"error": "Ya existe un registro con esos datos", "sqlstate": "23505"}` |
| CHECK violado (por ejemplo graduación) | 422 | `{"error": "Un valor no cumple una restricción de la base", "sqlstate": "23514"}` |
| Cuerpo con formato inválido | 422 | `{"detail": [...]}` (validación de FastAPI) |

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

Son 56 pruebas (`tests/test_api.py` de la Etapa 6 y `tests/test_etapa7.py` con los
catálogos, el detalle de transferencias, la búsqueda de clientes y la edición de vinos)
y **ninguna necesita PostgreSQL**: reemplazan la conexión por una
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
