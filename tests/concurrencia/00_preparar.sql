-- =====================================================================
-- Demostración de concurrencia - preparación (se CONFIRMA con COMMIT)
-- =====================================================================
-- Deja la sala 800001 con UNA sola botella del vino 800001 (CONC-V1).
-- Se ejecuta sobre la base de PRUEBAS (bodegas_test), nunca sobre la
-- base principal. Para limpiar todo, volver a correr run_etapa2.sh, que
-- recrea bodegas_test desde cero.
-- Ids 800001 para no chocar con los de tests/db_tests.sql (900001).
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path TO bodegas;

BEGIN;
INSERT INTO encargado (id_encargado, nombre, apellido, dni) VALUES (800001, 'Conc', 'Demo', 'C800001');
INSERT INTO localidad (id_localidad, cod_postal, nombre, provincia, id_encargado)
VALUES (800001, '5600', 'CONC San Rafael', 'Mendoza', 800001);
INSERT INTO sala_de_ventas (id_sala, calle, numero, dia_cierre_semanal, id_localidad)
VALUES (800001, 'Av. Concurrencia', '1', 'lunes', 800001);
INSERT INTO tipo_cliente (id_tipo_cliente, nombre, porcentaje_descuento) VALUES (800001, 'CONC Socio', 10);
INSERT INTO cliente (id_cliente, nombre_o_razon_social, tipo_documento, num_documento, calle, numero, id_localidad, id_tipo_cliente)
VALUES (800001, 'Cliente A', 'DNI', 'C-1', 'X', '1', 800001, 800001),
       (800002, 'Cliente B', 'DNI', 'C-2', 'X', '2', 800001, 800001);
INSERT INTO socio (id_cliente) VALUES (800001), (800002);
INSERT INTO bodega (id_bodega, cuit, razon_social, calle, numero) VALUES (800001, '30800000011', 'Bodega Conc', 'X', '1');
INSERT INTO transportista (id_transportista, cod_transporte, razon_social, cuit, calle, numero)
VALUES (800001, 'CONC-T1', 'Transp Conc', '30800000021', 'X', '1');
INSERT INTO cepa (id_cepa, nombre, tipo) VALUES (800001, 'CONC Malbec', 'tinta');
INSERT INTO vino (id_vino, cod_vino, nombre_comercial, tipo, anada, presentacion_ml, graduacion_alcoholica, precio_venta, id_bodega)
VALUES (800001, 'CONC-V1', 'CONC Ultima Botella', 'tinto', 2021, 750, 14, 10000, 800001);
INSERT INTO vino_cepa (id_vino, id_cepa, porcentaje_corte) VALUES (800001, 800001, 100);

-- 1 botella al depósito y de ahí a la sala, por el circuito normal
INSERT INTO ingreso (id_ingreso, cod_ingreso, id_transportista, id_bodega) VALUES (800001, 'CONC-I1', 800001, 800001);
INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas) VALUES (800001, 800001, 1);
UPDATE ingreso SET estado = 'terminado' WHERE id_ingreso = 800001;
CALL sp_procesar_ingreso(800001);

INSERT INTO transferencia (id_transferencia, num_solicitud, id_sala) VALUES (800001, 'CONC-TR1', 800001);
INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas) VALUES (800001, 800001, 1);
UPDATE transferencia SET estado = 'terminado' WHERE id_transferencia = 800001;
CALL sp_procesar_transferencia(800001);

-- Un comprobante (todavía sin renglones) para cada cliente
INSERT INTO comprobante (id_comprobante, num_comprobante, id_cliente, id_sala)
VALUES (800001, 'CONC-A', 800001, 800001),
       (800002, 'CONC-B', 800002, 800001);
COMMIT;

SELECT id_sala, id_vino, cantidad AS stock_inicial
FROM stock_sala WHERE id_sala = 800001 AND id_vino = 800001;
