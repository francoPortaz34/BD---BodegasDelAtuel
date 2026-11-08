-- =====================================================================
-- consultas/select.sql  -  Etapa 5: consultas (SELECT)
-- =====================================================================
-- Cómo ejecutarlo (desde la raíz del repo):
--   docker exec -i bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < consultas/select.sql
--
-- Las consignas con "la última semana", "el último mes", etc. se calculan
-- desde la fecha actual (CURRENT_DATE), como pide la consigna.
-- Los parámetros (una sala, un vino) están marcados con "<- parámetro".
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas
--     en toda la red de salas.
-- Estrategia: JOIN de los renglones de venta con el vino, GROUP BY por
-- vino y SUM de las cantidades. ORDER BY descendente y LIMIT 10.
-- ---------------------------------------------------------------------
\echo '=== S1: top 10 vinos más vendidos'
SELECT v.cod_vino, v.nombre_comercial, v.anada, v.presentacion_ml,
       SUM(d.cantidad) AS botellas_vendidas
FROM detalle_comprobante d
JOIN vino v ON v.id_vino = d.id_vino
GROUP BY v.id_vino, v.cod_vino, v.nombre_comercial, v.anada, v.presentacion_ml
ORDER BY botellas_vendidas DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- S2. Códigos y nombres de los vinos que se vendieron en TODAS las salas
--     (división relacional).
-- Estrategia: doble NOT EXISTS. Se buscan los vinos para los que
-- "no existe ninguna sala en la que no se hayan vendido".
--   * El NOT EXISTS de adentro: ¿hay alguna venta de este vino en esta sala?
--   * El NOT EXISTS de afuera: ¿hay alguna sala donde eso no pase?
-- Alternativa equivalente: GROUP BY por vino y
--   HAVING COUNT(DISTINCT c.id_sala) = (SELECT COUNT(*) FROM sala_de_ventas).
-- ---------------------------------------------------------------------
\echo '=== S2: vinos vendidos en todas las salas'
SELECT v.cod_vino, v.nombre_comercial
FROM vino v
WHERE NOT EXISTS (
    SELECT 1
    FROM sala_de_ventas s
    WHERE NOT EXISTS (
        SELECT 1
        FROM comprobante c
        JOIN detalle_comprobante d ON d.id_comprobante = c.id_comprobante
        WHERE c.id_sala = s.id_sala
          AND d.id_vino = v.id_vino
    )
)
ORDER BY v.cod_vino;


-- ---------------------------------------------------------------------
-- S3. Cantidad de clientes de cada tipo que compraron en una sala
--     determinada en la última semana.
-- Estrategia: JOIN comprobante -> cliente -> tipo_cliente, filtro por sala
-- y por fecha, GROUP BY por tipo. COUNT(DISTINCT ...) porque un mismo
-- cliente pudo comprar varias veces en la semana y se cuenta una sola vez.
-- ---------------------------------------------------------------------
\echo '=== S3: clientes por tipo que compraron en la sala 1 en la última semana'
SELECT t.nombre AS tipo_cliente,
       COUNT(DISTINCT c.id_cliente) AS clientes
FROM comprobante c
JOIN cliente cl     ON cl.id_cliente = c.id_cliente
JOIN tipo_cliente t ON t.id_tipo_cliente = cl.id_tipo_cliente
WHERE c.id_sala = 1                              -- <- parámetro: sala
  AND c.fecha >= CURRENT_DATE - 7
GROUP BY t.nombre
ORDER BY clientes DESC;


-- ---------------------------------------------------------------------
-- S4. Top 5 de las salas que solicitaron mayor cantidad de un vino
--     determinado mediante transferencias en los últimos 15 días.
-- Estrategia: JOIN renglón -> transferencia -> sala -> localidad, filtro
-- por vino y fecha de confección, SUM de botellas por sala, ORDER BY
-- descendente y LIMIT 5. Se cuentan todas las transferencias (procesadas
-- o no), porque la consigna pregunta por lo que se solicitó.
-- ---------------------------------------------------------------------
\echo '=== S4: top 5 salas que más pidieron el vino 72 en los últimos 15 días'
SELECT t.id_sala, l.nombre AS localidad,
       SUM(r.cantidad_botellas) AS botellas_pedidas
FROM renglon_transferencia r
JOIN transferencia t  ON t.id_transferencia = r.id_transferencia
JOIN sala_de_ventas s ON s.id_sala = t.id_sala
JOIN localidad l      ON l.id_localidad = s.id_localidad
WHERE r.id_vino = 72                             -- <- parámetro: vino
  AND t.fecha_confeccion >= CURRENT_DATE - 15
GROUP BY t.id_sala, l.nombre
ORDER BY botellas_pedidas DESC
LIMIT 5;


-- ---------------------------------------------------------------------
-- S5. Listado de las salas con menor cantidad de transferencias
--     pendientes (no procesadas).
-- Estrategia: LEFT JOIN de sala con transferencia, para que también
-- aparezcan las salas con 0 pendientes. La condición del estado va en el
-- ON y no en el WHERE: si fuera en el WHERE, las salas sin pendientes se
-- descartarían y el LEFT JOIN funcionaría como un INNER JOIN.
-- COUNT(t.id_transferencia) no cuenta los NULL, así que da 0 para esas salas.
-- ---------------------------------------------------------------------
\echo '=== S5: salas ordenadas de menor a mayor cantidad de transferencias pendientes'
SELECT s.id_sala, l.nombre AS localidad,
       COUNT(t.id_transferencia) AS pendientes
FROM sala_de_ventas s
JOIN localidad l          ON l.id_localidad = s.id_localidad
LEFT JOIN transferencia t ON t.id_sala = s.id_sala
                         AND t.estado <> 'procesado'
GROUP BY s.id_sala, l.nombre
ORDER BY pendientes, s.id_sala;


-- ---------------------------------------------------------------------
-- S6. Para una sala determinada, los vinos sin stock en la sala pero con
--     stock en el depósito central.
-- Estrategia: se parte del depósito (vinos con stock > 0) y con NOT EXISTS
-- se descartan los que la sala sí tiene. Un vino "sin stock en la sala"
-- puede no tener fila en stock_sala o tenerla con cantidad 0: el NOT EXISTS
-- con "cantidad > 0" cubre los dos casos.
-- ---------------------------------------------------------------------
\echo '=== S6: vinos sin stock en la sala 1 pero con stock en el depósito'
SELECT v.cod_vino, v.nombre_comercial, d.cantidad AS stock_deposito
FROM stock_deposito d
JOIN vino v ON v.id_vino = d.id_vino
WHERE d.cantidad > 0
  AND NOT EXISTS (
      SELECT 1
      FROM stock_sala ss
      WHERE ss.id_sala = 1                       -- <- parámetro: sala
        AND ss.id_vino = d.id_vino
        AND ss.cantidad > 0
  )
ORDER BY v.nombre_comercial;


-- ---------------------------------------------------------------------
-- S7. ¿Cuál es la empresa de transporte con mayor actividad en el último mes?
-- Estrategia: la actividad de un transportista son los ingresos que
-- trasladó. GROUP BY por transportista y COUNT de ingresos del último mes.
-- En vez de ORDER BY ... LIMIT 1 se usa HAVING con una subconsulta que
-- calcula el máximo: así, si hay empate, aparecen todos los empatados.
-- ---------------------------------------------------------------------
\echo '=== S7: transportista(s) con más ingresos en el último mes'
SELECT tr.cod_transporte, tr.razon_social, COUNT(i.id_ingreso) AS ingresos
FROM transportista tr
JOIN ingreso i ON i.id_transportista = tr.id_transportista
WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
GROUP BY tr.id_transportista, tr.cod_transporte, tr.razon_social
HAVING COUNT(i.id_ingreso) = (
    SELECT MAX(cantidad)
    FROM (SELECT COUNT(*) AS cantidad
          FROM ingreso
          WHERE fecha >= CURRENT_DATE - INTERVAL '1 month'
          GROUP BY id_transportista) AS por_transportista
);


-- ---------------------------------------------------------------------
-- S8. Monto total de ventas por sala en el último trimestre, en orden
--     descendente.
-- Estrategia: JOIN comprobante -> sala -> localidad, filtro por fecha
-- (últimos 3 meses), SUM del total por sala y ORDER BY descendente.
-- Se suma comprobante.total, que ya tiene el descuento aplicado (lo
-- calculan los triggers de la etapa 2).
-- ---------------------------------------------------------------------
\echo '=== S8: monto vendido por sala en el último trimestre'
SELECT s.id_sala, l.nombre AS localidad, SUM(c.total) AS monto_total
FROM comprobante c
JOIN sala_de_ventas s ON s.id_sala = c.id_sala
JOIN localidad l      ON l.id_localidad = s.id_localidad
WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY s.id_sala, l.nombre
ORDER BY monto_total DESC;


-- =====================================================================
-- Consultas avanzadas (S9 a S12)
-- =====================================================================

-- ---------------------------------------------------------------------
-- S9. Ficha de un vino: cepas con sus porcentajes, bodega elaboradora,
--     maridajes y stock total (depósito más salas).
-- Estrategia: JOIN del vino con su bodega y con la vista v_stock_total_vino
-- (etapa 2), que ya suma el stock del depósito y de las salas.
-- Las cepas y los maridajes se arman con subconsultas escalares en el
-- SELECT, cada una con string_agg (junta varios textos en uno, como SUM
-- pero para texto). Si se hiciera JOIN con cepas y con maridajes a la vez,
-- las filas se multiplicarían (2 cepas x 2 maridajes = 4 filas) y los
-- nombres saldrían repetidos.
-- ---------------------------------------------------------------------
\echo '=== S9: ficha del vino V0001'
SELECT v.cod_vino, v.nombre_comercial, v.tipo, v.anada, v.presentacion_ml,
       v.precio_venta, b.razon_social AS bodega,
       (SELECT string_agg(c.nombre || ' ' || vc.porcentaje_corte || '%', ', '
                          ORDER BY vc.porcentaje_corte DESC)
        FROM vino_cepa vc
        JOIN cepa c ON c.id_cepa = vc.id_cepa
        WHERE vc.id_vino = v.id_vino) AS cepas,
       (SELECT string_agg(m.nombre || ' (' || m.temperatura_sugerida || ' °C)', ', ')
        FROM vino_maridaje vm
        JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
        WHERE vm.id_vino = v.id_vino) AS maridajes,
       st.stock_deposito, st.stock_salas, st.stock_total
FROM vino v
JOIN bodega b              ON b.id_bodega = v.id_bodega
JOIN v_stock_total_vino st ON st.id_vino = v.id_vino
WHERE v.cod_vino = 'V0001';                      -- <- parámetro: vino


-- ---------------------------------------------------------------------
-- S10. Rendimiento en kg por hectárea de cada parcela y campaña, e
--      identificar las parcelas que rinden menos que el promedio de su finca.
-- Estrategia: una CTE (WITH) calcula el rendimiento de cada lote
-- (kilos / superficie de la parcela). Una CTE es una consulta con nombre
-- que se usa como si fuera una tabla en la consulta que sigue.
--   * S10a lista el rendimiento.
--   * S10b usa una subconsulta correlacionada: para cada fila calcula el
--     promedio de SU finca en esa misma campaña y se queda con las que
--     están por debajo. Se compara dentro de la misma campaña para no
--     mezclar años buenos con años malos.
-- ---------------------------------------------------------------------
\echo '=== S10a: rendimiento (kg/ha) de cada parcela y campaña (primeras 15 filas)'
WITH rendimiento AS (
    SELECT l.id_finca, l.num_parcela, l.campania,
           l.kilos_cosechados / p.superficie AS kg_por_ha
    FROM lote_de_uva l
    JOIN parcela p ON p.id_finca = l.id_finca
                  AND p.num_parcela = l.num_parcela
)
SELECT f.nombre AS finca, r.num_parcela, r.campania, ROUND(r.kg_por_ha) AS kg_por_ha
FROM rendimiento r
JOIN finca f ON f.id_finca = r.id_finca
ORDER BY f.nombre, r.num_parcela, r.campania
LIMIT 15;                                        -- sacar el LIMIT para ver todas

\echo '=== S10b: parcelas que rinden menos que el promedio de su finca en la campaña (primeras 15)'
WITH rendimiento AS (
    SELECT l.id_finca, l.num_parcela, l.campania,
           l.kilos_cosechados / p.superficie AS kg_por_ha
    FROM lote_de_uva l
    JOIN parcela p ON p.id_finca = l.id_finca
                  AND p.num_parcela = l.num_parcela
)
SELECT f.nombre AS finca, r.num_parcela, r.campania,
       ROUND(r.kg_por_ha) AS kg_por_ha,
       ROUND((SELECT AVG(r2.kg_por_ha)
              FROM rendimiento r2
              WHERE r2.id_finca = r.id_finca
                AND r2.campania = r.campania)) AS promedio_finca
FROM rendimiento r
JOIN finca f ON f.id_finca = r.id_finca
WHERE r.kg_por_ha < (SELECT AVG(r2.kg_por_ha)
                     FROM rendimiento r2
                     WHERE r2.id_finca = r.id_finca      -- correlacionada: usa la fila de afuera
                       AND r2.campania = r.campania)
ORDER BY f.nombre, r.campania, r.num_parcela
LIMIT 15;                                        -- sacar el LIMIT para ver todas


-- ---------------------------------------------------------------------
-- S11. Ranking de vinos dentro de cada sala por botellas vendidas, y
--      ventas acumuladas mensuales por sala.
-- Estrategia: funciones de ventana (OVER). Calculan algo sobre un grupo
-- de filas (la "ventana") pero, a diferencia de GROUP BY, no juntan las
-- filas: cada fila conserva su lugar y recibe el valor calculado.
--   * PARTITION BY id_sala: la ventana es cada sala por separado.
--   * S11a: RANK() numera los vinos de cada sala según las botellas.
--     El ranking no se puede filtrar en el WHERE (se calcula después), por
--     eso se calcula en una subconsulta y se filtra afuera (top 3 por sala).
--   * S11b: SUM(...) OVER (... ORDER BY mes) va sumando mes a mes: es el
--     acumulado de cada sala desde su primera venta.
-- ---------------------------------------------------------------------
\echo '=== S11a: top 3 de vinos por botellas vendidas en cada sala (salas 1 a 3)'
SELECT id_sala, puesto, cod_vino, nombre_comercial, botellas
FROM (
    SELECT c.id_sala, v.cod_vino, v.nombre_comercial,
           SUM(d.cantidad) AS botellas,
           RANK() OVER (PARTITION BY c.id_sala ORDER BY SUM(d.cantidad) DESC) AS puesto
    FROM comprobante c
    JOIN detalle_comprobante d ON d.id_comprobante = c.id_comprobante
    JOIN vino v                ON v.id_vino = d.id_vino
    GROUP BY c.id_sala, v.id_vino, v.cod_vino, v.nombre_comercial
) AS ranking
WHERE puesto <= 3
  AND id_sala <= 3                               -- sacar esta línea para ver todas las salas
ORDER BY id_sala, puesto;

\echo '=== S11b: ventas mensuales y acumuladas de la sala 1 (últimos 12 meses)'
SELECT id_sala, mes, monto_mes, acumulado
FROM (
    SELECT c.id_sala,
           to_char(c.fecha, 'YYYY-MM') AS mes,
           SUM(c.total) AS monto_mes,
           SUM(SUM(c.total)) OVER (PARTITION BY c.id_sala
                                   ORDER BY to_char(c.fecha, 'YYYY-MM')) AS acumulado
    FROM comprobante c
    GROUP BY c.id_sala, to_char(c.fecha, 'YYYY-MM')
) AS mensual
WHERE id_sala = 1                                -- <- parámetro: sala (sacar para ver todas)
  AND mes >= to_char(CURRENT_DATE - INTERVAL '11 months', 'YYYY-MM')
ORDER BY id_sala, mes;


-- ---------------------------------------------------------------------
-- S12. Clientes que compraron todos los vinos de una bodega determinada,
--      y clientes que nunca compraron ningún vino tinto.
-- Estrategia:
--   * S12a: división relacional con doble NOT EXISTS, igual que S2:
--     clientes para los que "no existe un vino de la bodega que no hayan
--     comprado".
--   * S12b: anti-join con NOT EXISTS: clientes para los que no existe
--     ninguna compra de un vino tinto. Incluye a los que nunca compraron nada.
-- ---------------------------------------------------------------------
\echo '=== S12a: clientes que compraron todos los vinos de la bodega 21 (primeros 10)'
SELECT cl.id_cliente, cl.nombre_o_razon_social
FROM cliente cl
WHERE NOT EXISTS (
    SELECT 1
    FROM vino v
    WHERE v.id_bodega = 21                       -- <- parámetro: bodega
      AND NOT EXISTS (
          SELECT 1
          FROM comprobante c
          JOIN detalle_comprobante d ON d.id_comprobante = c.id_comprobante
          WHERE c.id_cliente = cl.id_cliente
            AND d.id_vino = v.id_vino
      )
)
ORDER BY cl.id_cliente
LIMIT 10;                                        -- sacar el LIMIT para verlos todos

\echo '=== S12b: clientes que nunca compraron un vino tinto (primeros 10)'
SELECT cl.id_cliente, cl.nombre_o_razon_social
FROM cliente cl
WHERE NOT EXISTS (
    SELECT 1
    FROM comprobante c
    JOIN detalle_comprobante d ON d.id_comprobante = c.id_comprobante
    JOIN vino v                ON v.id_vino = d.id_vino
    WHERE c.id_cliente = cl.id_cliente
      AND v.tipo = 'tinto'
)
ORDER BY cl.id_cliente
LIMIT 10;                                        -- sacar el LIMIT para verlos todos
