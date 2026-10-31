# Etapa 2 — Demostración de concurrencia: la última botella

Dos sesiones de PostgreSQL intentan vender al mismo tiempo la **única** botella de un vino
que tiene una sala. Se muestra qué pasa **con** bloqueo (como funciona el sistema) y **sin**
bloqueo (una aplicación que lee y escribe el stock por su cuenta).

Nivel de aislamiento: **READ COMMITTED** (el que usa PostgreSQL por defecto; no se cambió).
En READ COMMITTED cada sentencia ve los datos confirmados al momento de empezar. Por eso dos
sesiones pueden leer el mismo stock "viejo" si no se bloquea la fila.

## Archivos

| Archivo | Para qué |
|---|---|
| `tests/concurrencia/00_preparar.sql` | Crea (con COMMIT) la sala 800001 con 1 botella del vino 800001 y dos comprobantes vacíos (800001 cliente A, 800002 cliente B) |
| `tests/concurrencia/con_bloqueo_sesion_a.sql` / `_b.sql` | Escenario 1: venta normal (los triggers bloquean) |
| `tests/concurrencia/sin_bloqueo_sesion_a.sql` / `_b.sql` | Escenario 2: lógica ingenua sin bloqueo |
| `tests/concurrencia/run_demo.sh` | Corre los dos escenarios con dos conexiones `psql` simultáneas |

Se usa la base de pruebas `bodegas_test`. Para dejarla limpia, volver a correr
`run_etapa2.sh`, que la recrea desde cero.

## Ejecución automática (dos conexiones reales en paralelo)

```
docker exec bodegas_atuel_db sh /tests/run_etapa2.sh
docker exec bodegas_atuel_db sh /tests/concurrencia/run_demo.sh
```

`run_demo.sh` lanza la sesión A en segundo plano y la sesión B un segundo después; son dos
procesos `psql` distintos, con conexiones independientes. Cada script deja una pausa
(`pg_sleep`) para que las transacciones se superpongan.

## Ejecución manual (para las capturas del informe)

Abrir **dos terminales** y en cada una:

```
docker exec -it bodegas_atuel_db psql -U bodegas_admin -d bodegas_test
SET search_path TO bodegas;
```

Antes, una sola vez: `\i /tests/concurrencia/00_preparar.sql` en cualquiera de las dos.

### Escenario 1 — CON bloqueo (el sistema real)

El trigger `trg_detalle_validar` hace `SELECT ... FROM stock_sala ... FOR UPDATE` antes de
controlar el stock.

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon) VALUES (800001, 800001, 1, 0, 0, 0);` → OK, el trigger bloqueó la fila de stock y la dejó en 0 | |
| 3 | | `INSERT INTO detalle_comprobante (...) VALUES (800002, 800001, 1, 0, 0, 0);` → **queda esperando** (la fila está bloqueada por A) |
| 4 | `COMMIT;` | |
| 5 | | Recién ahora continúa, lee el stock real (0) y falla: `Stock insuficiente del vino 800001 en la sala 800001: disponible 0, solicitado 1 (RN-09)`. `ROLLBACK;` |

### Escenario 2 — SIN bloqueo (lógica ingenua de una aplicación)

Primero, como superusuario, volver a poner 1 botella:
`UPDATE stock_sala SET cantidad = 1 WHERE id_sala = 800001 AND id_vino = 800001;`

La "aplicación" lee el stock, decide que alcanza y escribe el valor calculado por ella (1 − 1 = 0).
Escribe `stock_sala` directamente: esto lo puede hacer un superusuario, **no** el rol de la API.

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `SELECT cantidad FROM stock_sala WHERE id_sala = 800001 AND id_vino = 800001;` → 1 | |
| 3 | | La misma consulta → **1** (A todavía no confirmó) |
| 4 | `UPDATE stock_sala SET cantidad = 0 WHERE ...;` `COMMIT;` | |
| 5 | | `UPDATE stock_sala SET cantidad = 0 WHERE ...;` `COMMIT;` → **OK** |

Las dos sesiones vendieron la misma botella y el stock quedó en 0: es una
**actualización perdida**. Ningún CHECK la detecta porque el valor final (0) es válido.

Variante: si la aplicación escribe `SET cantidad = cantidad - 1` (sin FOR UPDATE), el UPDATE de
B espera a que A confirme, se vuelve a evaluar con el valor nuevo (0 − 1 = −1) y el CHECK del
dominio `dom_cantidad` lo rechaza. El stock no queda negativo, pero B se entera del problema
recién al final, después de haber "vendido".

## Resultado obtenido (ejecución del 31/10/2026, PostgreSQL 16.15)

Escenario 1 (salida de `run_demo.sh`, resumida):

```
[A] 16:30:44  A inserta el renglón (el trigger bloquea la fila de stock)
[A]           A ve stock = 0
[B] 16:30:45  B intenta vender la misma botella          <- queda esperando
[A] 16:30:49  A hace COMMIT
[B] ERROR:  Stock insuficiente del vino 800001 en la sala 800001: disponible 0, solicitado 1 (RN-09)
[B] 16:30:49  B terminó (después de esperar a A)

stock_final = 0
CONC-A: 1 renglón, total 9000.00      CONC-B: 0 renglones, total 0.00
```

B empezó a las 16:30:45 y recién obtuvo respuesta a las 16:30:49, en el mismo segundo del
COMMIT de A: estuvo bloqueada esperando.

Escenario 2:

```
[A] 16:30:49  A lee el stock (sin FOR UPDATE) -> 1
[B] 16:30:50  B lee el stock (sin FOR UPDATE) -> 1
[A] 16:30:52  A escribió stock = 0 y hace COMMIT
[B] 16:30:54  B escribió stock = 0 y hace COMMIT
stock_final = 0   -> las dos sesiones vendieron la única botella
```

Variante `cantidad - 1` sin FOR UPDATE: B obtuvo
`ERROR: value for domain bodegas.dom_cantidad violates check constraint "dom_cantidad_check"`
y el stock final quedó en 0.

## Conclusión

- El sistema **no** depende de que la aplicación haga las cosas bien: la venta pasa por el
  trigger, que bloquea la fila de stock con `FOR UPDATE` antes de leerla. La segunda sesión
  espera y después ve el stock real, así que se rechaza con un mensaje claro.
- Además, el rol de la API no tiene permiso para escribir `stock_sala`, así que no puede
  implementar la lógica ingenua del escenario 2 aunque quisiera.
- El CHECK `cantidad >= 0` es una segunda barrera: evita el stock negativo, pero no evita la
  actualización perdida. Por eso hace falta el bloqueo.
- Comportamiento documentado por PostgreSQL (no ejecutado en esta demostración): con
  `REPEATABLE READ`, en la variante B recibiría un error de serialización (SQLSTATE 40001) en
  lugar de reevaluar, y la aplicación tendría que reintentar. No se usó porque
  READ COMMITTED + FOR UPDATE alcanza y es más simple.
