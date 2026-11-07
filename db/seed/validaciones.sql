-- =====================================================================
-- db/seed/validaciones.sql  -  Etapa 3: consultas de control de la carga
-- =====================================================================
-- SÓLO LECTURA: es una única sentencia SELECT. No modifica nada.
-- La ejecuta carga_masiva.py al terminar (y con --verificar). También se
-- puede correr a mano:
--   docker exec bodegas_atuel_db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /db/seed/validaciones.sql
--
-- Cada fila es un control: orden, descripción, valor y resultado
-- (OK / FALLA / INFO). Los controles de inconsistencia esperan valor 0.
--
-- [*] = el control supone una base RECIÉN CARGADA: que el stock sólo
-- cambió por ingresos, transferencias y ventas. Con actividad posterior
-- (por ejemplo, documentos en confección de la API, o comprobantes
-- borrados con CASCADE, que no devuelven stock) puede dar FALLA sin que
-- la carga esté mal.
--
-- Cronología (opción A, docs/etapa3_carga_masiva.md §3.2): los controles
-- 900-906 exigen que ninguna venta sea anterior a la transferencia que
-- abasteció su (sala, vino), ni a la primera transferencia procesada, y
-- que no haya fechas futuras.
-- =====================================================================
WITH
conteos (tabla, filas) AS (
              SELECT 'encargado',              count(*) FROM bodegas.encargado
    UNION ALL SELECT 'departamento',           count(*) FROM bodegas.departamento
    UNION ALL SELECT 'cepa',                   count(*) FROM bodegas.cepa
    UNION ALL SELECT 'maridaje',               count(*) FROM bodegas.maridaje
    UNION ALL SELECT 'tipo_cliente',           count(*) FROM bodegas.tipo_cliente
    UNION ALL SELECT 'localidad',              count(*) FROM bodegas.localidad
    UNION ALL SELECT 'bodega',                 count(*) FROM bodegas.bodega
    UNION ALL SELECT 'transportista',          count(*) FROM bodegas.transportista
    UNION ALL SELECT 'transportista_email',    count(*) FROM bodegas.transportista_email
    UNION ALL SELECT 'transportista_telefono', count(*) FROM bodegas.transportista_telefono
    UNION ALL SELECT 'transportista_localidad',count(*) FROM bodegas.transportista_localidad
    UNION ALL SELECT 'sala_de_ventas',         count(*) FROM bodegas.sala_de_ventas
    UNION ALL SELECT 'empleado',               count(*) FROM bodegas.empleado
    UNION ALL SELECT 'finca',                  count(*) FROM bodegas.finca
    UNION ALL SELECT 'parcela',                count(*) FROM bodegas.parcela
    UNION ALL SELECT 'lote_de_uva',            count(*) FROM bodegas.lote_de_uva
    UNION ALL SELECT 'analisis_calidad',       count(*) FROM bodegas.analisis_calidad
    UNION ALL SELECT 'vino',                   count(*) FROM bodegas.vino
    UNION ALL SELECT 'vino_cepa',              count(*) FROM bodegas.vino_cepa
    UNION ALL SELECT 'vino_maridaje',          count(*) FROM bodegas.vino_maridaje
    UNION ALL SELECT 'cliente',                count(*) FROM bodegas.cliente
    UNION ALL SELECT 'socio',                  count(*) FROM bodegas.socio
    UNION ALL SELECT 'distribuidor',           count(*) FROM bodegas.distribuidor
    UNION ALL SELECT 'exportador',             count(*) FROM bodegas.exportador
    UNION ALL SELECT 'permiso_exportacion',    count(*) FROM bodegas.permiso_exportacion
    UNION ALL SELECT 'ingreso',                count(*) FROM bodegas.ingreso
    UNION ALL SELECT 'renglon_ingreso',        count(*) FROM bodegas.renglon_ingreso
    UNION ALL SELECT 'stock_deposito',         count(*) FROM bodegas.stock_deposito
    UNION ALL SELECT 'transferencia',          count(*) FROM bodegas.transferencia
    UNION ALL SELECT 'renglon_transferencia',  count(*) FROM bodegas.renglon_transferencia
    UNION ALL SELECT 'stock_sala',             count(*) FROM bodegas.stock_sala
    UNION ALL SELECT 'comprobante',            count(*) FROM bodegas.comprobante
    UNION ALL SELECT 'detalle_comprobante',    count(*) FROM bodegas.detalle_comprobante
    UNION ALL SELECT 'auditoria_precio',       count(*) FROM bodegas.auditoria_precio
),
totales_renglones AS (
    SELECT id_comprobante,
           SUM(subtotal_renglon)                AS neto,
           SUM(cantidad * precio_unitario_venta) AS bruto
    FROM bodegas.detalle_comprobante
    GROUP BY id_comprobante
),
ingresado AS (
    SELECT ri.id_vino, SUM(ri.cantidad_botellas) AS q
    FROM bodegas.renglon_ingreso ri
    JOIN bodegas.ingreso i ON i.id_ingreso = ri.id_ingreso
    WHERE i.estado = 'procesado'
    GROUP BY ri.id_vino
),
transferido AS (
    SELECT t.id_sala, rt.id_vino, SUM(rt.cantidad_botellas) AS q
    FROM bodegas.renglon_transferencia rt
    JOIN bodegas.transferencia t ON t.id_transferencia = rt.id_transferencia
    WHERE t.estado = 'procesado'
    GROUP BY t.id_sala, rt.id_vino
),
vendido AS (
    SELECT c.id_sala, d.id_vino, SUM(d.cantidad) AS q
    FROM bodegas.detalle_comprobante d
    JOIN bodegas.comprobante c ON c.id_comprobante = d.id_comprobante
    GROUP BY c.id_sala, d.id_vino
),
pares_sala AS (
    SELECT id_sala, id_vino FROM transferido
    UNION SELECT id_sala, id_vino FROM vendido
    UNION SELECT id_sala, id_vino FROM bodegas.stock_sala
),
primera_transferencia AS (
    SELECT t.id_sala, rt.id_vino, MIN(t.fecha_confeccion) AS primera
    FROM bodegas.renglon_transferencia rt
    JOIN bodegas.transferencia t ON t.id_transferencia = rt.id_transferencia
    WHERE t.estado = 'procesado'
    GROUP BY t.id_sala, rt.id_vino
),
-- Saldo acumulado por día: entradas y salidas de cada fecha, en orden de fecha.
-- Granularidad diaria: dentro de un mismo día se toma primero lo que entra
-- (en la carga, las transferencias se procesan antes que las ventas).
movimientos_sala AS (
    SELECT t.id_sala, rt.id_vino, t.fecha_confeccion AS fecha, rt.cantidad_botellas::bigint AS entra, 0::bigint AS sale
    FROM bodegas.renglon_transferencia rt
    JOIN bodegas.transferencia t ON t.id_transferencia = rt.id_transferencia
    WHERE t.estado = 'procesado'
    UNION ALL
    SELECT c.id_sala, d.id_vino, c.fecha, 0::bigint, d.cantidad::bigint
    FROM bodegas.detalle_comprobante d
    JOIN bodegas.comprobante c ON c.id_comprobante = d.id_comprobante
),
saldo_sala_diario AS (
    SELECT id_sala, id_vino, fecha,
           SUM(SUM(entra) - SUM(sale)) OVER (PARTITION BY id_sala, id_vino ORDER BY fecha) AS saldo
    FROM movimientos_sala
    GROUP BY id_sala, id_vino, fecha
),
movimientos_deposito AS (
    SELECT ri.id_vino, i.fecha, ri.cantidad_botellas::bigint AS entra, 0::bigint AS sale
    FROM bodegas.renglon_ingreso ri
    JOIN bodegas.ingreso i ON i.id_ingreso = ri.id_ingreso
    WHERE i.estado = 'procesado'
    UNION ALL
    SELECT rt.id_vino, t.fecha_confeccion, 0::bigint, rt.cantidad_botellas::bigint
    FROM bodegas.renglon_transferencia rt
    JOIN bodegas.transferencia t ON t.id_transferencia = rt.id_transferencia
    WHERE t.estado = 'procesado'
),
saldo_deposito_diario AS (
    SELECT id_vino, fecha,
           SUM(SUM(entra) - SUM(sale)) OVER (PARTITION BY id_vino ORDER BY fecha) AS saldo
    FROM movimientos_deposito
    GROUP BY id_vino, fecha
),
controles (orden, control, valor, ok) AS (
    -- 1. Volúmenes ------------------------------------------------------
    SELECT 100 + row_number() OVER (ORDER BY tabla), 'Filas en ' || tabla, filas, filas > 0
    FROM conteos
    UNION ALL
    SELECT 200, 'Tablas con más de 10.000 filas (mínimo 3)',
           count(*) FILTER (WHERE filas > 10000), count(*) FILTER (WHERE filas > 10000) >= 3
    FROM conteos
    UNION ALL
    SELECT 201, 'Tablas con más de 100.000 filas (mínimo 1)',
           count(*) FILTER (WHERE filas > 100000), count(*) FILTER (WHERE filas > 100000) >= 1
    FROM conteos

    -- 2. Filas huérfanas (las FK lo impiden; se controla igual) ---------
    UNION ALL
    SELECT 300, 'Huérfanas: renglones de comprobante sin comprobante', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.comprobante c WHERE c.id_comprobante = d.id_comprobante)
    UNION ALL
    SELECT 301, 'Huérfanas: renglones de comprobante sin vino', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.vino v WHERE v.id_vino = d.id_vino)
    UNION ALL
    SELECT 302, 'Huérfanas: comprobantes sin cliente o sin sala', count(*), count(*) = 0
    FROM bodegas.comprobante c
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.cliente cl WHERE cl.id_cliente = c.id_cliente)
       OR NOT EXISTS (SELECT 1 FROM bodegas.sala_de_ventas s WHERE s.id_sala = c.id_sala)
    UNION ALL
    SELECT 303, 'Huérfanas: renglones de ingreso sin ingreso', count(*), count(*) = 0
    FROM bodegas.renglon_ingreso r
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.ingreso i WHERE i.id_ingreso = r.id_ingreso)
    UNION ALL
    SELECT 304, 'Huérfanas: renglones de transferencia sin transferencia', count(*), count(*) = 0
    FROM bodegas.renglon_transferencia r
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.transferencia t WHERE t.id_transferencia = r.id_transferencia)
    UNION ALL
    SELECT 305, 'Huérfanas: stock de sala sin sala o sin vino', count(*), count(*) = 0
    FROM bodegas.stock_sala ss
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.sala_de_ventas s WHERE s.id_sala = ss.id_sala)
       OR NOT EXISTS (SELECT 1 FROM bodegas.vino v WHERE v.id_vino = ss.id_vino)
    UNION ALL
    SELECT 306, 'Huérfanas: localidades sin encargado', count(*), count(*) = 0
    FROM bodegas.localidad l
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.encargado e WHERE e.id_encargado = l.id_encargado)
    UNION ALL
    SELECT 307, 'Encargados sin localidad', count(*), count(*) = 0
    FROM bodegas.encargado e
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.localidad l WHERE l.id_encargado = e.id_encargado)

    -- 3. Stock --------------------------------------------------------------
    UNION ALL
    SELECT 400, 'Stock de sala negativo', count(*), count(*) = 0
    FROM bodegas.stock_sala WHERE cantidad < 0
    UNION ALL
    SELECT 401, 'Stock de depósito negativo', count(*), count(*) = 0
    FROM bodegas.stock_deposito WHERE cantidad < 0
    UNION ALL
    SELECT 402, 'Depósito: ingresado - transferido distinto del stock [*]', count(*), count(*) = 0
    FROM bodegas.vino v
    LEFT JOIN ingresado i ON i.id_vino = v.id_vino
    LEFT JOIN (SELECT id_vino, SUM(q) AS q FROM transferido GROUP BY id_vino) t ON t.id_vino = v.id_vino
    LEFT JOIN bodegas.stock_deposito sd ON sd.id_vino = v.id_vino
    WHERE COALESCE(i.q, 0) - COALESCE(t.q, 0) <> COALESCE(sd.cantidad, 0)
    UNION ALL
    SELECT 403, 'Sala: transferido - vendido distinto del stock [*]', count(*), count(*) = 0
    FROM pares_sala p
    LEFT JOIN transferido t ON t.id_sala = p.id_sala AND t.id_vino = p.id_vino
    LEFT JOIN vendido vd    ON vd.id_sala = p.id_sala AND vd.id_vino = p.id_vino
    LEFT JOIN bodegas.stock_sala ss ON ss.id_sala = p.id_sala AND ss.id_vino = p.id_vino
    WHERE COALESCE(t.q, 0) - COALESCE(vd.q, 0) <> COALESCE(ss.cantidad, 0)
    UNION ALL
    SELECT 404, 'Ingresos o transferencias sin procesar [*]', count(*), count(*) = 0
    FROM (SELECT estado FROM bodegas.ingreso UNION ALL SELECT estado FROM bodegas.transferencia) x
    WHERE estado <> 'procesado'
    UNION ALL
    SELECT 405, 'Renglones de ingreso con vino de otra bodega', count(*), count(*) = 0
    FROM bodegas.renglon_ingreso r
    JOIN bodegas.ingreso i ON i.id_ingreso = r.id_ingreso
    JOIN bodegas.vino v    ON v.id_vino = r.id_vino
    WHERE v.id_bodega <> i.id_bodega

    -- 4. Comprobantes (RN-01, RN-06, RN-08) ---------------------------------
    UNION ALL
    SELECT 500, 'Comprobantes cuyo total no coincide con la suma de sus renglones', count(*), count(*) = 0
    FROM bodegas.comprobante c
    LEFT JOIN totales_renglones t ON t.id_comprobante = c.id_comprobante
    WHERE c.total <> COALESCE(t.neto, 0)
    UNION ALL
    SELECT 501, 'Comprobantes con subtotal o descuento incoherentes', count(*), count(*) = 0
    FROM bodegas.comprobante c
    LEFT JOIN totales_renglones t ON t.id_comprobante = c.id_comprobante
    WHERE c.subtotal <> COALESCE(t.bruto, 0) OR c.descuento <> c.subtotal - c.total
    UNION ALL
    SELECT 502, 'Comprobantes sin renglones', count(*), count(*) = 0
    FROM bodegas.comprobante c
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.detalle_comprobante d WHERE d.id_comprobante = c.id_comprobante)
    UNION ALL
    SELECT 503, 'Renglones con descuento distinto del tipo de cliente', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    JOIN bodegas.comprobante c   ON c.id_comprobante = d.id_comprobante
    JOIN bodegas.cliente cl      ON cl.id_cliente = c.id_cliente
    JOIN bodegas.tipo_cliente tc ON tc.id_tipo_cliente = cl.id_tipo_cliente
    WHERE d.descuento_aplicado <> tc.porcentaje_descuento
    UNION ALL
    SELECT 504, 'Renglones con subtotal mal calculado', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    WHERE d.subtotal_renglon <> ROUND(d.cantidad * d.precio_unitario_venta * (1 - d.descuento_aplicado / 100), 2)
    UNION ALL
    SELECT 505, 'Renglones con precio que no es el vigente ni uno anterior auditado', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    JOIN bodegas.vino v ON v.id_vino = d.id_vino
    WHERE d.precio_unitario_venta <> v.precio_venta
      AND NOT EXISTS (SELECT 1 FROM bodegas.auditoria_precio a
                      WHERE a.id_vino = d.id_vino AND a.precio_anterior = d.precio_unitario_venta)
    UNION ALL
    SELECT 506, 'Ventas anteriores al alta del cliente', count(*), count(*) = 0
    FROM bodegas.comprobante c
    JOIN bodegas.cliente cl ON cl.id_cliente = c.id_cliente
    WHERE c.fecha < cl.fecha_alta
    UNION ALL
    SELECT 507, 'Ventas en el día de cierre de la sala', count(*), count(*) = 0
    FROM bodegas.comprobante c
    JOIN bodegas.sala_de_ventas s ON s.id_sala = c.id_sala
    WHERE array_position(enum_range(NULL::bodegas.dia_semana), s.dia_cierre_semanal) = EXTRACT(ISODOW FROM c.fecha)
    UNION ALL
    SELECT 508, 'Vinos vendidos antes de su primer ingreso (o sin ingreso)', count(*), count(*) = 0
    FROM (SELECT d.id_vino, MIN(c.fecha) AS primera_venta
          FROM bodegas.detalle_comprobante d
          JOIN bodegas.comprobante c ON c.id_comprobante = d.id_comprobante
          GROUP BY d.id_vino) pv
    LEFT JOIN (SELECT r.id_vino, MIN(i.fecha) AS primer_ingreso
               FROM bodegas.renglon_ingreso r
               JOIN bodegas.ingreso i ON i.id_ingreso = r.id_ingreso
               GROUP BY r.id_vino) pin ON pin.id_vino = pv.id_vino
    WHERE pin.primer_ingreso IS NULL OR pin.primer_ingreso > pv.primera_venta

    -- 5. Vinos, clientes y producción ---------------------------------------
    UNION ALL
    SELECT 600, 'Vinos cuyos porcentajes de corte no suman 100 (o sin cepas)', count(*), count(*) = 0
    FROM (SELECT v.id_vino
          FROM bodegas.vino v
          LEFT JOIN bodegas.vino_cepa vc ON vc.id_vino = v.id_vino
          GROUP BY v.id_vino
          HAVING COALESCE(SUM(vc.porcentaje_corte), 0) <> 100) x
    UNION ALL
    SELECT 601, 'Vinos sin maridaje', count(*), count(*) = 0
    FROM bodegas.vino v
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.vino_maridaje vm WHERE vm.id_vino = v.id_vino)
    UNION ALL
    SELECT 602, 'Clientes sin subtipo, con más de uno o distinto de su tipo', count(*), count(*) = 0
    FROM bodegas.cliente c
    JOIN bodegas.tipo_cliente tc ON tc.id_tipo_cliente = c.id_tipo_cliente
    WHERE (EXISTS (SELECT 1 FROM bodegas.socio s WHERE s.id_cliente = c.id_cliente))::int
        + (EXISTS (SELECT 1 FROM bodegas.distribuidor d WHERE d.id_cliente = c.id_cliente))::int
        + (EXISTS (SELECT 1 FROM bodegas.exportador e WHERE e.id_cliente = c.id_cliente))::int <> 1
       OR (tc.nombre = 'Socio'        AND NOT EXISTS (SELECT 1 FROM bodegas.socio s        WHERE s.id_cliente = c.id_cliente))
       OR (tc.nombre = 'Distribuidor' AND NOT EXISTS (SELECT 1 FROM bodegas.distribuidor d WHERE d.id_cliente = c.id_cliente))
       OR (tc.nombre = 'Exportador'   AND NOT EXISTS (SELECT 1 FROM bodegas.exportador e   WHERE e.id_cliente = c.id_cliente))
    UNION ALL
    SELECT 603, 'Permisos de exportación emitidos antes del alta del cliente', count(*), count(*) = 0
    FROM bodegas.permiso_exportacion p
    JOIN bodegas.cliente c ON c.id_cliente = p.id_cliente
    WHERE p.fecha_emision < c.fecha_alta
    UNION ALL
    SELECT 604, 'Salas sin empleados', count(*), count(*) = 0
    FROM bodegas.sala_de_ventas s
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.empleado e WHERE e.id_sala = s.id_sala)
    UNION ALL
    SELECT 605, 'Análisis de calidad anteriores a la cosecha del lote', count(*), count(*) = 0
    FROM bodegas.analisis_calidad a
    JOIN bodegas.lote_de_uva l ON l.id_lote_uva = a.id_lote_uva
    WHERE a.fecha < l.fecha_cosecha
    UNION ALL
    SELECT 606, 'Vinos auditados cuyo precio actual no es el último precio auditado', count(*), count(*) = 0
    FROM bodegas.vino v
    JOIN LATERAL (SELECT a.precio_nuevo
                  FROM bodegas.auditoria_precio a
                  WHERE a.id_vino = v.id_vino
                  ORDER BY a.fecha_hora DESC, a.id_auditoria DESC
                  LIMIT 1) ult ON TRUE
    WHERE ult.precio_nuevo <> v.precio_venta

    -- 6. Cronología de los movimientos (RN-11: fecha_confeccion = CURRENT_DATE)
    UNION ALL
    SELECT 900, 'Comprobantes anteriores a la primera transferencia procesada', count(*), count(*) = 0
    FROM bodegas.comprobante
    WHERE fecha < (SELECT MIN(fecha_confeccion) FROM bodegas.transferencia WHERE estado = 'procesado')
    UNION ALL
    SELECT 901, 'Renglones vendidos antes de la 1ra transferencia de su (sala, vino) o sin ella',
           count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    JOIN bodegas.comprobante c ON c.id_comprobante = d.id_comprobante
    LEFT JOIN primera_transferencia pt ON pt.id_sala = c.id_sala AND pt.id_vino = d.id_vino
    WHERE pt.primera IS NULL OR c.fecha < pt.primera
    UNION ALL
    SELECT 902, 'Sala: días en que lo vendido acumulado supera lo transferido (sala, vino) [*]',
           count(*), count(*) = 0
    FROM saldo_sala_diario
    WHERE saldo < 0
    UNION ALL
    SELECT 903, 'Depósito: días en que lo transferido acumulado supera lo ingresado (vino) [*]',
           count(*), count(*) = 0
    FROM saldo_deposito_diario
    WHERE saldo < 0
    UNION ALL
    SELECT 904, 'Comprobantes con fecha futura', count(*), count(*) = 0
    FROM bodegas.comprobante WHERE fecha > CURRENT_DATE
    UNION ALL
    SELECT 905, 'Transferencias con fecha de confección futura', count(*), count(*) = 0
    FROM bodegas.transferencia WHERE fecha_confeccion > CURRENT_DATE
    UNION ALL
    SELECT 906, 'Ingresos con fecha futura', count(*), count(*) = 0
    FROM bodegas.ingreso WHERE fecha > CURRENT_DATE

    -- 7. Informativos ---------------------------------------------------------
    UNION ALL
    SELECT 990, 'INFO: fechas distintas de confección de transferencias', count(DISTINCT fecha_confeccion),
           NULL::boolean
    FROM bodegas.transferencia
    UNION ALL
    SELECT 991, 'INFO: fechas distintas de comprobantes', count(DISTINCT fecha), NULL::boolean
    FROM bodegas.comprobante
)
SELECT orden,
       control,
       valor,
       CASE WHEN ok IS NULL THEN 'INFO' WHEN ok THEN 'OK' ELSE 'FALLA' END AS resultado
FROM controles
ORDER BY orden;
