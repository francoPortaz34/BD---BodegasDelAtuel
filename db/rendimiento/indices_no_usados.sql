-- =====================================================================
-- indices_no_usados.sql  -  Etapa 4, pasos 6 y 8
-- Casos en que el planificador NO usa un índice, y el índice descartado.
-- Ejecutar DESPUÉS de 008_indices.sql.
-- =====================================================================
SET search_path TO bodegas;

-- Caso 1 (paso 8): S5 con el índice parcial idx_transferencia_pendiente.
-- La tabla transferencia es chica: leerla entera es más barato que usar
-- el índice, así que el plan muestra Seq Scan aunque el índice exista.
\echo '--- Caso 1: S5 (índice parcial existente, tabla chica)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.id_sala, COUNT(t.id_transferencia) AS pendientes
FROM sala_de_ventas s
LEFT JOIN transferencia t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
GROUP BY s.id_sala
ORDER BY pendientes;

-- Caso 2 (paso 8): S1 con idx_detalle_vino.
-- La consulta suma TODOS los renglones: si hay que leer la tabla completa,
-- el índice no ayuda y el plan hace Seq Scan.
\echo '--- Caso 2: S1 (hay que leer toda la tabla)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.cod_vino, v.nombre_comercial, SUM(d.cantidad) AS botellas
FROM detalle_comprobante d
JOIN vino v USING (id_vino)
GROUP BY v.id_vino, v.cod_vino, v.nombre_comercial
ORDER BY botellas DESC
LIMIT 10;

-- Índice descartado (paso 6): cliente(id_tipo_cliente).
-- Se crea dentro de una transacción y se deshace con ROLLBACK, así no queda.
-- La columna tiene solo 3 valores (baja selectividad): el planificador
-- prefiere leer la tabla entera y el índice solo sumaría costo de escritura.
\echo '--- Índice descartado: cliente(id_tipo_cliente)'
BEGIN;
CREATE INDEX idx_descartado_cliente_tipo ON cliente (id_tipo_cliente);
ANALYZE cliente;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM cliente WHERE id_tipo_cliente = 1;
ROLLBACK;
