-- 006_vistas.sql
SET search_path TO bodegas;

-- Stock total por vino: depósito central + suma de todas las salas
CREATE OR REPLACE VIEW v_stock_total_vino AS
SELECT v.id_vino,
       v.cod_vino,
       v.nombre_comercial,
       v.anada,
       v.presentacion_ml,
       COALESCE(sd.cantidad, 0)                               AS stock_deposito,
       COALESCE(ss.stock_salas, 0)                            AS stock_salas,
       COALESCE(sd.cantidad, 0) + COALESCE(ss.stock_salas, 0) AS stock_total
FROM vino v
LEFT JOIN stock_deposito sd ON sd.id_vino = v.id_vino
LEFT JOIN (SELECT id_vino, SUM(cantidad) AS stock_salas
           FROM stock_sala
           GROUP BY id_vino) ss ON ss.id_vino = v.id_vino;


-- Ventas mensuales por sala (MATERIALIZADA)
CREATE MATERIALIZED VIEW mv_ventas_mensuales_sala AS
SELECT s.id_sala,
       l.nombre                           AS localidad,
       date_trunc('month', c.fecha)::date AS mes,
       COUNT(*)                           AS cantidad_comprobantes,
       SUM(c.total)                       AS monto_total
FROM comprobante c
JOIN sala_de_ventas s ON s.id_sala = c.id_sala
JOIN localidad l      ON l.id_localidad = s.id_localidad
GROUP BY s.id_sala, l.nombre, date_trunc('month', c.fecha);


-- Documentos pendientes: ingresos y transferencias no procesados
CREATE OR REPLACE VIEW v_documentos_pendientes AS
SELECT 'ingreso'        AS tipo_documento,
       i.id_ingreso     AS id_documento,
       i.cod_ingreso    AS codigo,
       i.fecha          AS fecha,
       i.estado         AS estado,
       NULL::INTEGER    AS id_sala
FROM ingreso i
WHERE i.estado <> 'procesado'
UNION ALL
SELECT 'transferencia',
       t.id_transferencia,
       t.num_solicitud,
       t.fecha_confeccion,
       t.estado,
       t.id_sala
FROM transferencia t
WHERE t.estado <> 'procesado';