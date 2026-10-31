-- Escenario 2 (SIN bloqueo) - SESIÓN B
-- En READ COMMITTED, B lee el stock antes de que A confirme: ve 1
-- botella, cree que hay stock y también "vende". Al final las DOS
-- sesiones vendieron la misma botella y el stock quedó en 0 (y no en -1):
-- es una ACTUALIZACIÓN PERDIDA. Ningún CHECK la detecta, porque el valor
-- final (0) es válido.
SET search_path TO bodegas;
\echo [B] BEGIN
BEGIN;
SELECT clock_timestamp()::time(0) AS b_hora, 'B lee el stock (sin FOR UPDATE)' AS paso, cantidad
FROM stock_sala WHERE id_sala = 800001 AND id_vino = 800001;
SELECT pg_sleep(4);
UPDATE stock_sala SET cantidad = 0 WHERE id_sala = 800001 AND id_vino = 800001;  -- 1 - 1 calculado por la app
SELECT clock_timestamp()::time(0) AS b_hora, 'B escribió stock = 0 y hace COMMIT' AS paso;
COMMIT;
