# Etapa 8 - Backup y restauración de prueba

Se hicieron dos backups de la base de Supabase y se restauró uno de ellos en un contenedor
PostgreSQL independiente para comprobar que el backup sirve. El despliegue está en
[`etapa8_despliegue.md`](etapa8_despliegue.md).

> Convención: lo **verificado** se comprobó en los archivos de backup, en el contenedor de
> prueba o en las capturas del procedimiento. Lo marcado **pendiente de confirmación** no quedó
> registrado. Los backups se hicieron el 09/11/2026 a las 23:49 y 23:54 (hora de Argentina,
> UTC−3) y la restauración el 10/11/2026 entre las 00:06 y las 00:18.

## 1. Archivos generados

| Archivo | Contenido | Tamaño | Creado (encabezado del archivo) |
|---|---|---:|---|
| `bodegas_atuel_supabase_2026-11-09.dump` | **Backup completo** de la base `postgres` de Supabase | **1.434.709 bytes** | 10/11/2026 02:49:16 UTC |
| `bodegas_atuel_2026-11-09.dump` | **Backup específico** del esquema `bodegas` | **1.050.817 bytes** | 10/11/2026 02:54:15 UTC |

- **Ubicación:** `C:\Users\EQUIPO\Documents\ISI\TERCER_ANIO\BASE_DE_DATOS\`, una carpeta
  **fuera del repositorio** (el repositorio está en `...\BASE_DE_DATOS\bodegaAtuel\BD---BodegasDelAtuel\`).
  Verificado: los tamaños coinciden byte a byte.
- **No se suben a GitHub:** `.gitignore` excluye `*.dump`, `*.backup`, `*.bak` y `backups/`.

Datos leídos del encabezado de los dos archivos con `pg_restore -l` (solo lista el contenido,
no restaura nada):

| Dato | Backup completo | Backup específico |
|---|---|---|
| Formato | `CUSTOM` (archivo de `pg_dump -Fc`) | `CUSTOM` |
| Compresión | gzip | gzip |
| Base de origen | `postgres` | `postgres` |
| Versión del servidor | PostgreSQL 17.11 | PostgreSQL 17.11 |
| Versión de `pg_dump` | 17.11 (Debian 17.11-1.pgdg13+2), la de la imagen Docker `postgres:17` | Igual |
| Esquemas | `bodegas` y los de Supabase: `auth`, `extensions`, `graphql`, `graphql_public`, `pgbouncer`, `realtime`, `storage`, `vault` | Solo `bodegas` |
| Entradas del índice del archivo (TOC) | 955 | 366 |
| Bloques de datos de tablas | 74 (34 de `bodegas` + 40 de esquemas de Supabase) | 34 (todas las tablas de `bodegas`) |
| Dueño de los objetos de `bodegas` | `bodegas_owner` (359 objetos) | `bodegas_owner` (359 objetos) |

## 2. Por qué con Docker y PostgreSQL 17.11

- `pg_dump` solo puede volcar servidores de **su misma versión o anteriores**. Supabase corre
  PostgreSQL **17.11**; el entorno local del proyecto usa PostgreSQL 16 (`docker-compose.yml`),
  cuyo `pg_dump` no puede leer un servidor 17.
- La imagen oficial `postgres:17` trae `pg_dump` y `pg_restore` 17.11, sin instalar nada en la
  computadora. El encabezado de los backups lo confirma (*Dumped by pg_dump version: 17.11
  (Debian 17.11-1.pgdg13+2)*).
- Con un volumen de Docker (carpeta compartida entre la computadora y el contenedor) el
  archivo que escribe `pg_dump` dentro del contenedor queda en la carpeta de la computadora.

## 3. Backup

### 3.1 Comandos

**Los comandos exactos del backup no quedaron registrados** (no hay captura ni historial).
Lo siguiente es la forma de los comandos, reconstruida a partir del contenido verificado de
los archivos (formato custom, base `postgres`, esquema `bodegas`, `pg_dump` 17.11 de la imagen
`postgres:17`) y del procedimiento informado por el equipo (conexión con SSL y carpeta compartida
de Docker). **Pendientes de confirmación:** el host, el puerto, el usuario
y cómo se pasó la carpeta compartida (`-v`).

En PowerShell (Windows), desde cualquier carpeta. `<...>` son datos del proyecto Supabase que
**no** se escriben en la documentación:

```powershell
# Carpeta de destino (fuera del repositorio)
$destino = "C:\Users\EQUIPO\Documents\ISI\TERCER_ANIO\BASE_DE_DATOS"

# Contraseña del usuario administrador de Supabase: se pide por teclado (oculta) y no queda en el historial
$clave = Read-Host "Contraseña de Supabase" -AsSecureString
$env:PGPASSWORD = [System.Net.NetworkCredential]::new("", $clave).Password

# 1. Backup completo de la base
docker run --rm -e PGPASSWORD -v "${destino}:/backup" postgres:17 `
  pg_dump "host=<HOST_SUPABASE> port=<PUERTO> dbname=postgres user=<USUARIO_ADMIN> sslmode=require" `
  --format=custom --verbose `
  --file=/backup/bodegas_atuel_supabase_2026-11-09.dump

# 2. Backup solo del esquema bodegas
docker run --rm -e PGPASSWORD -v "${destino}:/backup" postgres:17 `
  pg_dump "host=<HOST_SUPABASE> port=<PUERTO> dbname=postgres user=<USUARIO_ADMIN> sslmode=require" `
  --format=custom --schema=bodegas --verbose `
  --file=/backup/bodegas_atuel_2026-11-09.dump

Remove-Item Env:PGPASSWORD; Remove-Variable clave
```

| Parte | Qué hace |
|---|---|
| `docker run --rm` | Crea un contenedor temporal con la imagen `postgres:17` y lo borra al terminar (el archivo queda en la carpeta compartida) |
| `-e PGPASSWORD` | Pasa al contenedor la variable `PGPASSWORD` de la sesión, sin escribir la contraseña en el comando |
| `-v "${destino}:/backup"` | Carpeta compartida: lo que se escribe en `/backup` dentro del contenedor aparece en `$destino` |
| `host=… port=… dbname=postgres user=…` | Datos de conexión a Supabase. La base de un proyecto Supabase se llama `postgres` |
| `sslmode=require` | Exige conexión cifrada: si el servidor no ofrece SSL, la conexión falla en lugar de viajar sin cifrar |
| `--format=custom` (`-Fc`) | Formato propio de PostgreSQL: comprimido y restaurable con `pg_restore`, que permite elegir qué restaurar |
| `--schema=bodegas` (`-n bodegas`) | Solo el esquema `bodegas` (y sus objetos y datos) |
| `--verbose` | Muestra el avance |
| `--file=` (`-f`) | Archivo de salida |

### 3.2 Backup completo vs. backup específico

| | Completo (`bodegas_atuel_supabase_…`) | Específico (`bodegas_atuel_…`) |
|---|---|---|
| Qué guarda | Toda la base `postgres`: el esquema `bodegas` **y** los esquemas internos de Supabase (autenticación, almacenamiento, *realtime*, *vault*, etc.) | Solo el esquema `bodegas`: tipos, dominios, tablas, datos, funciones, procedimientos, triggers, vistas, índices y permisos |
| Para qué sirve | Copia íntegra del proyecto tal como estaba en Supabase | Mover o recuperar **el sistema** en cualquier PostgreSQL 17 (otro proyecto Supabase, un servidor propio o un contenedor) |
| Restaurable en un PostgreSQL común | No directamente: sus objetos de Supabase dependen de roles y extensiones propios de Supabase (`supabase_admin`, etc.) | Sí, creando antes los tres roles del sistema (ver 4.2) |

Ninguno de los dos incluye **roles ni contraseñas**: son objetos del servidor, no de la base, y
`pg_dump` no los guarda. Por eso la restauración crea los roles antes.

## 4. Restauración de prueba

Se restauró el **backup específico** en un contenedor nuevo, con su propio volumen de datos y
en otro puerto. **No se tocó Supabase** (`pg_dump` solo lee) **ni la base local** del proyecto
(contenedor `bodegas_atuel_db`, puerto 55432).

| Dato | Valor |
|---|---|
| Contenedor | `bodegas_restore_test` |
| Imagen | `postgres:17` (PostgreSQL 17.11, verificado con `postgres --version`) |
| Puerto | `127.0.0.1:55433` → 5432 del contenedor |
| Base | `bodegas_restore_test` |
| Backup restaurado | `bodegas_atuel_2026-11-09.dump` (copiado como `/tmp/bodegas_atuel.dump`, 1.050.817 bytes) |

### 4.1 Comandos ejecutados

Tomados de las capturas C-01 a C-03 (ver [sección 7](#7-evidencias)). Se ejecutaron en el
*Símbolo del sistema* (cmd) de Windows. La contraseña del contenedor de prueba se reemplazó por
`<CONTRASEÑA_PRUEBA>`.

```bat
:: 1. Contenedor PostgreSQL 17 independiente
docker run -d --name bodegas_restore_test -p 127.0.0.1:55433:5432 ^
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=<CONTRASEÑA_PRUEBA> ^
  -e POSTGRES_DB=bodegas_restore_test postgres:17

:: 2. Esperar a que acepte conexiones
docker exec bodegas_restore_test pg_isready -U postgres -d bodegas_restore_test
::    /var/run/postgresql:5432 - accepting connections

:: 3. Crear los roles a los que el backup asigna dueños y permisos
docker exec bodegas_restore_test psql -U postgres -d bodegas_restore_test -c "CREATE ROLE bodegas_owner NOLOGIN; CREATE ROLE bodegas_api LOGIN; CREATE ROLE bodegas_reportes LOGIN;"
::    CREATE ROLE (x3)

:: 4. Copiar el backup al contenedor
docker cp "C:\Users\EQUIPO\Documents\ISI\TERCER_ANIO\BASE_DE_DATOS\bodegas_atuel_2026-11-09.dump" bodegas_restore_test:/tmp/bodegas_atuel.dump
::    Successfully copied 1.05MB to bodegas_restore_test:/tmp/bodegas_atuel.dump

:: 5. Restaurar
docker exec bodegas_restore_test pg_restore --verbose --exit-on-error -U postgres -d bodegas_restore_test /tmp/bodegas_atuel.dump

:: 6. Código de salida de pg_restore
echo %ERRORLEVEL%
::    0
```

| Paso | Por qué |
|---|---|
| `docker run -d --name … -p 127.0.0.1:55433:5432` | Servidor nuevo y aislado, accesible solo desde la propia computadora, en un puerto que no choca con la base local (55432) |
| `POSTGRES_DB=bodegas_restore_test` | La imagen crea esa base vacía al arrancar |
| `pg_isready` | Confirma que el servidor terminó de iniciar antes de usarlo |
| `CREATE ROLE …` | El backup asigna los objetos a `bodegas_owner` y da permisos a `bodegas_api` y `bodegas_reportes`, pero no crea los roles. Se crean con los mismos atributos que en `007_roles.sql` (`bodegas_owner` sin login; los otros dos con login) |
| `docker cp` | Copia el archivo de la computadora al contenedor |
| `pg_restore --verbose` | Muestra cada objeto que crea (esquema, tipos, tablas, datos, índices, permisos, vista materializada) |
| `--exit-on-error` | Se detiene ante el primer error. Por eso el **código de salida 0** significa que se restauraron **todos** los objetos sin ningún error |
| `-d bodegas_restore_test` | Base de destino |

El final del registro de `pg_restore` (captura C-03) muestra la creación de los permisos
(`ACL`), de los privilegios por defecto y de los datos de la vista materializada
`mv_ventas_mensuales_sala`, que es el último paso del backup.

### 4.2 Verificación

Consultas ejecutadas en el contenedor de prueba (capturas C-03 a C-07) y resultados:

| Verificación | Consulta (resumen) | Resultado | Qué demuestra |
|---|---|---:|---|
| Tablas | `information_schema.tables` del esquema `bodegas`, tipo `BASE TABLE` | **34** | Están todas las tablas del modelo |
| Clientes | `COUNT(*)` de `bodegas.cliente` | **20.000** | Se restauraron los datos, no solo la estructura |
| Comprobantes | `COUNT(*)` de `bodegas.comprobante` | **2.000** | Coincide con la carga hecha en Supabase |
| Localidades | `COUNT(*)` de `bodegas.localidad` | **269** | Catálogo real completo (localidades de Mendoza con código postal) |
| Vinos | `COUNT(*)` de `bodegas.vino` | **403** | Catálogo de vinos completo |
| Funciones y rutinas | `information_schema.routines` | **15** | Están todas: 13 funciones (de negocio y de triggers) y 2 procedimientos (`sp_procesar_ingreso`, `sp_procesar_transferencia`) |
| Triggers | `information_schema.triggers` | **23** | Están los **10 triggers** de `005_triggers.sql`. La vista cuenta una fila por trigger **y por evento** (INSERT, UPDATE, DELETE), por eso da 23 |
| Vistas | `information_schema.views` | **2** | `v_stock_total_vino` y `v_documentos_pendientes` |
| Vistas materializadas | `pg_matviews` | **1** | `mv_ventas_mensuales_sala` |
| CHECK | `pg_constraint`, tipo `c` | **28** | Se conservan las reglas de dominio (precio > 0, graduación entre 5 y 20, etc.) |
| FOREIGN KEY | tipo `f` | **39** | Se conserva la integridad referencial entre tablas |
| PRIMARY KEY | tipo `p` | **34** | Una por tabla |
| UNIQUE | tipo `u` | **22** | Se conservan las claves alternativas (códigos, documentos, etc.) |
| Constraint triggers | tipo `t` | **1** | `trg_vino_cepa_suma_100` (RN-05: las cepas de un vino suman 100), que se controla al confirmar la transacción |
| Registros en la vista materializada | `COUNT(*)` de `bodegas.mv_ventas_mensuales_sala` | **1.185** | La vista materializada se restauró con sus datos ya calculados |

En conjunto: estructura (tablas, restricciones), lógica (funciones, procedimientos, triggers),
objetos de consulta (vistas) y datos están completos. El backup específico es suficiente para
reconstruir el sistema.

#### Verificaciones adicionales de solo lectura (10/11/2026, al documentar)

Hechas en el mismo contenedor de prueba, sin modificarlo:

- Los 6 índices de `008_indices.sql` existen (`idx_comprobante_cliente`, `idx_detalle_vino`,
  `idx_comprobante_sala_fecha`, `idx_comprobante_fecha_cubriente`, `idx_transferencia_pendiente`,
  `idx_renglon_transf_vino`).
- `db/seed/validaciones.sql` da OK en todos los controles de integridad: sin filas huérfanas,
  sin stock negativo, stock coherente con los movimientos, totales y descuentos correctos,
  fechas coherentes y composición de cepas al 100 % (detalle en
  [`etapa8_despliegue.md`, sección 4.3](etapa8_despliegue.md#43-controles-de-integridad)).

### 4.3 Repetir la restauración

Los pasos 1 a 6 de 4.1 sirven para cualquier PostgreSQL 17. En un servidor real, además:

1. Asignar contraseñas a `bodegas_api` y `bodegas_reportes` (`\password bodegas_api` en `psql`).
2. Ejecutar `db/migrations/007_roles.sql`: el backup no guarda el `search_path` de los roles y la
   API lo necesita para encontrar las tablas.
3. Ejecutar `ANALYZE` para que el planificador tenga estadísticas.

El contenedor `bodegas_restore_test` **sigue existiendo** (no se borró). Cuando ya no haga falta
se puede eliminar con `docker rm -f bodegas_restore_test`, y su volumen de datos con
`docker volume rm <volumen>` (`docker inspect bodegas_restore_test` muestra cuál es). No se
ejecutó.

## 5. Seguridad

- Los backups **contienen todos los datos del sistema** (clientes con documentos y direcciones,
  ventas, etc.). Se guardan en una carpeta privada, **fuera del repositorio**, y **no se suben a
  GitHub** (`.gitignore` excluye `*.dump`).
- El backup completo incluye además los esquemas internos de Supabase (por ejemplo `auth`):
  tratarlo con el mismo cuidado que una credencial.
- La contraseña del administrador de Supabase no se escribe en comandos ni documentos (usar
  `PGPASSWORD` pedida por teclado, como en 3.1).
- **Las capturas C-01 y C-02 muestran en texto plano la contraseña del contenedor de prueba**
  (`POSTGRES_PASSWORD=...`). Es una contraseña de un contenedor local y desechable, pero hay que
  **taparla antes de publicar o entregar las capturas**, y no reutilizarla en ningún otro lado.

## 6. Resumen de resultados

| Prueba | Resultado |
|---|---|
| Backup completo de Supabase | Archivo de 1.434.709 bytes, formato custom, 955 entradas |
| Backup del esquema `bodegas` | Archivo de 1.050.817 bytes, formato custom, 366 entradas |
| Restauración del backup específico en PostgreSQL 17.11 | Código de salida **0** con `--exit-on-error` |
| Verificación de objetos y datos | 34 tablas, 15 rutinas, 23 filas de triggers (10 triggers), 2 vistas, 1 vista materializada, 124 restricciones; datos completos |

## 7. Evidencias

Las capturas están en `C:\Users\EQUIPO\Documents\ISI\TERCER_ANIO\BASE_DE_DATOS\cap_backup\`
(fuera del repositorio). Ubicación propuesta dentro del repositorio, **después de tapar la
contraseña de C-01 y C-02**: `docs/etapa8/capturas/`.

| N° | Archivo | Descripción | Comando o acción | Resultado demostrado |
|---|---|---|---|---|
| C-01 | `Captura de pantalla 2026-11-10 000625.png` | Creación del contenedor de prueba | `docker ps` y `docker run -d --name bodegas_restore_test … postgres:17` | Contenedor creado (id `5bee99b2…`) junto a los del proyecto, sin modificarlos |
| C-02 | `Captura de pantalla 2026-11-10 001047.png` | Preparación y comienzo de la restauración | `pg_isready`, `CREATE ROLE` (x3), `docker cp`, `pg_restore --verbose --exit-on-error` | Servidor listo, 3 roles creados, archivo copiado (1.05 MB) y restauración en curso |
| C-03 | `Captura de pantalla 2026-11-10 001238.png` | Fin de la restauración y conteo de tablas | Final de `pg_restore`, `echo %ERRORLEVEL%`, consulta de tablas | Código de salida **0** y **34** tablas |
| C-04 | `comparacion_tablas.png` | Cantidades de registros | `COUNT(*)` de cliente, comprobante, localidad y vino | 20.000 / 2.000 / 269 / 403 |
| C-05 | `comparacion_trigger_func.png` | Objetos de programación | Conteo de rutinas, triggers, vistas y vistas materializadas | 15 / 23 / 2 / 1 |
| C-06 | `comparcion_restric_integracion.png` | Restricciones de integridad | `pg_constraint` agrupado por tipo | c 28, f 39, p 34, t 1, u 22 |
| C-07 | `comparacion_vistas_materializadas.png` | Datos de la vista materializada | `COUNT(*)` de `mv_ventas_mensuales_sala` | 1.185 registros |

Faltan (pendientes de incorporar): capturas de la ejecución de los dos `pg_dump` contra Supabase
y del listado de los archivos generados con sus tamaños.

## 8. Pendientes de confirmación

1. Comandos exactos de los dos `pg_dump`: host, puerto y usuario de Supabase, modo SSL usado y
   forma de la carpeta compartida (`-v`).
2. Capturas del backup (sección 7).
