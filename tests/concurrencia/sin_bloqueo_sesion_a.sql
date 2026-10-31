-- Escenario 2 (SIN bloqueo, lógica "ingenua" de una aplicación) - SESIÓN A
-- La aplicación lee el stock, decide si alcanza y escribe el valor que
-- calculó ella misma (leído - 1). No usa FOR UPDATE ni los triggers de
-- venta: escribe stock_sala directamente (sólo lo puede hacer un
-- superusuario o el propietario; la API no tiene ese permiso).
SET search_path TO bodegas;
\echo [A] BEGIN
BEGIN;
SELECT clock_timestamp()::time(0) AS a_hora, 'A lee el stock (sin FOR UPDATE)' AS paso, cantidad
FROM stock_sala WHERE id_sala = 800001 AND id_vino = 800001;
SELECT pg_sleep(3);   -- "la aplicación procesa la venta"
UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 800001 AND id_vino = 800001;  -- 1 - 1 calculado por la app
SELECT clock_timestamp()::time(0) AS a_hora, 'A escribió stock = 0 y hace COMMIT' AS paso;
COMMIT;
