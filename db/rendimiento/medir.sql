SET search_path TO bodegas;

-- S3: clientes de cada tipo que compraron en una sala en la última semana
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.nombre, COUNT(DISTINCT c.id_cliente) AS clientes
FROM comprobante c
JOIN cliente cl      USING (id_cliente)
JOIN tipo_cliente t  USING (id_tipo_cliente)
WHERE c.id_sala = 3                          -- sala: cambiar acá
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY t.nombre;

-- S4: top 5 salas que más pidieron un vino por transferencias (últimos 15 días)
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.id_sala, SUM(r.cantidad_botellas) AS botellas
FROM renglon_transferencia r
JOIN transferencia t USING (id_transferencia)
WHERE r.id_vino = 10                         -- vino: cambiar acá
  AND t.fecha_confeccion >= CURRENT_DATE - 15
GROUP BY t.id_sala
ORDER BY botellas DESC
LIMIT 5;

-- S8: monto total de ventas por sala en el último trimestre
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_sala, SUM(total) AS monto
FROM comprobante
WHERE fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY id_sala
ORDER BY monto DESC;

-- S12: clientes que compraron TODOS los vinos de una bodega (división con NOT EXISTS)
EXPLAIN (ANALYZE, BUFFERS)
SELECT cl.id_cliente
FROM cliente cl
WHERE NOT EXISTS (
    SELECT 1 FROM vino v
    WHERE v.id_bodega = 5                    -- bodega: cambiar acá
      AND NOT EXISTS (
          SELECT 1
          FROM comprobante c
          JOIN detalle_comprobante d USING (id_comprobante)
          WHERE c.id_cliente = cl.id_cliente
            AND d.id_vino = v.id_vino));