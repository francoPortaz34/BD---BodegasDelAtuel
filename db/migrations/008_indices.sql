-- =====================================================================
-- 008_indices.sql  -  Etapa 4: índices y rendimiento
-- PostgreSQL crea índices solo para PRIMARY KEY y UNIQUE; las claves
-- foráneas y los filtros frecuentes hay que indexarlos a mano.
-- =====================================================================
SET search_path TO bodegas;

-- 1. CLAVE FORÁNEA: comprobante.id_cliente  ->  S12
--    S12 busca, para cada cliente, sus comprobantes. Sin índice recorre
--    los 150.000 comprobantes una vez por cliente.
CREATE INDEX idx_comprobante_cliente ON comprobante (id_cliente);

-- 2. CLAVE FORÁNEA: detalle_comprobante.id_vino
--    La PK es (id_comprobante, id_vino): sirve para buscar por comprobante,
--    pero no por vino. Se usa al borrar un vino (la FK revisa que no tenga
--    ventas) y en las consultas por vino.
CREATE INDEX idx_detalle_vino ON detalle_comprobante (id_vino);

-- 3. COMPUESTO: comprobante (id_sala, fecha)  ->  S3
--    Primero la columna de igualdad (id_sala) y después la de rango (fecha):
--    el índice va directo a la sala y recorre solo las fechas pedidas.
CREATE INDEX idx_comprobante_sala_fecha ON comprobante (id_sala, fecha);

-- 4. CON INCLUDE (cubriente): comprobante (fecha) + id_sala, total  ->  S8
--    S8 solo usa fecha, id_sala y total: como están todas en el índice,
--    responde sin leer la tabla (Index Only Scan).
CREATE INDEX idx_comprobante_fecha_cubriente ON comprobante (fecha) INCLUDE (id_sala, total);

-- 5. PARCIAL: transferencias pendientes  ->  S5
--    Solo indexa las NO procesadas, que son pocas y las que se consultan
--    seguido. El índice es chico y no crece con el historial.
CREATE INDEX idx_transferencia_pendiente ON transferencia (id_sala)
    WHERE estado <> 'procesado';

-- 6. CLAVE FORÁNEA: renglon_transferencia.id_vino  ->  S4
CREATE INDEX idx_renglon_transf_vino ON renglon_transferencia (id_vino);

-- Actualizar estadísticas para que el planificador conozca los índices
ANALYZE;
