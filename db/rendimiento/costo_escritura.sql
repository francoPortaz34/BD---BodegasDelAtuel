-- =====================================================================
-- costo_escritura.sql  -  Etapa 4, paso 7
-- Mide cuánto tarda insertar todos los renglones de venta en una tabla
-- SIN índices y en otra CON la clave primaria y el índice de la FK.
-- Usa tablas de prueba que se borran al final: no toca los datos reales.
-- =====================================================================
SET search_path TO bodegas;
\timing on

\echo '--- Inserción SIN índices'
CREATE TABLE prueba_sin_indices AS SELECT * FROM detalle_comprobante WITH NO DATA;
INSERT INTO prueba_sin_indices SELECT * FROM detalle_comprobante;

\echo '--- Inserción CON índices (PK + índice de la FK id_vino)'
CREATE TABLE prueba_con_indices AS SELECT * FROM detalle_comprobante WITH NO DATA;
ALTER TABLE prueba_con_indices ADD PRIMARY KEY (id_comprobante, id_vino);
CREATE INDEX ON prueba_con_indices (id_vino);
INSERT INTO prueba_con_indices SELECT * FROM detalle_comprobante;

\timing off
DROP TABLE prueba_sin_indices, prueba_con_indices;
