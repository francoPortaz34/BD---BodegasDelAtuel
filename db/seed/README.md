# db/seed – Carga masiva (Etapa 3)

Scripts y catálogos para poblar el esquema `bodegas` con datos sintéticos
coherentes, respetando **todas** las restricciones y triggers de la Etapa 2.
Las decisiones de diseño, el orden de carga y los riesgos están en
[`docs/etapa3_carga_masiva.md`](../../docs/etapa3_carga_masiva.md).

> **Estado:** el perfil `prueba` se cargó completo en una PostgreSQL 16
> **aislada** (contenedor `bodegas_atuel_prueba`, puerto 55433), con 0
> controles en FALLA, incluyendo una interrupción simulada y su reanudación.
> La carga **definitiva** todavía no se ejecutó (ver "Carga definitiva").

## Contenido

| Archivo | Para qué sirve |
|---|---|
| `carga_masiva.py` | Genera el plan de datos (determinístico) y lo carga por fases y por lotes. |
| `validaciones.sql` | Consultas de control de **solo lectura**: conteos, huérfanas, stock, totales, cronología, etc. |
| `medir_insercion.py` | Compara la inserción fila por fila con la inserción por lotes. Termina con ROLLBACK y no deja datos (ver su limitación). |
| `../../pyproject.toml`, `../../uv.lock` | Dependencias de Python (`psycopg`, `Faker`) con versiones fijas, gestionadas con `uv` (en la raíz del repositorio). |
| `csv/localidades.csv` | 269 localidades de Mendoza (ver `docs/etapa3_localidades.md`). |
| `csv/encargados_auxiliares.csv` | Un encargado ficticio por localidad. `localidad` y `cod_postal` son columnas auxiliares y **no se insertan**. |
| `csv/localidades_excluidas.csv` | 36 localidades sin código postal. Es documentación y **no se carga**. |
| `csv/departamentos.csv` | Los 18 departamentos, iguales a los de `localidades.csv`. |
| `csv/cepas.csv`, `csv/maridajes.csv` | Catálogos del Anexo B del TPI. |
| `csv/tipos_cliente.csv` | Socio 10 %, Distribuidor 20 %, Exportador 30 % (RN-06). |

## Requisitos previos

1. Contenedor de desarrollo levantado (ver `docker-compose.yml`) y `.env`
   completado a partir de `.env.example`.
2. Base con las migraciones **001 a 007** aplicadas y **sin datos** en el
   esquema `bodegas`. Si se quiere una base aparte, crearla y aplicarle las
   migraciones antes de cargar.
3. Python 3.10 o superior y [`uv`](https://docs.astral.sh/uv/) en el equipo
   anfitrión. Las dependencias se instalan desde `pyproject.toml` y `uv.lock`
   (raíz del repositorio) en un entorno local `.venv`, que está en `.gitignore`:

   ```sh
   uv sync
   ```

   Los comandos de las secciones siguientes se pueden ejecutar anteponiendo
   `uv run` (por ejemplo `uv run python db/seed/carga_masiva.py --solo-plan`),
   o bien activando el entorno:
   - PowerShell: `.venv\Scripts\Activate.ps1`
   - Git Bash: `source .venv/Scripts/activate`
   - Linux/macOS: `source .venv/bin/activate`

   Versiones verificadas en PyPI: `psycopg-binary 3.2.3` tiene wheel para
   Windows y Python 3.12, y `Faker 33.1.0` es Python puro y trae el locale
   `es_AR`.

## Conexión

El script lee las mismas variables que `docker-compose.yml`, tomándolas del
entorno o del archivo `.env` de la raíz:

| Variable | Por defecto |
|---|---|
| `POSTGRES_HOST` (o `PGHOST`) | `127.0.0.1` |
| `POSTGRES_PORT` (o `PGPORT`) | `55432` |
| `POSTGRES_DB` (o `PGDATABASE`) | (obligatoria) |
| `POSTGRES_USER` (o `PGUSER`) | (obligatoria) |
| `POSTGRES_PASSWORD` (o `PGPASSWORD`) | (sin valor: se usa `.pgpass`) |

Perfil `definitivo` (el de por defecto): para apuntar a otra base basta con
definir la variable antes del comando, por ejemplo
`POSTGRES_DB=bodegas_carga python db/seed/carga_masiva.py`, o usar
`--env otra_ruta/.env`. La contraseña no se imprime ni se guarda.

Perfil `prueba`: **exige** `--env` con un archivo de prueba y aplica las
protecciones descritas en "Perfiles y prueba aislada". **No** toma variables
del entorno del proceso ni del `.env` principal.

Se usa el usuario de `POSTGRES_USER`, que en el contenedor es superusuario.
Hace falta para ejecutar `ANALYZE` sobre todas las tablas. La lógica de stock
igual corre a través de los procedimientos y triggers `SECURITY DEFINER`.

## Pasos

Ejecutar desde la raíz del repositorio:

```sh
# 1. Ver qué se va a generar, sin conectarse a ninguna base.
#    El plan de ventas depende del día de la semana de la carga (ver "Cronología").
python db/seed/carga_masiva.py --solo-plan
python db/seed/carga_masiva.py --solo-plan --fecha-carga 2026-11-09   # simular otro día

# 2. Revisar la base destino SIN escribir: valida el esquema, los triggers y el estado de cada fase
python db/seed/carga_masiva.py

# 3. Ejecutar la carga (guarda la salida y un reporte con tiempos y conteos)
python db/seed/carga_masiva.py --confirmar --reporte db/seed/reporte_carga.json | tee db/seed/carga.log

# 4. Volver a correr las consultas de control cuando se quiera (solo lectura)
python db/seed/carga_masiva.py --verificar
#    o con psql dentro del contenedor:
docker exec bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /db/seed/validaciones.sql'

# 5. (Opcional) Medir fila por fila contra lotes (no deja datos)
python db/seed/medir_insercion.py --filas 5000
```

`*.log` está en `.gitignore`. El reporte JSON se versiona solo si el grupo lo decide.

### Códigos de salida de `carga_masiva.py`

| Código | Significado |
|---|---|
| 0 | Plan generado, revisión sin escritura o carga terminada sin controles con FALLA. |
| 1 | Las consultas de control encontraron al menos una FALLA. |
| 2 | El script detuvo la carga: datos que no coinciden con el plan, esquema incompleto, triggers inactivos, CSV inválido, otra carga en curso, etc. **No se modificó nada** en esa ejecución. |
| 3 | PostgreSQL rechazó una operación, por ejemplo un trigger. Se muestran el SQLSTATE y el mensaje. **Solo se revierte la transacción en curso** (el lote o la fase); lo confirmado antes queda intacto. |

### Si la carga falla

1. Leer el mensaje: el script indica la fase y la causa. Con código 3, también
   el SQLSTATE y el contexto del trigger.
2. Corregir la causa (por ejemplo, aplicar una migración que falte).
3. Volver a ejecutar `python db/seed/carga_masiva.py` para revisar el estado y
   después `--confirmar`. Las fases completas se saltean y la fase por lotes
   interrumpida se reanuda desde el primer documento que falta.

### Después de la carga (manual, recomendado)

```sh
# Recuperar el espacio de las versiones de fila que dejan los triggers y actualizar estadísticas
docker exec bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "VACUUM (ANALYZE) bodegas.comprobante" -c "VACUUM (ANALYZE) bodegas.stock_sala"'

# Refrescar la vista materializada de ventas mensuales (006_vistas.sql)
docker exec bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "REFRESH MATERIALIZED VIEW bodegas.mv_ventas_mensuales_sala"'

# Volcado de la base cargada (paso 8 del TPI)
docker exec bodegas_atuel_db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip' > dump_completo.sql.gz
```

`dump_completo.sql.gz` no está cubierto por `.gitignore` (solo `*.dump`). Por
su tamaño, conviene no subirlo al repositorio y entregarlo aparte.

## Cronología

- **Datos históricos:** cosechas, análisis, ingresos al depósito (segundo
  semestre de 2024), altas de clientes, empleados y permisos. Todas las fechas
  son anteriores o iguales al 30/06/2026 (`FIN_HISTORIAL`).
- **Transferencias:** quedan con `fecha_confeccion = CURRENT_DATE`, el día de
  la carga, porque lo impone `trg_transferencia_fecha`.
- **Comprobantes:** quedan con `fecha = CURRENT_DATE` (DEFAULT de la columna) y
  se cargan **después** de procesar todas las transferencias. No hay ventas
  históricas.
- **Salas que venden:** solo las que **no cierran** el día de la semana de la
  carga. Antes de cada lote el script controla, dentro de la misma
  transacción, que ninguna sala del lote cierre ese día, que todas las
  transferencias estén procesadas y no sean futuras, y que cada (sala, vino)
  vendido tenga una transferencia procesada con fecha anterior o igual.

## Repetición controlada

- **Mismos datos.** Para obtener los mismos datos tienen que coincidir la
  semilla (por defecto `20261106`, se cambia con `--semilla N`), el **día de
  la semana** de la carga y las versiones de Python y de Faker. El resumen
  del plan y el reporte JSON muestran la fecha de carga, el locale de Faker y
  la versión de Python.
- **Lo que no es reproducible:** los valores que pone el motor, es decir las
  fechas de transferencias y comprobantes (el día de la carga),
  `auditoria_precio.fecha_hora`/`usuario` y los ids `SERIAL`.
- **Fases.** La carga se divide en 8 fases. Antes de escribir, el script
  compara la base con el plan usando claves naturales, cantidades por tabla y,
  en las fases por lotes, el **contenido de una muestra** de hasta 300
  documentos:
  - una fase **completa** se saltea;
  - una fase **pendiente** se ejecuta;
  - una fase **en curso** (solo ingresos, transferencias y comprobantes) se
    reanuda desde el primer documento que falta;
  - una fase **inconsistente** detiene la carga **sin borrar ni modificar
    nada**. Pasa con datos ajenos, otra semilla, otra versión de Python u
    otro día de la semana.
- **Reanudar comprobantes otro día.** Si la fase de comprobantes queda a medias,
  el plan se regenera con el día de los comprobantes ya cargados. Puede
  reanudarse otro día solo si ninguna sala con ventas pendientes cierra ese
  día de la semana; si no, el script se detiene (código 2) y avisa. Lo más
  simple es reanudar el mismo día o el mismo día de la semana. Lo ya cargado
  conserva su fecha y la cronología se mantiene (siempre después de las
  transferencias).
- **Base con actividad posterior.** Si la carga está completa y después la
  base tuvo actividad (por ejemplo, cambios de precio o ventas de la API), el
  script lo informa ("hay filas posteriores a la carga") y no escribe. En
  cambio, si hay filas de más y la carga **no** está terminada, se detiene,
  porque podrían ser datos ajenos. Los controles marcados con `[*]` en
  `validaciones.sql` suponen una base recién cargada.
- Sin `--confirmar`, el script nunca escribe.
- **Triggers activos.** Se exige que todos los triggers de 005 estén activos
  (`tgenabled` `O` o `A`) y que la sesión tenga `session_replication_role =
  'origin'`. El script no cambia ninguno de los dos valores.
- Un bloqueo consultivo (`pg_try_advisory_lock`) impide que dos cargas corran
  a la vez sobre la misma base. No bloquea a la API: no usar la base mientras
  se carga.
- Para cargar de nuevo desde cero hay que hacerlo sobre una base nueva con las
  migraciones aplicadas. **El script no borra datos.**

## Medición fila por fila contra lotes: limitación

`medir_insercion.py` inserta en la tabla real `encargado` de tres formas
(una sentencia por fila, `executemany` y `COPY`), todas dentro de **una
transacción que se revierte**. **No mide un COMMIT por fila**, porque eso
dejaría datos persistentes. Las alternativas tampoco sirven: una tabla
temporal no escribe WAL, y una tabla auxiliar o `UNLOGGED` modificaría el
esquema. Por eso la ventaja real de los lotes es mayor que la que muestra el
script. Si el grupo quiere medir el COMMIT por fila, debe hacerlo en una base
descartable creada para eso y dejarlo registrado.

## Perfiles y prueba aislada

Los volúmenes y los tamaños de lote están centralizados en `Perfil`
(`carga_masiva.py`: `PERFIL_DEFINITIVO`, `PERFIL_PRUEBA`) y se eligen con
`--perfil`:

| Perfil | Volumen | Lotes | Mínimos TPI | Conexión |
|---|---|---|---|---|
| `definitivo` (por defecto) | 150.000 comprobantes, 525.000 renglones | 250 documentos / 5.000 comprobantes | se exigen | `.env` de la raíz o `--env` |
| `prueba` | 300 comprobantes, 1.050 renglones (6 salas, 24 vinos, 200 clientes) | 5 documentos / 50 comprobantes | no aplican (200 y 201 se informan como INFO) | **sólo** `--env` de prueba |

Antes de generar, `validar_perfil()` controla los parámetros y lista **todos**
los errores juntos, con el parámetro a corregir:
- cada bodega tiene al menos un vino;
- `vinos_por_sala` está entre el máximo de renglones por comprobante y `n_vinos`;
- las localidades por transportista son compatibles con las salas;
- los ajustes de precio no superan los vinos;
- hay al menos un cliente de cada tipo;
- hay al menos un empleado por sala;
- los márgenes de stock son válidos.

Después de generar, `controlar_stock_plan()` verifica que el stock planificado
cubra las ventas.

**Protecciones del perfil `prueba`.** El script se niega a conectarse si:
- falta `--env`;
- el archivo es el `.env` principal;
- el archivo no declara `BODEGAS_ENTORNO=prueba`;
- el destino usa el puerto o el nombre de base de la principal, con
  **cualquier** host. Una IP de la red o `host.docker.internal` pueden llevar a
  la misma instancia. Como principal se toman el `.env` de la raíz, las
  variables del proceso y los valores por defecto de `docker-compose.yml`
  (55432 y `bodegas_atuel`).

Además:
- lee solo las variables del archivo indicado;
- muestra el destino antes de operar (`Perfil: prueba | Base destino:
  usuario@host:puerto/base`, sin la contraseña);
- verifica `current_database()` después de conectar.

**Entorno aislado usado en la prueba** (PowerShell, desde la raíz). No toca
`docker-compose.yml`, `bodegas_atuel_db` ni `bodegas_atuel_pgdata`. Los datos
viven en `tmpfs`, así que detener el contenedor borra todo.

```powershell
# .env.prueba (ignorado por .gitignore: .env.*)
#   BODEGAS_ENTORNO=prueba
#   POSTGRES_HOST=127.0.0.1
#   POSTGRES_PORT=55433
#   POSTGRES_DB=bodegas_prueba
#   POSTGRES_USER=bodegas_prueba
#   POSTGRES_PASSWORD=<contraseña local>
docker run -d --name bodegas_atuel_prueba --env-file .env.prueba `
  -e TZ=America/Argentina/Mendoza -e PGTZ=America/Argentina/Mendoza `
  -p 127.0.0.1:55433:5432 --tmpfs /var/lib/postgresql/data:rw `
  -v "${PWD}\db:/db:ro" postgres:16
foreach ($f in Get-ChildItem db\migrations\00[1-7]_*.sql | Sort-Object Name) {
  docker exec bodegas_atuel_prueba psql -v ON_ERROR_STOP=1 -q -U bodegas_prueba -d bodegas_prueba -f "/db/migrations/$($f.Name)"
}
uv run python db/seed/carga_masiva.py --perfil prueba --env .env.prueba --solo-plan
uv run python db/seed/carga_masiva.py --perfil prueba --env .env.prueba              # revisión
uv run python db/seed/carga_masiva.py --perfil prueba --env .env.prueba --confirmar
uv run python db/seed/carga_masiva.py --perfil prueba --env .env.prueba --verificar
# Limpieza (sólo el contenedor de prueba): docker stop bodegas_atuel_prueba; docker rm bodegas_atuel_prueba
```

`--interrumpir-en-lote N` (solo con `--perfil prueba --confirmar`) simula un
fallo dentro del lote N de comprobantes, después de insertar cabeceras y
renglones. Sirve para comprobar que ese lote se revierte entero y que la
siguiente ejecución reanuda sin duplicar.

## Carga definitiva

La carga definitiva va a la base del `.env` principal: `bodegas_atuel` en
`127.0.0.1:55432`, contenedor `bodegas_atuel_db`. Antes de ejecutarla hay que
verificar:

1. **Que sea la base correcta.** El script muestra `Perfil: definitivo | Base
   destino: ...` antes de operar, y el modo revisión (sin `--confirmar`) no
   escribe nada.
2. **Que la base tenga las migraciones 001 a 007 y esté vacía.** La revisión
   tiene que mostrar las 8 fases `pendiente`.
3. **No volver a aplicar `001_esquema.sql` sobre una base con datos.** Empieza
   con `DROP SCHEMA IF EXISTS bodegas CASCADE`.
4. **Que nadie más use la base durante la carga** (la API, por ejemplo).
5. **El día de la semana.** `CURRENT_DATE` del contenedor (zona
   `America/Argentina/Mendoza`) define qué salas venden. Conviene empezar con
   tiempo antes de la medianoche.

## Tiempos esperados

Referencia medida con el perfil `prueba` en la base aislada (`tmpfs`):
plan en 0,3 s; comprobantes y renglones en unos 0,4 ms por renglón
(1.050 renglones en 0,4 s); carga completa en 2,5 s.

Para el perfil `definitivo` **es solo una estimación**:
- generación del plan: unos 15 s;
- catálogos, maestros, vinos y clientes: menos de 1 minuto;
- ingresos y transferencias: de 1 a 3 minutos;
- **comprobantes (150.000 cabeceras y 525.000 renglones), la fase más lenta:
  de 5 a 20 minutos.** Al extrapolar linealmente salen unos 3,5 minutos, pero
  hay que sumar las tablas más grandes y un disco más lento que `tmpfs`.

El script muestra el avance cada 5.000 comprobantes.
