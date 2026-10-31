-- Escenario 1 (CON bloqueo) - SESIÓN B
-- Se lanza mientras A tiene la transacción abierta. El INSERT queda
-- ESPERANDO en el SELECT ... FOR UPDATE del trigger hasta que A termina;
-- entonces lee el stock real (0) y la venta se rechaza (RN-09).
SET search_path TO bodegas;
\echo [B] BEGIN
BEGIN;
SELECT clock_timestamp()::time(0) AS b_hora, 'B intenta vender la misma botella' AS paso;
INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
VALUES (800002, 800001, 1, 0, 0, 0);
ROLLBACK;
SELECT clock_timestamp()::time(0) AS b_hora, 'B terminó (después de esperar a A)' AS paso;
