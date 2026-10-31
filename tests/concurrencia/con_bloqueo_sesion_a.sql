-- Escenario 1 (CON bloqueo) - SESIÓN A
-- Vende la última botella y mantiene la transacción abierta 5 segundos
-- antes del COMMIT, para que la sesión B intente vender al mismo tiempo.
SET search_path TO bodegas;
\echo [A] BEGIN
BEGIN;
SELECT now()::time(0) AS a_hora, 'A inserta el renglón (el trigger bloquea la fila de stock)' AS paso;
INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
VALUES (800001, 800001, 1, 0, 0, 0);
SELECT 'A ve stock' AS paso, cantidad FROM stock_sala WHERE id_sala = 800001 AND id_vino = 800001;
SELECT pg_sleep(5);
SELECT clock_timestamp()::time(0) AS a_hora, 'A hace COMMIT' AS paso;
COMMIT;
