-- =====================================================================
-- db/seed/validaciones.sql  -  Etapa 3: consultas de control de la carga
-- =====================================================================
-- Solo lectura. La ejecuta carga_masiva.py al terminar; también se puede
-- correr a mano:
--   docker exec bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /db/seed/validaciones.sql'
-- Cada fila es un control: orden, descripción, valor y resultado (OK / FALLA / INFO).
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
-- Botellas que entraron y salieron (solo documentos procesados)
ingresado AS (
    SELECT r.id_vino, SUM(r.cantidad_botellas) AS q
    FROM bodegas.renglon_ingreso r JOIN bodegas.ingreso i USING (id_ingreso)
    WHERE i.estado = 'procesado' GROUP BY r.id_vino
),
transferido AS (
    SELECT t.id_sala, r.id_vino, SUM(r.cantidad_botellas) AS q, MIN(t.fecha_confeccion) AS primera
    FROM bodegas.renglon_transferencia r JOIN bodegas.transferencia t USING (id_transferencia)
    WHERE t.estado = 'procesado' GROUP BY t.id_sala, r.id_vino
),
vendido AS (
    SELECT c.id_sala, d.id_vino, SUM(d.cantidad) AS q
    FROM bodegas.detalle_comprobante d JOIN bodegas.comprobante c USING (id_comprobante)
    GROUP BY c.id_sala, d.id_vino
),
renglones AS (
    SELECT id_comprobante, SUM(subtotal_renglon) AS neto, SUM(cantidad * precio_unitario_venta) AS bruto
    FROM bodegas.detalle_comprobante GROUP BY id_comprobante
),
controles (orden, control, valor, ok) AS (
    -- 1. Volúmenes
    SELECT 100 + row_number() OVER (ORDER BY tabla), 'Filas en ' || tabla, filas, filas > 0 FROM conteos
    UNION ALL SELECT 200, 'Tablas con más de 10.000 filas (mínimo 3)',
    count(*) FILTER (WHERE filas > 10000),
    CASE
        WHEN (SELECT count(*) FROM bodegas.comprobante) < 100000 THEN NULL
        ELSE count(*) FILTER (WHERE filas > 10000) >= 3
    END
FROM conteos
UNION ALL SELECT 201, 'Tablas con más de 100.000 filas (mínimo 1)',
    count(*) FILTER (WHERE filas > 100000),
    CASE
        WHEN (SELECT count(*) FROM bodegas.comprobante) < 100000 THEN NULL
        ELSE count(*) FILTER (WHERE filas > 100000) >= 1
    END
FROM conteos

    -- 2. Filas huérfanas (las FK lo impiden; se controla igual)
    UNION ALL SELECT 300, 'Renglones de venta sin comprobante', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.comprobante c WHERE c.id_comprobante = d.id_comprobante)
    UNION ALL SELECT 301, 'Comprobantes sin renglones', count(*), count(*) = 0
    FROM bodegas.comprobante c
    WHERE NOT EXISTS (SELECT 1 FROM bodegas.detalle_comprobante d WHERE d.id_comprobante = c.id_comprobante)
    UNION ALL SELECT 302, 'Clientes sin subtipo o con un subtipo distinto de su tipo', count(*), count(*) = 0
    FROM bodegas.cliente c JOIN bodegas.tipo_cliente t USING (id_tipo_cliente)
    WHERE NOT ((t.nombre = 'Socio'        AND EXISTS (SELECT 1 FROM bodegas.socio s        WHERE s.id_cliente = c.id_cliente))
            OR (t.nombre = 'Distribuidor' AND EXISTS (SELECT 1 FROM bodegas.distribuidor d WHERE d.id_cliente = c.id_cliente))
            OR (t.nombre = 'Exportador'   AND EXISTS (SELECT 1 FROM bodegas.exportador e   WHERE e.id_cliente = c.id_cliente)))

    -- 3. Stock: nunca negativo y coherente con los movimientos
    UNION ALL SELECT 400, 'Stock negativo (salas y depósito)', count(*), count(*) = 0
    FROM (SELECT cantidad FROM bodegas.stock_sala UNION ALL SELECT cantidad FROM bodegas.stock_deposito) s
    WHERE cantidad < 0
    UNION ALL SELECT 401, 'Depósito: ingresado - transferido distinto del stock', count(*), count(*) = 0
    FROM bodegas.vino v
    LEFT JOIN ingresado i USING (id_vino)
    LEFT JOIN (SELECT id_vino, SUM(q) AS q FROM transferido GROUP BY id_vino) t USING (id_vino)
    LEFT JOIN bodegas.stock_deposito s USING (id_vino)
    WHERE COALESCE(i.q, 0) - COALESCE(t.q, 0) <> COALESCE(s.cantidad, 0)
    UNION ALL SELECT 402, 'Sala: transferido - vendido distinto del stock', count(*), count(*) = 0
    FROM transferido t
    LEFT JOIN vendido v USING (id_sala, id_vino)
    LEFT JOIN bodegas.stock_sala s USING (id_sala, id_vino)
    WHERE t.q - COALESCE(v.q, 0) <> COALESCE(s.cantidad, 0)

    -- 4. Comprobantes (RN-06, RN-08)
    UNION ALL SELECT 500, 'Comprobantes cuyo total no es la suma de sus renglones', count(*), count(*) = 0
    FROM bodegas.comprobante c JOIN renglones r USING (id_comprobante)
    WHERE c.total <> r.neto OR c.subtotal <> r.bruto OR c.descuento <> c.subtotal - c.total
    UNION ALL SELECT 501, 'Renglones con descuento distinto del de su tipo de cliente', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    JOIN bodegas.comprobante c USING (id_comprobante)
    JOIN bodegas.cliente cl USING (id_cliente)
    JOIN bodegas.tipo_cliente t USING (id_tipo_cliente)
    WHERE d.descuento_aplicado <> t.porcentaje_descuento

    -- 5. Fechas coherentes
    UNION ALL SELECT 600, 'Ventas anteriores al alta del cliente', count(*), count(*) = 0
    FROM bodegas.comprobante c JOIN bodegas.cliente cl USING (id_cliente)
    WHERE c.fecha < cl.fecha_alta
    UNION ALL SELECT 601, 'Ventas anteriores a la primera transferencia de ese vino a esa sala', count(*), count(*) = 0
    FROM bodegas.detalle_comprobante d
    JOIN bodegas.comprobante c USING (id_comprobante)
    LEFT JOIN transferido t ON t.id_sala = c.id_sala AND t.id_vino = d.id_vino
    WHERE t.primera IS NULL OR c.fecha < t.primera
    UNION ALL SELECT 602, 'Movimientos con fecha futura', count(*), count(*) = 0
    FROM (SELECT fecha FROM bodegas.comprobante UNION ALL SELECT fecha FROM bodegas.ingreso
          UNION ALL SELECT fecha_confeccion FROM bodegas.transferencia) f
    WHERE fecha > CURRENT_DATE
    UNION ALL SELECT 603, 'Vinos cuyas cepas no suman 100', count(*), count(*) = 0
    FROM (SELECT id_vino FROM bodegas.vino LEFT JOIN bodegas.vino_cepa USING (id_vino)
          GROUP BY id_vino HAVING COALESCE(SUM(porcentaje_corte), 0) <> 100) x

    -- 6. Informativos
    UNION ALL SELECT 900, 'INFO: documentos pendientes (no procesados)', count(*), NULL::boolean
    FROM (SELECT estado FROM bodegas.ingreso UNION ALL SELECT estado FROM bodegas.transferencia) x
    WHERE estado <> 'procesado'
    UNION ALL SELECT 901, 'INFO: meses distintos con ventas', count(DISTINCT date_trunc('month', fecha)), NULL
    FROM bodegas.comprobante
)
SELECT orden, control, valor,
       CASE WHEN ok IS NULL THEN 'INFO' WHEN ok THEN 'OK' ELSE 'FALLA' END AS resultado
FROM controles
ORDER BY orden;
