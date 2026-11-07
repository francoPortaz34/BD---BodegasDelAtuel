# Etapa 2 — Integridad y lógica en la base de datos

Este documento explica qué se implementó en la Etapa 2, dónde está y cómo se prueba.
Todo lo que se afirma acá se comprobó ejecutando las migraciones y `tests/db_tests.sql`
sobre PostgreSQL 16.15 (contenedor `postgres:16`).

## 1. Archivos y orden de ejecución

| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `db/migrations/001_esquema.sql` | Esquema de la Etapa 1 (tipos, dominios, tablas, PK, FK) |
| 2 | `db/migrations/002_constraints.sql` | Corrección del ENUM, acciones referenciales, UNIQUE, CHECK, DEFAULT |
| 3 | `db/migrations/003_funciones.sql` | Las 4 funciones de negocio |
| 4 | `db/migrations/004_procedimientos.sql` | Los 2 procedimientos transaccionales |
| 5 | `db/migrations/005_triggers.sql` | 10 triggers |
| 6 | `db/migrations/006_vistas.sql` | 2 vistas + 1 vista materializada |
| 7 | `db/migrations/007_roles.sql` | Roles, dueño de los objetos y privilegios |
| 8 | `tests/db_tests.sql` | Pruebas (todo en una transacción con ROLLBACK) |

`001_esquema.sql` empieza con `DROP SCHEMA IF EXISTS bodegas CASCADE`, así que la cadena
completa siempre se aplica desde cero.

## 2. Cómo ejecutar las migraciones y las pruebas

Requisito: el contenedor levantado (`docker compose up -d`, ver `docker-compose.yml`).
Las carpetas `db/` y `tests/` están montadas en el contenedor como `/db` y `/tests` (solo lectura).

**Todo de una vez, sobre una base de pruebas separada** (recomendado; no toca la base principal):

```
docker exec bodegas_atuel_db sh /tests/run_etapa2.sh
```

El script borra y recrea la base `bodegas_test`, aplica 001 a 007 y ejecuta las pruebas.
Se niega a ejecutarse sobre la base principal (`POSTGRES_DB`). Si todo está bien, la última
línea es `=== TODAS LAS PRUEBAS PASARON ===`; si una prueba falla, aparece
`ERROR: FALLO [regla]: ...` y el script termina con código distinto de 0.

**Paso a paso, a mano** (por ejemplo sobre la base principal `bodegas_atuel`, que hoy está vacía):

```
docker exec bodegas_atuel_db psql -v ON_ERROR_STOP=1 -U bodegas_admin -d bodegas_atuel -f /db/migrations/001_esquema.sql
...   (002 a 007 en orden)
docker exec bodegas_atuel_db psql -v ON_ERROR_STOP=1 -U bodegas_admin -d bodegas_atuel -f /tests/db_tests.sql
```

> En Git Bash para Windows anteponer `MSYS_NO_PATHCONV=1` a los comandos `docker exec`
> que llevan rutas (`/db/...`, `/tests/...`); si no, Git Bash las convierte en rutas de Windows.
> En PowerShell no hace falta.

**Contraseñas de los roles**: `007_roles.sql` crea `bodegas_api` y `bodegas_reportes` con LOGIN
pero sin contraseña (no se guardan secretos en Git). Para asignarlas, desde psql:

```
docker exec -it bodegas_atuel_db psql -U bodegas_admin -d bodegas_atuel
\password bodegas_api
\password bodegas_reportes
```

## 3. Restricciones (002_constraints.sql)

### 3.1 Tipos propios
- **ENUM**: `tipo_vino`, `tipo_cepa`, `estado_movimiento`, `dia_semana`, `tipo_documento` (de 001).
  Se corrigió `dia_semana`: el valor `' jueves'` (con espacio) pasa a `'jueves'` con
  `ALTER TYPE ... RENAME VALUE`.
- **DOMAIN**: `dom_cuit` (11 dígitos), `dom_dinero` (>= 0), `dom_porcentaje` (0..100),
  `dom_cantidad` (>= 0), `dom_email` (de 001).

### 3.2 Claves foráneas: acciones referenciales (39 FK, todas explícitas)
- **ON UPDATE RESTRICT en todas**: las PK son subrogadas (SERIAL) y nunca cambian.
- **ON DELETE RESTRICT (25)**: no se borra un padre con hijos. Cubre RN-14
  (transportista, bodega y vino con movimientos), catálogos (localidad, cepa, maridaje,
  tipo de cliente...) y las cabeceras de movimientos (cliente y sala de un comprobante, etc.).
  También la auditoría: un vino con historial de precios no se borra.
- **ON DELETE CASCADE (14)**: solo filas que no existen sin su cabecera:
  renglones de ingreso, transferencia y comprobante; composición y maridajes del vino;
  e-mails, teléfonos y cobertura del transportista; subtipos socio/distribuidor/exportador
  y permisos del exportador; parcela (entidad débil) de su finca; análisis de su lote.
  Aunque haya CASCADE, si el padre tiene además un movimiento con RESTRICT, el borrado se
  rechaza igual (por ejemplo, un transportista con ingresos).

### 3.3 UNIQUE adicionales (6 nuevos; 22 en total contando los de 001)
| Restricción | Tabla | Regla |
|---|---|---|
| `uq_lote_parcela_campania` | lote_de_uva (finca, parcela, campaña) | RN-04 |
| `uq_vino_nombre_anada_presentacion` | vino | mismo nombre solo con otra añada o presentación |
| `uq_cliente_documento` | cliente (tipo, número de documento) | un documento = un cliente |
| `uq_departamento_nombre_provincia` | departamento | |
| `uq_renglon_ingreso_vino` | renglon_ingreso (ingreso, vino) | un vino una vez por ingreso |
| `uq_renglon_transferencia_vino` | renglon_transferencia (transferencia, vino) | ídem |

Ya existían en 001: CUIT de bodega, transportista y empleado; códigos de vino, ingreso,
transporte, lote, permiso; número de comprobante y de solicitud; nombre de cepa, maridaje,
tipo de cliente; DNI de encargado; encargado de localidad; habilitación del distribuidor.

### 3.4 CHECK (23)
| Restricción | Qué controla | Regla |
|---|---|---|
| `ck_vino_precio_positivo` | precio_venta > 0 | RN-01 |
| `ck_vino_graduacion` | graduación entre 5 y 20 | RN-15 |
| `ck_vino_presentacion` | 187, 375, 750, 1500 o 3000 ml (Anexo B.4) | |
| `ck_vino_anada` | añada entre 1900 y 2100 | |
| `ck_finca_superficie` | superficie > 0 | RN-15 |
| `ck_parcela_superficie` | superficie > 0 | RN-15 |
| `ck_lote_kilos` | kilos > 0 | RN-15 |
| `ck_lote_campania_fecha` | **entre columnas**: campaña = año de la fecha de cosecha | RN-04 |
| `ck_permiso_fechas` | **entre columnas**: vencimiento > emisión | RN-07 |
| `ck_renglon_ingreso_cantidad` | cantidad > 0 | RN-15 |
| `ck_renglon_transferencia_cantidad` | cantidad > 0 | RN-15 |
| `ck_detalle_cantidad` | cantidad > 0 | RN-15 |
| `ck_detalle_precio` | precio unitario > 0 | RN-15 |
| `ck_comprobante_importes` | **entre columnas**: descuento <= subtotal y total = subtotal − descuento | RN-08 |
| `ck_empleado_salario` | salario > 0 | |
| `ck_analisis_ph` | pH entre 0 y 14 | |
| `ck_analisis_brix` | grado Brix entre 0 y 40 | |
| `ck_analisis_acidez` | acidez total >= 0 | |
| `ck_parcela_numero` | número de parcela > 0 | |
| `ck_parcela_anio` | año de plantación >= 1900 | |
| `ck_lote_campania` | campaña >= 1990 | |
| `ck_vino_cepa_porcentaje` | porcentaje de corte > 0 | RN-15 |
| `ck_maridaje_temperatura` | temperatura de servicio entre 0 y 25 °C | |

"El stock nunca es negativo" (RN-09) lo garantiza el dominio `dom_cantidad` (CHECK >= 0)
de `stock_sala.cantidad` y `stock_deposito.cantidad`. El rango del descuento (RN-06) lo
garantiza `dom_porcentaje` (0..100).

Ningún CHECK usa `CURRENT_DATE`: las reglas que dependen de la fecha actual van en triggers
(por ejemplo, la fecha de confección de la transferencia).

### 3.5 DEFAULT (13)
`ingreso.estado` y `transferencia.estado` = `'en_confeccion'`; `ingreso.fecha`,
`transferencia.fecha_confeccion`, `cliente.fecha_alta`, `comprobante.fecha` = `CURRENT_DATE`;
`comprobante.subtotal/descuento/total` = 0 (los calcula un trigger);
`auditoria_precio.fecha_hora` = `now()`, `auditoria_precio.usuario` = `session_user`;
`stock_sala.cantidad` y `stock_deposito.cantidad` = 0.

## 4. Funciones (003_funciones.sql)

Las cuatro son de solo lectura y **STABLE** (leen tablas o la fecha actual; dentro de una
sentencia devuelven siempre lo mismo). Ninguna es IMMUTABLE porque todas dependen de datos.

| Función | Qué devuelve | Casos límite |
|---|---|---|
| `fn_total_comprobante(id_comprobante)` | Total neto: suma de `subtotal_renglon` (cada renglón ya tiene el descuento) | 0 si no hay renglones o el comprobante no existe |
| `fn_stock_sala(id_sala, id_vino)` | Botellas del vino en la sala | 0 (no NULL) si no hay fila de stock |
| `fn_descuento_cliente(id_cliente)` | % de descuento según el tipo de cliente (lo lee de `tipo_cliente`) | Excepción si el cliente no existe |
| `fn_antiguedad_anios(fecha)` | Años completos desde la fecha hasta hoy | NULL → NULL; fecha futura → 0 |

Interpretación adoptada: `fn_antiguedad_anios` recibe una **fecha** (y no un id de empleado)
para poder usarla con empleados (U2), clientes (D4) y comprobantes (D1).

## 5. Procedimientos (004_procedimientos.sql)

Los dos siguen los mismos pasos: **bloquear la cabecera** (`SELECT ... FOR UPDATE`) →
**validar** (existe, está `terminado`, tiene renglones) → **mover el stock** → **pasar a
`procesado`**.

- **`sp_procesar_ingreso(id_ingreso)`** (RN-10): suma las botellas al depósito central.
  Si el vino no tenía fila en `stock_deposito`, la crea (`INSERT ... ON CONFLICT DO UPDATE`).
- **`sp_procesar_transferencia(id_transferencia)`** (RN-11, RN-09): bloquea las filas de
  `stock_deposito` de los vinos pedidos (en orden de `id_vino`, para evitar deadlocks),
  controla que alcance **para todos los renglones** (con `LEFT JOIN`, así detecta también el
  vino que no tiene fila en el depósito), descuenta del depósito, suma a la sala y cambia el
  estado.

**Por qué son transaccionales**: un `CALL` es una sola sentencia; si cualquier paso falla,
PostgreSQL revierte todo lo que hizo el procedimiento. No hacen `COMMIT` adentro, así la API
los puede usar dentro de una transacción más grande. La prueba RN-11 verifica que, con un
renglón que alcanza y otro que no, **no cambia ningún stock**.

**Operaciones duplicadas**: si dos sesiones procesan el mismo documento, la segunda espera en
el `FOR UPDATE`; cuando entra ve `procesado` y se rechaza. La prueba RN-10 verifica que un
segundo `CALL` no duplica el stock.

**SECURITY DEFINER**: se ejecutan con los permisos del dueño (`bodegas_owner`), porque la API
no puede escribir `stock_deposito` ni `stock_sala`. Llevan `SET search_path = bodegas, pg_temp`
para que nadie pueda "reemplazar" una tabla con otra de su propio esquema.

Uso: `CALL sp_procesar_ingreso(15);` — `CALL sp_procesar_transferencia(42);`

## 6. Triggers (005_triggers.sql)

| Trigger | Tabla | Momento | Responsabilidad | Regla |
|---|---|---|---|---|
| `trg_vino_auditoria_precio` | vino | AFTER UPDATE OF precio_venta | Inserta precio anterior, nuevo, fecha/hora y usuario en `auditoria_precio` (solo si el precio cambió) | RN-13 |
| `trg_transferencia_fecha` | transferencia | BEFORE INSERT/UPDATE | INSERT: pone `CURRENT_DATE`. UPDATE: prohíbe cambiar la fecha | RN-11 |
| `trg_ingreso_estado` / `trg_transferencia_estado` | ingreso / transferencia | BEFORE INSERT/UPDATE OF estado | Un documento nace `en_confeccion`; solo `en_confeccion → terminado → procesado`; a `procesado` solo se llega por el procedimiento | RN-10, RN-11 |
| `trg_renglon_ingreso_bloqueo` / `trg_renglon_transferencia_bloqueo` | renglones | BEFORE INSERT/UPDATE/DELETE | Si la cabecera no está `en_confeccion`, no se agregan, modifican ni quitan renglones | RN-12 |
| `trg_vino_cepa_suma_100` | vino_cepa | CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED | Al cerrar la transacción, la composición de cada vino suma 100 | RN-05 |
| `trg_detalle_validar` | detalle_comprobante | BEFORE INSERT/UPDATE | Completa precio (el del vino), descuento (`fn_descuento_cliente`) y subtotal; bloquea la fila de stock con `FOR UPDATE` y rechaza si no alcanza | RN-09, RN-06, RN-01 |
| `trg_detalle_actualizar` | detalle_comprobante | AFTER INSERT/UPDATE/DELETE | Descuenta (o devuelve) el stock de la sala y recalcula los importes del comprobante | RN-09, RN-08 |
| `trg_comprobante_totales` | comprobante | BEFORE INSERT/UPDATE | Pisa subtotal, descuento y total con los calculados; impide cambiar sala o cliente si ya hay renglones | RN-08 |

Detalles para la defensa:
- **Por qué el control de estados mira el dueño de la tabla**: los procedimientos son SECURITY
  DEFINER, así que mientras corren, `current_user` es el dueño de la tabla (`bodegas_owner`).
  Un `UPDATE ... SET estado = 'procesado'` hecho directamente por la API (o por un superusuario)
  tiene otro `current_user` y se rechaza: no se puede marcar un documento como procesado sin
  mover el stock. El dueño de las tablas sí podría hacerlo, pero también podría deshabilitar
  los triggers: se lo considera de confianza.
- **Renglones de venta**: en un UPDATE solo tiene efecto el cambio de cantidad; el precio queda
  congelado (es el del momento de la venta) y el descuento se recalcula según el tipo de
  cliente. Para cambiar el vino se borra el renglón y se carga otro.
- **Borrar un renglón de venta** devuelve las botellas a la sala (se anuló parte de la venta).
  **Borrar el comprobante completo** (depuración de historial, consulta D1) borra los renglones
  por CASCADE pero **no** devuelve stock: el trigger detecta que la cabecera ya no existe.
  Lo mismo para RN-12: borrar un ingreso procesado completo (consulta D5) no queda bloqueado.
- **SECURITY DEFINER** en `trg_auditar_precio`, `trg_validar_renglon_venta` y
  `trg_actualizar_stock_y_totales`: escriben (o bloquean con FOR UPDATE) tablas en las que la
  API solo puede leer. Por eso la auditoría guarda `session_user` (el usuario que se conectó)
  y no `current_user` (que dentro del trigger es el dueño).
- **Concurrencia**: ver `docs/etapa2_concurrencia.md`.

## 7. Vistas (006_vistas.sql)

| Vista | Tipo | Qué devuelve |
|---|---|---|
| `v_stock_total_vino` | normal | Por vino: stock del depósito, suma de las salas y total. LEFT JOIN: los vinos sin stock aparecen con 0. Las salas se suman antes del join para no duplicar filas |
| `mv_ventas_mensuales_sala` | **materializada** | Por sala y mes: cantidad de comprobantes y monto total vendido |
| `v_documentos_pendientes` | normal | Ingresos y transferencias que no están `procesado` (UNION ALL; `id_sala` es NULL en los ingresos) |

La vista materializada guarda el resultado y **no se actualiza sola**. Para refrescarla
(con el dueño o un superusuario), por ejemplo después de la carga masiva:

```sql
REFRESH MATERIALIZED VIEW bodegas.mv_ventas_mensuales_sala;
```

## 8. Roles y permisos (007_roles.sql)

| Rol | LOGIN | Permisos |
|---|---|---|
| `bodegas_owner` | No (se usa con `SET ROLE`) | Dueño del esquema y de **todos** los objetos (tablas, vistas, funciones, tipos) |
| `bodegas_api` | Sí | SELECT en todo; INSERT/UPDATE/DELETE en las tablas de negocio **excepto** `stock_sala`, `stock_deposito` y `auditoria_precio` (solo lectura); USAGE en secuencias; EXECUTE en las 4 funciones y los 2 procedimientos |
| `bodegas_reportes` | Sí | Solo SELECT en tablas y vistas; EXECUTE en las 4 funciones de consulta |

- A `PUBLIC` se le quitan todos los privilegios sobre el esquema, tablas, secuencias y funciones.
- Las migraciones las corre el superusuario, que queda como dueño de todo. `007` cambia el dueño
  de cada objeto a `bodegas_owner` (recorre el catálogo). Es necesario porque los objetos
  SECURITY DEFINER se ejecutan con los permisos de su dueño: no debe ser un superusuario.
- El script se puede ejecutar de nuevo: crea los roles solo si no existen.
- `ALTER DEFAULT PRIVILEGES FOR ROLE bodegas_owner`: las tablas que cree `bodegas_owner` más
  adelante reciben los mismos permisos, y las funciones nuevas no quedan ejecutables por PUBLIC.
  Para que esto aplique, las próximas migraciones (por ejemplo `008_indices.sql`) deben
  ejecutarse después de `SET ROLE bodegas_owner;`.
- Los tres roles tienen `search_path = bodegas`.
- La API **no** puede escribir el stock ni la auditoría de forma directa: solo a través de los
  procedimientos y de los triggers de venta (probado en la sección "ROL api" de las pruebas).

## 9. Tabla de trazabilidad

Las pruebas están en `tests/db_tests.sql`, en la sección con el mismo nombre de la regla.
Cada línea de salida empieza con `OK [RN-xx]`.

| Regla de negocio | Mecanismo implementado | Archivo | Prueba |
|---|---|---|---|
| RN-01 Precio único y > 0 | Atributo `vino.precio_venta` + `ck_vino_precio_positivo`; el trigger de venta toma siempre ese precio | 001, 002, 005 | Precio 0 y negativo rechazados; mismo precio en dos salas; ventas anteriores conservan su precio |
| RN-02 Sala en una localidad; un encargado por localidad | `fk_sala_localidad` NOT NULL, `fk_localidad_encargado`, `uq_localidad_encargado` | 001, 002 | Sala sin localidad (23502), con localidad inexistente (23503), encargado repetido (23505) |
| RN-03 Empleado en una sola sala | `fk_empleado_sala` NOT NULL | 001, 002 | Empleado sin sala (23502) y con sala inexistente (23503); alta válida |
| RN-04 Una cepa por parcela; una cosecha por campaña | `fk_parcela_cepa`, `uq_lote_parcela_campania`, `ck_lote_campania_fecha` | 001, 002 | Segunda cosecha en la misma campaña (23505); otra campaña OK; cepa inexistente; campaña ≠ año |
| RN-05 Corte suma 100 | `trg_vino_cepa_suma_100` (constraint trigger diferido) | 005 | 60 % rechazado; 60 + 40 OK; quitar una cepa rechazado |
| RN-06 Descuento por tipo de cliente | `fn_descuento_cliente` + `dom_porcentaje` + trigger de venta | 003, 005 | 10/20/30 %; cliente inexistente; descuento 120 rechazado; descuento aplicado al renglón |
| RN-07 Permisos; vencimiento > emisión | Tabla `permiso_exportacion` + `ck_permiso_fechas` | 001, 002 | Dos permisos OK; vencimiento = emisión (23514); permiso a un no exportador (23503) |
| RN-08 Total = suma de renglones; no se carga a mano | `fn_total_comprobante` + `trg_detalle_validar`, `trg_detalle_actualizar`, `trg_comprobante_totales` + `ck_comprobante_importes` | 002, 003, 005 | Importes manuales ignorados; totales al agregar, modificar y quitar renglones; cambio de sala bloqueado; CHECK sin trigger |
| RN-09 No vender más que el stock; stock >= 0 | `trg_detalle_validar` (BEFORE, FOR UPDATE) + `trg_detalle_actualizar` (AFTER) + `dom_cantidad` | 001, 005 | Vender 8 con 7 rechazado; vender las 7 OK; stock 0 rechazado; vino sin stock; UPDATE de cantidad; stock negativo directo (23514); demostración de concurrencia |
| RN-10 Estados del ingreso | ENUM `estado_movimiento` + `trg_ingreso_estado` + `sp_procesar_ingreso` | 001, 004, 005 | Alta en procesado; salto y retroceso de estados; procesar sin procedimiento; procesar en confección, dos veces, inexistente, sin renglones |
| RN-11 Estados de la transferencia; fecha actual inmutable | `trg_transferencia_estado`, `trg_transferencia_fecha` + `sp_procesar_transferencia` | 004, 005 | Fecha forzada a hoy; cambio de fecha rechazado; stock insuficiente sin cambios a medias; vino sin fila en depósito; procesar sin procedimiento |
| RN-12 Renglones bloqueados fuera de confección | `trg_renglon_ingreso_bloqueo`, `trg_renglon_transferencia_bloqueo` | 005 | INSERT/UPDATE/DELETE en documentos terminados o procesados rechazados; mover un renglón a un documento cerrado; en confección OK; borrado completo de un ingreso procesado |
| RN-13 Auditoría de precios | `trg_vino_auditoria_precio` (AFTER UPDATE) + `auditoria_precio` + permisos (la API solo puede leerla) | 001, 005, 007 | Cambio auditado con valores y usuario; sin auditoría si no cambia el precio; la API no puede borrar la auditoría (42501); cambio hecho por la API auditado |
| RN-14 No borrar con movimientos | FK con ON DELETE RESTRICT | 002 | Borrar transportista, bodega y vino con movimientos (23503); transportista sin movimientos se borra |
| RN-15 Valores positivos; graduación 5–20 | CHECK `ck_vino_graduacion`, `ck_lote_kilos`, `ck_*_superficie`, `ck_*_cantidad` | 002 | Graduación 4,99 y 20,01; kilos 0; superficies 0 y −1; cantidades 0 y negativas |

Además se prueban: los UNIQUE nuevos, otros CHECK, el dominio de CUIT, los DEFAULT, la
corrección del ENUM, los casos límite de las funciones, las tres vistas (incluido el REFRESH
de la materializada) y los permisos de los tres roles (con `SET ROLE`).

## 10. Dónde va cada regla (criterio usado)

| Tipo de regla | Herramienta | Ejemplos en este trabajo |
|---|---|---|
| Valor válido de una fila | CHECK, DOMAIN, NOT NULL | precio > 0, graduación, vencimiento > emisión |
| Dato relacionado existente | FOREIGN KEY | renglón → vino, empleado → sala |
| Unicidad | UNIQUE / PK | una cosecha por parcela y campaña |
| Depende de otras filas, tablas o de la fecha actual | Trigger | stock suficiente, estados, fecha de confección, suma 100 |
| Cálculo usado en varios lugares | Función | total del comprobante, stock de sala, descuento |
| Operación de varios pasos todo o nada | Procedimiento | procesar ingreso / transferencia |
| Quién puede hacer qué | Roles y privilegios | la API no escribe stock ni auditoría |

## 11. Limitaciones conocidas y observaciones

- **Tipo de cliente y subtipos**: el modelo de la Etapa 1 guarda el tipo en
  `cliente.id_tipo_cliente` y además tiene las tablas `socio`, `distribuidor` y `exportador`.
  Nada impide hoy que un cliente de tipo "Socio" tenga fila en `exportador`. El descuento se
  toma siempre de `tipo_cliente` (fuente única). Si se quiere cerrar ese hueco, la opción
  más simple es un trigger en las tablas de subtipo que compare con `id_tipo_cliente`.
- **Consulta U6** (subir al 35 % el descuento de ciertos exportadores): con el modelo actual
  el descuento es por tipo de cliente, no por cliente. Habrá que resolverlo en la Etapa 5
  (por ejemplo, con un tipo de cliente adicional). Los CHECK de esta etapa no lo impiden
  (el rango permitido es 0..100).
- **Carga masiva (Etapa 3)**: los triggers fuerzan que los documentos nazcan en
  `en_confeccion`, que la fecha de transferencia sea la actual y que el precio de venta sea el
  vigente. Para cargar historial habrá que deshabilitarlos temporalmente
  (`ALTER TABLE ... DISABLE TRIGGER`), como sugiere la consigna, y validar después con
  consultas de control.
- Un documento ya `terminado` o `procesado` puede cambiar otras columnas de su cabecera
  (por ejemplo, el transportista). Las reglas de la consigna no lo exigen; no se agregó.
