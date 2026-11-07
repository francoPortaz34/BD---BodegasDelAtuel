-- =====================================================================
-- tests/db_tests.sql  -  Etapa 2: pruebas de integridad y lógica
-- =====================================================================
-- Cómo ejecutarlo (sobre una base con las migraciones 001 a 007):
--   psql -v ON_ERROR_STOP=1 -U <superusuario> -d bodegas_test -f tests/db_tests.sql
--
-- Funcionamiento:
--   * Todo corre dentro de UNA transacción que termina en ROLLBACK:
--     no queda ningún dato de prueba en la base.
--   * Los datos de prueba usan ids desde 900001 y códigos 'TEST-...'
--     para no chocar con datos reales.
--   * Cada prueba imprime "OK [regla] ...". Si una prueba no da el
--     resultado esperado se lanza "FALLO [regla] ..." y, gracias a
--     ON_ERROR_STOP, el script se detiene con código de salida 3.
--   * Al final se imprime "TODAS LAS PRUEBAS PASARON".
--
-- Se ejecuta con un superusuario porque cambia de rol (SET ROLE) para
-- probar los permisos.
-- =====================================================================
\set ON_ERROR_STOP on
\set VERBOSITY terse
-- Se descarta la salida de los SELECT (filas vacías de los helpers);
-- los resultados se informan con NOTICE "OK ..." / "FALLO ...".
\o /dev/null
SET client_min_messages = notice;
SET search_path TO bodegas;

BEGIN;

-- ---------------------------------------------------------------------
-- Helpers de prueba (funciones temporales: desaparecen con el ROLLBACK)
-- ---------------------------------------------------------------------
-- debe_fallar(regla, sentencia, sqlstate esperado, parte del mensaje)
--   Ejecuta la sentencia y exige que falle con ese SQLSTATE y, si se
--   indica, con un mensaje que contenga el texto dado. Los cambios de la
--   sentencia fallida se revierten (bloque EXCEPTION = subtransacción).
--   SQLSTATE usados:
--     23514 CHECK   23505 UNIQUE   23503 FOREIGN KEY   23502 NOT NULL
--     P0001 RAISE EXCEPTION de un trigger/procedimiento
--     42501 permiso denegado      22P02 valor inválido para el tipo
CREATE FUNCTION pg_temp.debe_fallar(p_regla TEXT, p_sql TEXT, p_sqlstate TEXT, p_mensaje TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $f$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE <> p_sqlstate THEN
            RAISE EXCEPTION 'FALLO [%]: se esperaba SQLSTATE % y se obtuvo %: %',
                            p_regla, p_sqlstate, SQLSTATE, SQLERRM;
        END IF;
        IF p_mensaje IS NOT NULL AND position(p_mensaje IN SQLERRM) = 0 THEN
            RAISE EXCEPTION 'FALLO [%]: el mensaje no contiene "%": %', p_regla, p_mensaje, SQLERRM;
        END IF;
        RAISE NOTICE 'OK [%] rechazado: %', p_regla, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FALLO [%]: la sentencia debía fallar y se ejecutó: %', p_regla, p_sql;
END $f$;

-- verificar(regla, condición, descripción): exige que la condición sea verdadera
CREATE FUNCTION pg_temp.verificar(p_regla TEXT, p_condicion BOOLEAN, p_descripcion TEXT)
RETURNS VOID LANGUAGE plpgsql AS $f$
BEGIN
    IF p_condicion IS NOT TRUE THEN
        RAISE EXCEPTION 'FALLO [%]: %', p_regla, p_descripcion;
    END IF;
    RAISE NOTICE 'OK [%] %', p_regla, p_descripcion;
END $f$;

-- Los helpers deben poder usarse también con SET ROLE (pruebas de permisos)
GRANT EXECUTE ON FUNCTION pg_temp.debe_fallar(TEXT, TEXT, TEXT, TEXT),
                          pg_temp.verificar(TEXT, BOOLEAN, TEXT)
      TO bodegas_api, bodegas_reportes;


-- =====================================================================
-- DATOS DE PRUEBA (fixture) - casos que deben funcionar
-- =====================================================================
INSERT INTO encargado (id_encargado, nombre, apellido, dni) VALUES
    (900001, 'Ana',  'Test', 'T900001'),
    (900002, 'Beto', 'Test', 'T900002'),
    (900003, 'Caro', 'Test', 'T900003');

INSERT INTO localidad (id_localidad, cod_postal, nombre, provincia, id_encargado) VALUES
    (900001, '5600', 'TEST San Rafael',     'Mendoza', 900001),
    (900002, '5620', 'TEST General Alvear', 'Mendoza', 900002);

-- La sala 900002 cierra los 'jueves': el ENUM corregido funciona
INSERT INTO sala_de_ventas (id_sala, calle, numero, dia_cierre_semanal, id_localidad) VALUES
    (900001, 'Av. Test', '100', 'lunes',  900001),
    (900002, 'Calle Test', '200', 'jueves', 900002);

INSERT INTO tipo_cliente (id_tipo_cliente, nombre, porcentaje_descuento) VALUES
    (900001, 'TEST Socio',        10),
    (900002, 'TEST Distribuidor', 20),
    (900003, 'TEST Exportador',   30);

INSERT INTO cliente (id_cliente, nombre_o_razon_social, tipo_documento, num_documento,
                     calle, numero, fecha_alta, id_localidad, id_tipo_cliente) VALUES
    (900001, 'Socio Test',        'DNI',  'T-90000001', 'Calle 1', '1', '2020-01-15', 900001, 900001),
    (900002, 'Distribuidor Test', 'CUIT', 'T-90000002', 'Calle 2', '2', '2021-05-10', 900001, 900002),
    (900003, 'Exportador Test',   'CUIT', 'T-90000003', 'Calle 3', '3', '2019-03-01', 900002, 900003);
INSERT INTO socio        (id_cliente) VALUES (900001);
INSERT INTO distribuidor (id_cliente, zona_cobertura, numero_habilitacion) VALUES (900002, 'Sur', 'TEST-HAB-1');
INSERT INTO exportador   (id_cliente, pais_destino_principal) VALUES (900003, 'Brasil');

INSERT INTO bodega (id_bodega, cuit, razon_social, calle, numero) VALUES
    (900001, '30900000011', 'Bodega Test SA', 'Ruta Test', '1');

INSERT INTO transportista (id_transportista, cod_transporte, razon_social, cuit, calle, numero) VALUES
    (900001, 'TEST-T1', 'Transporte Uno', '30900000021', 'Ruta 1', '10'),
    (900002, 'TEST-T2', 'Transporte Dos', '30900000031', 'Ruta 2', '20');
INSERT INTO transportista_email (id_transportista, email) VALUES (900002, 'dos@test.com');

INSERT INTO cepa (id_cepa, nombre, tipo) VALUES
    (900001, 'TEST Malbec',             'tinta'),
    (900002, 'TEST Cabernet Sauvignon', 'tinta'),
    (900003, 'TEST Torrontés',          'blanca');

-- Ejemplo de la consigna: Malbec Reserva 2021, 750 ml, $12.500, 14°, 85 % / 15 %
INSERT INTO vino (id_vino, cod_vino, nombre_comercial, tipo, anada, presentacion_ml,
                  graduacion_alcoholica, precio_venta, id_bodega) VALUES
    (900001, 'TEST-V1', 'TEST Malbec Reserva', 'tinto',  2021, 750, 14.00, 12500, 900001),
    (900002, 'TEST-V2', 'TEST Torrontés',      'blanco', 2023, 750, 13.00,  8000, 900001),
    (900003, 'TEST-V3', 'TEST Cabernet',       'tinto',  2022, 750, 14.50,  9000, 900001);
INSERT INTO vino_cepa (id_vino, id_cepa, porcentaje_corte) VALUES
    (900001, 900001, 85), (900001, 900002, 15),
    (900002, 900003, 100),
    (900003, 900002, 100);

INSERT INTO departamento (id_departamento, nombre, provincia) VALUES (900001, 'TEST San Rafael', 'Mendoza');
INSERT INTO finca (id_finca, nombre, sup_total_ha, id_departamento) VALUES (900001, 'Finca Test', 50, 900001);
INSERT INTO parcela (id_finca, num_parcela, superficie, anio_plantacion, id_cepa) VALUES (900001, 1, 5, 2010, 900001);
INSERT INTO lote_de_uva (id_lote_uva, num_lote, id_finca, num_parcela, campania, fecha_cosecha,
                         kilos_cosechados, id_bodega_entrega) VALUES
    (900001, 'TEST-L1', 900001, 1, 2024, '2024-03-10', 8000, 900001);

-- Los vinos de prueba se controlan YA (RN-05) en lugar de esperar al COMMIT
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- Circuito completo de ingreso: en_confeccion -> terminado -> procesado
INSERT INTO ingreso (id_ingreso, cod_ingreso, id_transportista, id_bodega)   -- estado y fecha por DEFAULT
VALUES (900001, 'TEST-I1', 900001, 900001);
INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas) VALUES
    (900001, 900001, 100),
    (900001, 900002, 50);
UPDATE ingreso SET estado = 'terminado' WHERE id_ingreso = 900001;
CALL sp_procesar_ingreso(900001);

-- Circuito completo de transferencias hacia las dos salas
INSERT INTO transferencia (id_transferencia, num_solicitud, id_sala) VALUES
    (900001, 'TEST-TR1', 900001),
    (900002, 'TEST-TR2', 900002);
INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas) VALUES
    (900001, 900001, 10),
    (900001, 900002, 5),
    (900002, 900001, 5);
UPDATE transferencia SET estado = 'terminado' WHERE id_transferencia IN (900001, 900002);
CALL sp_procesar_transferencia(900001);
CALL sp_procesar_transferencia(900002);

-- Estado esperado después del fixture:
--   depósito: V1 = 100 - 10 - 5 = 85, V2 = 50 - 5 = 45, V3 sin fila
--   sala 900001: V1 = 10, V2 = 5      sala 900002: V1 = 5


-- =====================================================================
-- PROCEDIMIENTOS (casos que deben funcionar)
-- =====================================================================
SELECT pg_temp.verificar('sp_procesar_ingreso',
    (SELECT estado FROM ingreso WHERE id_ingreso = 900001) = 'procesado',
    'el ingreso procesado queda en estado procesado');
SELECT pg_temp.verificar('sp_procesar_transferencia',
    (SELECT cantidad FROM stock_deposito WHERE id_vino = 900001) = 85
    AND (SELECT cantidad FROM stock_deposito WHERE id_vino = 900002) = 45,
    'el depósito quedó en V1=85 y V2=45 (sumó el ingreso y restó las transferencias)');
SELECT pg_temp.verificar('sp_procesar_transferencia',
    fn_stock_sala(900001, 900001) = 10 AND fn_stock_sala(900001, 900002) = 5
    AND fn_stock_sala(900002, 900001) = 5,
    'las salas recibieron las botellas (sala1: V1=10, V2=5; sala2: V1=5)');


-- =====================================================================
-- VISTAS
-- =====================================================================
SELECT pg_temp.verificar('v_stock_total_vino',
    (SELECT (stock_deposito, stock_salas, stock_total) = (85::bigint, 15::bigint, 100::bigint)
     FROM v_stock_total_vino WHERE id_vino = 900001),
    'V1: depósito 85 + salas 15 = total 100');
SELECT pg_temp.verificar('v_stock_total_vino',
    (SELECT stock_total FROM v_stock_total_vino WHERE id_vino = 900003) = 0,
    'un vino sin ninguna fila de stock aparece con total 0 (LEFT JOIN)');


-- =====================================================================
-- RN-01: el precio de un vino es único para toda la red y mayor que 0
-- Mecanismo: atributo precio_venta en vino + CHECK ck_vino_precio_positivo
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-01',
    $$UPDATE vino SET precio_venta = 0 WHERE id_vino = 900001$$, '23514', 'ck_vino_precio_positivo');
SELECT pg_temp.debe_fallar('RN-01',
    $$UPDATE vino SET precio_venta = -100 WHERE id_vino = 900001$$, '23514');


-- =====================================================================
-- RN-02: una sala pertenece a una sola localidad; cada localidad tiene
-- un único encargado regional
-- Mecanismo: FK NOT NULL sala->localidad, FK localidad->encargado,
-- UNIQUE uq_localidad_encargado (un encargado, una localidad)
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-02',
    $$INSERT INTO sala_de_ventas (calle, numero, dia_cierre_semanal, id_localidad)
      VALUES ('X', '1', 'lunes', NULL)$$, '23502');
SELECT pg_temp.debe_fallar('RN-02',
    $$INSERT INTO sala_de_ventas (calle, numero, dia_cierre_semanal, id_localidad)
      VALUES ('X', '1', 'lunes', 999999999)$$, '23503', 'fk_sala_localidad');
SELECT pg_temp.debe_fallar('RN-02',
    $$INSERT INTO localidad (cod_postal, nombre, provincia, id_encargado)
      VALUES ('5601', 'Otra', 'Mendoza', 900001)$$, '23505', 'uq_localidad_encargado');


-- =====================================================================
-- RN-03: cada empleado trabaja en una sola sala
-- Mecanismo: FK NOT NULL empleado.id_sala
-- =====================================================================
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20900000011', 'Empleado Test', '2018-02-01', 500000, 900001);
SELECT pg_temp.verificar('RN-03', true, 'un empleado con su sala se inserta correctamente');
SELECT pg_temp.debe_fallar('RN-03',
    $$INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
      VALUES ('20900000022', 'Sin sala', '2020-01-01', 1000, NULL)$$, '23502');
SELECT pg_temp.debe_fallar('RN-03',
    $$INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
      VALUES ('20900000033', 'Sala falsa', '2020-01-01', 1000, 999999999)$$, '23503', 'fk_empleado_sala');


-- =====================================================================
-- RN-04: una parcela tiene una sola cepa y se cosecha como máximo una
-- vez por campaña
-- Mecanismo: FK parcela.id_cepa (una columna) + UNIQUE uq_lote_parcela_campania
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-04',
    $$INSERT INTO lote_de_uva (num_lote, id_finca, num_parcela, campania, fecha_cosecha,
                               kilos_cosechados, id_bodega_entrega)
      VALUES ('TEST-L2', 900001, 1, 2024, '2024-04-01', 5000, 900001)$$, '23505', 'uq_lote_parcela_campania');
INSERT INTO lote_de_uva (num_lote, id_finca, num_parcela, campania, fecha_cosecha, kilos_cosechados, id_bodega_entrega)
VALUES ('TEST-L3', 900001, 1, 2025, '2025-03-05', 7000, 900001);
SELECT pg_temp.verificar('RN-04', true, 'la misma parcela sí se cosecha en otra campaña (2025)');
SELECT pg_temp.debe_fallar('RN-04',
    $$INSERT INTO parcela (id_finca, num_parcela, superficie, anio_plantacion, id_cepa)
      VALUES (900001, 2, 3, 2015, 999999999)$$, '23503', 'fk_parcela_cepa');
-- CHECK entre columnas: la campaña es el año de la cosecha
SELECT pg_temp.debe_fallar('RN-04',
    $$INSERT INTO lote_de_uva (num_lote, id_finca, num_parcela, campania, fecha_cosecha,
                               kilos_cosechados, id_bodega_entrega)
      VALUES ('TEST-L4', 900001, 1, 2026, '2023-03-01', 5000, 900001)$$, '23514', 'ck_lote_campania_fecha');


-- =====================================================================
-- RN-05: los porcentajes de corte de un vino suman exactamente 100
-- Mecanismo: CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED
-- (SET CONSTRAINTS ALL IMMEDIATE adelanta el control que haría el COMMIT)
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-05',
    $$INSERT INTO vino (id_vino, cod_vino, nombre_comercial, tipo, anada, presentacion_ml,
                        graduacion_alcoholica, precio_venta, id_bodega)
      VALUES (900010, 'TEST-V10', 'TEST Corte 60', 'tinto', 2022, 750, 13.5, 9000, 900001);
      INSERT INTO vino_cepa VALUES (900010, 900001, 60);
      SET CONSTRAINTS ALL IMMEDIATE$$, 'P0001', 'suman 60.00 y deben sumar 100');
SET CONSTRAINTS ALL DEFERRED;
-- Dentro de la transacción la suma puede estar "incompleta" (60) mientras se carga
INSERT INTO vino (id_vino, cod_vino, nombre_comercial, tipo, anada, presentacion_ml,
                  graduacion_alcoholica, precio_venta, id_bodega)
VALUES (900012, 'TEST-V12', 'TEST Corte OK', 'tinto', 2022, 750, 13.5, 9500, 900001);
INSERT INTO vino_cepa VALUES (900012, 900001, 60);
INSERT INTO vino_cepa VALUES (900012, 900002, 40);
SET CONSTRAINTS ALL IMMEDIATE;   -- 60 + 40 = 100: no falla
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.verificar('RN-05', true, 'un vino con 60 % + 40 % pasa el control diferido');
-- Quitar una cepa deja la suma en 60
SELECT pg_temp.debe_fallar('RN-05',
    $$DELETE FROM vino_cepa WHERE id_vino = 900012 AND id_cepa = 900002;
      SET CONSTRAINTS ALL IMMEDIATE$$, 'P0001', 'deben sumar 100');
SET CONSTRAINTS ALL DEFERRED;


-- =====================================================================
-- RN-06: el descuento depende del tipo de cliente
-- Mecanismo: fn_descuento_cliente + dominio dom_porcentaje (0..100)
-- =====================================================================
SELECT pg_temp.verificar('RN-06',
    fn_descuento_cliente(900001) = 10 AND fn_descuento_cliente(900002) = 20
    AND fn_descuento_cliente(900003) = 30,
    'fn_descuento_cliente: socio 10, distribuidor 20, exportador 30');
SELECT pg_temp.debe_fallar('RN-06',
    $$SELECT fn_descuento_cliente(999999999)$$, 'P0001', 'no existe');
SELECT pg_temp.debe_fallar('RN-06',
    $$UPDATE tipo_cliente SET porcentaje_descuento = 120 WHERE id_tipo_cliente = 900001$$, '23514', 'dom_porcentaje');


-- =====================================================================
-- RN-07: un exportador puede tener varios permisos; el vencimiento es
-- posterior a la emisión
-- Mecanismo: tabla permiso_exportacion + CHECK entre columnas ck_permiso_fechas
-- =====================================================================
INSERT INTO permiso_exportacion (codigo, fecha_emision, fecha_vencimiento, id_cliente) VALUES
    ('TEST-P1', '2025-01-01', '2026-01-01', 900003),
    ('TEST-P2', '2025-06-01', '2027-06-01', 900003);
SELECT pg_temp.verificar('RN-07',
    (SELECT COUNT(*) FROM permiso_exportacion WHERE id_cliente = 900003) = 2,
    'un exportador tiene dos permisos');
SELECT pg_temp.debe_fallar('RN-07',
    $$INSERT INTO permiso_exportacion (codigo, fecha_emision, fecha_vencimiento, id_cliente)
      VALUES ('TEST-P3', '2025-01-01', '2025-01-01', 900003)$$, '23514', 'ck_permiso_fechas');
SELECT pg_temp.debe_fallar('RN-07',
    $$INSERT INTO permiso_exportacion (codigo, fecha_emision, fecha_vencimiento, id_cliente)
      VALUES ('TEST-P4', '2025-01-01', '2026-01-01', 900001)$$, '23503', 'fk_permiso_exportador');


-- =====================================================================
-- RN-08: el total del comprobante es la suma de sus renglones con el
-- descuento aplicado; no se carga a mano
-- Mecanismo: fn_total_comprobante + triggers trg_detalle_validar,
-- trg_detalle_actualizar y trg_comprobante_totales + CHECK ck_comprobante_importes
-- Datos: exportador (30 %) compra en la sala 900001
-- =====================================================================
-- Se intenta cargar importes a mano: el trigger los pisa con 0
INSERT INTO comprobante (id_comprobante, num_comprobante, id_cliente, id_sala, subtotal, descuento, total)
VALUES (900001, 'TEST-C1', 900003, 900001, 999, 0, 999);
SELECT pg_temp.verificar('RN-08',
    (SELECT (subtotal, descuento, total) = (0.00, 0.00, 0.00) FROM comprobante WHERE id_comprobante = 900001),
    'un comprobante nuevo ignora los importes cargados a mano y queda en 0');

-- Se intenta cargar precio, descuento y subtotal falsos: el trigger los calcula
INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
VALUES (900001, 900001, 2, 1, 0, 0);
SELECT pg_temp.verificar('RN-08',
    (SELECT (precio_unitario_venta, descuento_aplicado, subtotal_renglon) = (12500.00, 30.00, 17500.00)
     FROM detalle_comprobante WHERE id_comprobante = 900001 AND id_vino = 900001),
    'renglón: precio 12500 del vino, descuento 30 del exportador, subtotal 2*12500*0,70 = 17500');

INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
VALUES (900001, 900002, 1, 1, 0, 0);
SELECT pg_temp.verificar('RN-08',
    (SELECT (subtotal, descuento, total) = (33000.00, 9900.00, 23100.00) FROM comprobante WHERE id_comprobante = 900001),
    'comprobante con 2 renglones: subtotal 33000, descuento 9900, total 23100');
SELECT pg_temp.verificar('RN-08',
    fn_total_comprobante(900001) = 23100.00,
    'fn_total_comprobante devuelve 23100');

-- Modificar la cantidad recalcula renglón, totales y stock
UPDATE detalle_comprobante SET cantidad = 3 WHERE id_comprobante = 900001 AND id_vino = 900001;
SELECT pg_temp.verificar('RN-08',
    (SELECT (subtotal, descuento, total) = (45500.00, 13650.00, 31850.00) FROM comprobante WHERE id_comprobante = 900001),
    'al pasar V1 de 2 a 3 botellas: subtotal 45500, descuento 13650, total 31850');

-- Quitar un renglón devuelve el stock y recalcula
DELETE FROM detalle_comprobante WHERE id_comprobante = 900001 AND id_vino = 900002;
SELECT pg_temp.verificar('RN-08',
    (SELECT (subtotal, descuento, total) = (37500.00, 11250.00, 26250.00) FROM comprobante WHERE id_comprobante = 900001),
    'al quitar el renglón de V2: subtotal 37500, descuento 11250, total 26250');
SELECT pg_temp.verificar('RN-09',
    fn_stock_sala(900001, 900002) = 5,
    'el renglón quitado devolvió la botella de V2 a la sala (vuelve a 5)');

-- Modificar el total a mano no tiene efecto
UPDATE comprobante SET subtotal = 1, descuento = 0, total = 1 WHERE id_comprobante = 900001;
SELECT pg_temp.verificar('RN-08',
    (SELECT total FROM comprobante WHERE id_comprobante = 900001) = 26250.00,
    'un UPDATE manual del total se reemplaza por el valor calculado (26250)');
-- U1: recalcular el total usando la función
UPDATE comprobante SET total = fn_total_comprobante(id_comprobante) WHERE id_comprobante = 900001;
SELECT pg_temp.verificar('RN-08',
    (SELECT total = fn_total_comprobante(900001) FROM comprobante WHERE id_comprobante = 900001),
    'el total almacenado coincide con fn_total_comprobante');

-- No se puede cambiar la sala de un comprobante con renglones
SELECT pg_temp.debe_fallar('RN-08',
    $$UPDATE comprobante SET id_sala = 900002 WHERE id_comprobante = 900001$$, 'P0001', 'ya tiene renglones');
-- El CHECK entre columnas también protege si se desactivan los triggers
SELECT pg_temp.debe_fallar('RN-08',
    $$ALTER TABLE comprobante DISABLE TRIGGER trg_comprobante_totales;
      UPDATE comprobante SET total = 5 WHERE id_comprobante = 900001$$, '23514', 'ck_comprobante_importes');


-- =====================================================================
-- RN-09: no se puede vender más de lo que hay en la sala; el stock
-- nunca es negativo
-- Mecanismo: trigger BEFORE trg_detalle_validar (con FOR UPDATE) +
-- trigger AFTER trg_detalle_actualizar + dominio dom_cantidad (>= 0)
-- Stock sala 900001: V1 = 10 - 3 = 7
-- =====================================================================
SELECT pg_temp.verificar('RN-09', fn_stock_sala(900001, 900001) = 7,
    'la venta de 3 botellas dejó la sala 900001 con 7 de V1');

INSERT INTO comprobante (id_comprobante, num_comprobante, id_cliente, id_sala)
VALUES (900002, 'TEST-C2', 900001, 900001);
SELECT pg_temp.debe_fallar('RN-09',
    $$INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
      VALUES (900002, 900001, 8, 0, 0, 0)$$, 'P0001', 'Stock insuficiente del vino 900001 en la sala 900001: disponible 7, solicitado 8');
-- Vender exactamente lo que hay (la "última botella") sí se puede
INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
VALUES (900002, 900001, 7, 0, 0, 0);
SELECT pg_temp.verificar('RN-09', fn_stock_sala(900001, 900001) = 0,
    'vender las 7 botellas deja el stock en 0');
SELECT pg_temp.verificar('RN-06',
    (SELECT (descuento_aplicado, subtotal_renglon) = (10.00, 78750.00)
     FROM detalle_comprobante WHERE id_comprobante = 900002),
    'al socio se le aplica 10 %: 7*12500*0,90 = 78750');

INSERT INTO comprobante (id_comprobante, num_comprobante, id_cliente, id_sala)
VALUES (900003, 'TEST-C3', 900002, 900001);
SELECT pg_temp.debe_fallar('RN-09',
    $$INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
      VALUES (900003, 900001, 1, 0, 0, 0)$$, 'P0001', 'disponible 0, solicitado 1');
-- Vino que la sala nunca tuvo (no hay fila de stock)
SELECT pg_temp.debe_fallar('RN-09',
    $$INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
      VALUES (900003, 900003, 1, 0, 0, 0)$$, 'P0001', 'disponible 0');
-- Aumentar la cantidad de un renglón existente también se controla
SELECT pg_temp.debe_fallar('RN-09',
    $$UPDATE detalle_comprobante SET cantidad = 50 WHERE id_comprobante = 900001 AND id_vino = 900001$$,
    'P0001', 'Stock insuficiente');
-- El stock no puede quedar negativo aunque se escriba directamente
SELECT pg_temp.debe_fallar('RN-09',
    $$UPDATE stock_sala SET cantidad = -1 WHERE id_sala = 900001 AND id_vino = 900001$$, '23514', 'dom_cantidad');
SELECT pg_temp.debe_fallar('RN-09',
    $$UPDATE stock_deposito SET cantidad = cantidad - 1000 WHERE id_vino = 900001$$, '23514', 'dom_cantidad');


-- =====================================================================
-- RN-01 (precio único en toda la red) y borrado de comprobante completo
-- =====================================================================
INSERT INTO comprobante (id_comprobante, num_comprobante, id_cliente, id_sala)
VALUES (900004, 'TEST-C4', 900001, 900002);
INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
VALUES (900004, 900001, 1, 0, 0, 0);
SELECT pg_temp.verificar('RN-01',
    (SELECT precio_unitario_venta FROM detalle_comprobante WHERE id_comprobante = 900004)
  = (SELECT precio_unitario_venta FROM detalle_comprobante WHERE id_comprobante = 900001 AND id_vino = 900001),
    'el mismo vino se vende al mismo precio en la sala 900001 y en la sala 900002');
SELECT pg_temp.verificar('RN-09', fn_stock_sala(900002, 900001) = 4,
    'la venta en la sala 900002 descontó de esa sala (5 -> 4)');
-- Borrar un comprobante completo (depuración de historial, D1) NO devuelve stock
DELETE FROM comprobante WHERE id_comprobante = 900004;
SELECT pg_temp.verificar('RN-08',
    NOT EXISTS (SELECT 1 FROM detalle_comprobante WHERE id_comprobante = 900004)
    AND fn_stock_sala(900002, 900001) = 4,
    'borrar el comprobante borra sus renglones (CASCADE) y no modifica el stock');


-- =====================================================================
-- RN-13: todo cambio de precio queda auditado
-- Mecanismo: trigger AFTER UPDATE trg_vino_auditoria_precio + tabla
-- auditoria_precio. Que la API no pueda borrarla ni modificarla se prueba
-- en la sección de permisos del rol api (42501).
-- =====================================================================
UPDATE vino SET precio_venta = 13000 WHERE id_vino = 900001;
SELECT pg_temp.verificar('RN-13',
    (SELECT COUNT(*) FROM auditoria_precio WHERE id_vino = 900001) = 1
    AND (SELECT (precio_anterior, precio_nuevo, usuario) = (12500.00, 13000.00, session_user::varchar)
         FROM auditoria_precio WHERE id_vino = 900001),
    'cambio 12500 -> 13000 auditado con precio anterior, nuevo y usuario');
SELECT pg_temp.verificar('RN-13',
    (SELECT fecha_hora IS NOT NULL FROM auditoria_precio WHERE id_vino = 900001),
    'la auditoría registra la fecha y hora');
UPDATE vino SET nombre_comercial = 'TEST Malbec Reserva Edición' WHERE id_vino = 900001;
UPDATE vino SET precio_venta = 13000 WHERE id_vino = 900001;   -- mismo precio
SELECT pg_temp.verificar('RN-13',
    (SELECT COUNT(*) FROM auditoria_precio WHERE id_vino = 900001) = 1,
    'cambiar otra columna o "cambiar" al mismo precio no genera auditoría');
SELECT pg_temp.verificar('RN-01',
    (SELECT precio_unitario_venta FROM detalle_comprobante WHERE id_comprobante = 900001 AND id_vino = 900001) = 12500,
    'las ventas anteriores conservan el precio del momento de la venta');


-- =====================================================================
-- RN-10: sólo un ingreso terminado impacta en el depósito y pasa a
-- procesado; en_confeccion -> terminado -> procesado, sin retrocesos
-- Mecanismo: ENUM estado_movimiento + trigger trg_ingreso_estado +
-- procedimiento sp_procesar_ingreso
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-10',
    $$INSERT INTO ingreso (cod_ingreso, estado, id_transportista, id_bodega)
      VALUES ('TEST-IX', 'procesado', 900001, 900001)$$, 'P0001', 'debe crearse en estado en_confeccion');
SELECT pg_temp.debe_fallar('RN-10',
    $$UPDATE ingreso SET estado = 'pendiente' WHERE id_ingreso = 900001$$, '22P02');

INSERT INTO ingreso (id_ingreso, cod_ingreso, id_transportista, id_bodega) VALUES (900002, 'TEST-I2', 900001, 900001);
INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas) VALUES (900002, 900003, 30);
SELECT pg_temp.debe_fallar('RN-10',
    $$CALL sp_procesar_ingreso(900002)$$, 'P0001', 'sólo se puede procesar un ingreso terminado');
SELECT pg_temp.debe_fallar('RN-10',
    $$UPDATE ingreso SET estado = 'procesado' WHERE id_ingreso = 900002$$, 'P0001', 'Cambio de estado no permitido');
UPDATE ingreso SET estado = 'terminado' WHERE id_ingreso = 900002;
-- No se puede saltear el procedimiento (no movería el stock)
SELECT pg_temp.debe_fallar('RN-10',
    $$UPDATE ingreso SET estado = 'procesado' WHERE id_ingreso = 900002$$, 'P0001', 'sólo puede pasar a procesado con CALL sp_procesar_ingreso');
SELECT pg_temp.debe_fallar('RN-10',
    $$UPDATE ingreso SET estado = 'en_confeccion' WHERE id_ingreso = 900002$$, 'P0001', 'Cambio de estado no permitido');
CALL sp_procesar_ingreso(900002);
SELECT pg_temp.verificar('RN-10',
    (SELECT cantidad FROM stock_deposito WHERE id_vino = 900003) = 30,
    'procesar el ingreso creó la fila de V3 en el depósito con 30 botellas');
SELECT pg_temp.debe_fallar('RN-10',
    $$CALL sp_procesar_ingreso(900002)$$, 'P0001', 'está "procesado"');
SELECT pg_temp.verificar('RN-10',
    (SELECT cantidad FROM stock_deposito WHERE id_vino = 900003) = 30,
    'el segundo intento de procesar no duplicó el stock');
SELECT pg_temp.debe_fallar('RN-10',
    $$UPDATE ingreso SET estado = 'terminado' WHERE id_ingreso = 900002$$, 'P0001', 'Cambio de estado no permitido');
SELECT pg_temp.debe_fallar('RN-10',
    $$CALL sp_procesar_ingreso(999999999)$$, 'P0001', 'no existe');
INSERT INTO ingreso (id_ingreso, cod_ingreso, id_transportista, id_bodega) VALUES (900003, 'TEST-I3', 900001, 900001);
UPDATE ingreso SET estado = 'terminado' WHERE id_ingreso = 900003;
SELECT pg_temp.debe_fallar('RN-10',
    $$CALL sp_procesar_ingreso(900003)$$, 'P0001', 'no tiene renglones');


-- =====================================================================
-- RN-11: igual que RN-10 para transferencias; la fecha de confección es
-- la actual y no se puede modificar
-- Mecanismo: triggers trg_transferencia_estado y trg_transferencia_fecha
-- + procedimiento sp_procesar_transferencia
-- =====================================================================
INSERT INTO transferencia (id_transferencia, num_solicitud, fecha_confeccion, id_sala)
VALUES (900003, 'TEST-TR3', '2020-01-01', 900001);
SELECT pg_temp.verificar('RN-11',
    (SELECT fecha_confeccion FROM transferencia WHERE id_transferencia = 900003) = CURRENT_DATE,
    'la fecha 2020-01-01 enviada se reemplazó por la fecha actual');
SELECT pg_temp.debe_fallar('RN-11',
    $$UPDATE transferencia SET fecha_confeccion = CURRENT_DATE - 1 WHERE id_transferencia = 900003$$,
    'P0001', 'no se puede modificar');
SELECT pg_temp.debe_fallar('RN-11',
    $$INSERT INTO transferencia (num_solicitud, estado, id_sala) VALUES ('TEST-TRX', 'terminado', 900001)$$,
    'P0001', 'debe crearse en estado en_confeccion');

-- Stock insuficiente en el depósito: no queda ningún cambio a medias.
-- Renglón 1 (V2: 10 de 45) alcanza; renglón 2 (V1: 1000 de 85) no.
INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas) VALUES
    (900003, 900002, 10),
    (900003, 900001, 1000);
UPDATE transferencia SET estado = 'terminado' WHERE id_transferencia = 900003;
SELECT pg_temp.debe_fallar('RN-11',
    $$CALL sp_procesar_transferencia(900003)$$, 'P0001',
    'Stock insuficiente en el depósito central para el vino 900001: disponible 85, solicitado 1000');
SELECT pg_temp.verificar('RN-11',
    (SELECT cantidad FROM stock_deposito WHERE id_vino = 900002) = 45
    AND (SELECT cantidad FROM stock_deposito WHERE id_vino = 900001) = 85
    AND fn_stock_sala(900001, 900002) = 5
    AND (SELECT estado FROM transferencia WHERE id_transferencia = 900003) = 'terminado',
    'tras el error no cambió ningún stock (ni el renglón que alcanzaba) y sigue terminada');
SELECT pg_temp.debe_fallar('RN-11',
    $$UPDATE transferencia SET estado = 'procesado' WHERE id_transferencia = 900003$$,
    'P0001', 'sólo puede pasar a procesado con CALL sp_procesar_transferencia');
SELECT pg_temp.debe_fallar('RN-11',
    $$CALL sp_procesar_transferencia(900001)$$, 'P0001', 'está "procesado"');
SELECT pg_temp.debe_fallar('RN-11',
    $$UPDATE transferencia SET estado = 'terminado' WHERE id_transferencia = 900001$$,
    'P0001', 'Cambio de estado no permitido');

-- Vino sin fila en stock_deposito (V12 nunca ingresó): disponible 0
INSERT INTO transferencia (id_transferencia, num_solicitud, id_sala) VALUES (900004, 'TEST-TR4', 900002);
INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas) VALUES (900004, 900012, 1);
UPDATE transferencia SET estado = 'terminado' WHERE id_transferencia = 900004;
SELECT pg_temp.debe_fallar('RN-11',
    $$CALL sp_procesar_transferencia(900004)$$, 'P0001', 'disponible 0, solicitado 1');


-- =====================================================================
-- RN-12: un documento que no está en confección no admite agregar,
-- modificar ni quitar renglones
-- Mecanismo: triggers BEFORE trg_renglon_ingreso_bloqueo y
-- trg_renglon_transferencia_bloqueo
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-12',
    $$INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas) VALUES (900001, 900003, 5)$$,
    'P0001', 'no se pueden cambiar sus renglones');
SELECT pg_temp.debe_fallar('RN-12',
    $$UPDATE renglon_ingreso SET cantidad_botellas = 1 WHERE id_ingreso = 900001$$,
    'P0001', 'no se pueden cambiar sus renglones');
SELECT pg_temp.debe_fallar('RN-12',
    $$DELETE FROM renglon_transferencia WHERE id_transferencia = 900003$$,
    'P0001', 'está "terminado"');
SELECT pg_temp.debe_fallar('RN-12',
    $$UPDATE renglon_transferencia SET cantidad_botellas = 1 WHERE id_transferencia = 900001$$,
    'P0001', 'está "procesado"');
-- Mover un renglón de un documento abierto a uno cerrado también se bloquea
INSERT INTO ingreso (id_ingreso, cod_ingreso, id_transportista, id_bodega) VALUES (900004, 'TEST-I4', 900001, 900001);
INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas) VALUES (900004, 900001, 12);
SELECT pg_temp.debe_fallar('RN-12',
    $$UPDATE renglon_ingreso SET id_ingreso = 900001 WHERE id_ingreso = 900004$$,
    'P0001', 'El ingreso 900001');
-- En confección sí se puede modificar y quitar
UPDATE renglon_ingreso SET cantidad_botellas = 24 WHERE id_ingreso = 900004;
DELETE FROM renglon_ingreso WHERE id_ingreso = 900004;
SELECT pg_temp.verificar('RN-12',
    NOT EXISTS (SELECT 1 FROM renglon_ingreso WHERE id_ingreso = 900004),
    'un ingreso en confección permite modificar y quitar renglones');


-- =====================================================================
-- RN-14: no se puede borrar un transportista, una bodega ni un vino con
-- movimientos asociados
-- Mecanismo: FK con ON DELETE RESTRICT
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-14',
    $$DELETE FROM transportista WHERE id_transportista = 900001$$, '23503', 'fk_ingreso_transportista');
SELECT pg_temp.debe_fallar('RN-14',
    $$DELETE FROM bodega WHERE id_bodega = 900001$$, '23503');
SELECT pg_temp.debe_fallar('RN-14',
    $$DELETE FROM vino WHERE id_vino = 900002$$, '23503');
-- Un transportista SIN movimientos sí se borra (y su e-mail con él, CASCADE)
DELETE FROM transportista WHERE id_transportista = 900002;
SELECT pg_temp.verificar('RN-14',
    NOT EXISTS (SELECT 1 FROM transportista_email WHERE id_transportista = 900002),
    'un transportista sin movimientos se borra junto con sus e-mails');


-- =====================================================================
-- RN-15: cantidades, superficies, kilos y precios positivos; graduación
-- entre 5 y 20
-- Mecanismo: CHECK
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-15',
    $$UPDATE vino SET graduacion_alcoholica = 4.99 WHERE id_vino = 900001$$, '23514', 'ck_vino_graduacion');
SELECT pg_temp.debe_fallar('RN-15',
    $$UPDATE vino SET graduacion_alcoholica = 20.01 WHERE id_vino = 900001$$, '23514', 'ck_vino_graduacion');
SELECT pg_temp.debe_fallar('RN-15',
    $$UPDATE lote_de_uva SET kilos_cosechados = 0 WHERE id_lote_uva = 900001$$, '23514', 'ck_lote_kilos');
SELECT pg_temp.debe_fallar('RN-15',
    $$UPDATE finca SET sup_total_ha = 0 WHERE id_finca = 900001$$, '23514', 'ck_finca_superficie');
SELECT pg_temp.debe_fallar('RN-15',
    $$UPDATE parcela SET superficie = -1 WHERE id_finca = 900001$$, '23514', 'ck_parcela_superficie');
INSERT INTO transferencia (id_transferencia, num_solicitud, id_sala) VALUES (900005, 'TEST-TR5', 900001);
SELECT pg_temp.debe_fallar('RN-15',
    $$INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas) VALUES (900005, 900001, 0)$$,
    '23514', 'ck_renglon_transferencia_cantidad');
SELECT pg_temp.debe_fallar('RN-15',
    $$INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas) VALUES (900004, 900001, -5)$$,
    '23514');
SELECT pg_temp.debe_fallar('RN-15',
    $$INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
      VALUES (900003, 900002, 0, 0, 0, 0)$$, '23514', 'ck_detalle_cantidad');


-- =====================================================================
-- OTRAS RESTRICCIONES: UNIQUE, CHECK, DEFAULT, ENUM
-- =====================================================================
SELECT pg_temp.debe_fallar('UNIQUE',
    $$INSERT INTO vino (cod_vino, nombre_comercial, tipo, anada, presentacion_ml, graduacion_alcoholica, precio_venta, id_bodega)
      VALUES ('TEST-V99', 'TEST Torrontés', 'blanco', 2023, 750, 13, 8000, 900001)$$,
    '23505', 'uq_vino_nombre_anada_presentacion');
SELECT pg_temp.debe_fallar('UNIQUE',
    $$INSERT INTO cliente (nombre_o_razon_social, tipo_documento, num_documento, calle, numero, id_localidad, id_tipo_cliente)
      VALUES ('Repetido', 'DNI', 'T-90000001', 'X', '1', 900001, 900001)$$, '23505', 'uq_cliente_documento');
SELECT pg_temp.debe_fallar('UNIQUE',
    $$INSERT INTO departamento (nombre, provincia) VALUES ('TEST San Rafael', 'Mendoza')$$,
    '23505', 'uq_departamento_nombre_provincia');
SELECT pg_temp.debe_fallar('UNIQUE',
    $$INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas) VALUES (900005, 900001, 1), (900005, 900001, 2)$$,
    '23505', 'uq_renglon_transferencia_vino');
SELECT pg_temp.debe_fallar('CHECK',
    $$UPDATE vino SET presentacion_ml = 700 WHERE id_vino = 900001$$, '23514', 'ck_vino_presentacion');
SELECT pg_temp.debe_fallar('CHECK',
    $$UPDATE empleado SET salario = 0 WHERE cuit = '20900000011'$$, '23514', 'ck_empleado_salario');
SELECT pg_temp.debe_fallar('CHECK',
    $$INSERT INTO analisis_calidad (id_lote_uva, fecha, grado_brix, ph, acidez_total)
      VALUES (900001, '2024-03-12', 24.5, 15, 6)$$, '23514', 'ck_analisis_ph');
SELECT pg_temp.debe_fallar('DOMAIN',
    $$UPDATE bodega SET cuit = '30-1234567' WHERE id_bodega = 900001$$, '23514', 'dom_cuit');

INSERT INTO cliente (id_cliente, nombre_o_razon_social, tipo_documento, num_documento, calle, numero, id_localidad, id_tipo_cliente)
VALUES (900010, 'Cliente Default', 'DNI', 'T-90000010', 'X', '1', 900001, 900001);
SELECT pg_temp.verificar('DEFAULT',
    (SELECT fecha_alta FROM cliente WHERE id_cliente = 900010) = CURRENT_DATE,
    'cliente.fecha_alta toma la fecha actual por defecto');
SELECT pg_temp.verificar('DEFAULT',
    (SELECT (estado, fecha) = ('en_confeccion'::estado_movimiento, CURRENT_DATE) FROM ingreso WHERE id_ingreso = 900004),
    'ingreso: estado en_confeccion y fecha actual por defecto');
SELECT pg_temp.verificar('ENUM',
    'jueves'::dia_semana = 'jueves',
    'el valor jueves del ENUM dia_semana quedó corregido (sin espacio)');
SELECT pg_temp.debe_fallar('ENUM',
    $$SELECT ' jueves'::dia_semana$$, '22P02');


-- =====================================================================
-- FUNCIONES: casos límite
-- =====================================================================
SELECT pg_temp.verificar('fn_stock_sala', fn_stock_sala(900002, 900002) = 0,
    'devuelve 0 (no NULL) si la sala no tiene fila de stock para el vino');
SELECT pg_temp.verificar('fn_total_comprobante', fn_total_comprobante(900003) = 0,
    'devuelve 0 para un comprobante sin renglones');
SELECT pg_temp.verificar('fn_total_comprobante', fn_total_comprobante(999999999) = 0,
    'devuelve 0 para un comprobante inexistente');
SELECT pg_temp.verificar('fn_antiguedad_anios',
    fn_antiguedad_anios((CURRENT_DATE - INTERVAL '5 years')::date) = 5
    AND fn_antiguedad_anios((CURRENT_DATE - INTERVAL '5 years' + INTERVAL '1 day')::date) = 4,
    'cuenta años completos: hace 5 años exactos = 5; un día menos = 4');
SELECT pg_temp.verificar('fn_antiguedad_anios',
    fn_antiguedad_anios(CURRENT_DATE) = 0 AND fn_antiguedad_anios(CURRENT_DATE + 30) = 0
    AND fn_antiguedad_anios(NULL) IS NULL,
    'hoy = 0, fecha futura = 0, NULL = NULL');
SELECT pg_temp.verificar('fn_antiguedad_anios',
    (SELECT COUNT(*) FROM empleado WHERE cuit = '20900000011' AND fn_antiguedad_anios(fecha_ingreso) > 5) = 1,
    'uso en U2: el empleado ingresado en 2018 tiene más de 5 años');


-- =====================================================================
-- VISTAS (segunda parte)
-- =====================================================================
SELECT pg_temp.verificar('v_documentos_pendientes',
    EXISTS (SELECT 1 FROM v_documentos_pendientes WHERE tipo_documento = 'ingreso' AND id_documento = 900004)
    AND EXISTS (SELECT 1 FROM v_documentos_pendientes WHERE tipo_documento = 'transferencia' AND id_documento = 900003)
    AND NOT EXISTS (SELECT 1 FROM v_documentos_pendientes WHERE tipo_documento = 'ingreso' AND id_documento = 900001),
    'lista el ingreso en confección y la transferencia terminada, no el ingreso procesado');

-- Comprobantes de la sala 900001 este mes: C1 (26250) + C2 (78750) + C3 (0) = 105000
REFRESH MATERIALIZED VIEW mv_ventas_mensuales_sala;
SELECT pg_temp.verificar('mv_ventas_mensuales_sala',
    (SELECT (cantidad_comprobantes, monto_total) = (3::bigint, 105000.00)
     FROM mv_ventas_mensuales_sala
     WHERE id_sala = 900001 AND mes = date_trunc('month', CURRENT_DATE)::date),
    'después de REFRESH: sala 900001, mes actual, 3 comprobantes por $105.000');


-- =====================================================================
-- ROLES Y PERMISOS
-- =====================================================================
SELECT pg_temp.verificar('ROLES',
    (SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'bodegas' AND tableowner <> 'bodegas_owner') = 0
    AND (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'bodegas') = 'bodegas_owner',
    'bodegas_owner es el dueño del esquema y de todas las tablas');
SELECT pg_temp.verificar('ROLES',
    NOT has_schema_privilege('public', 'bodegas', 'USAGE')
    AND NOT has_function_privilege('public', 'bodegas.fn_stock_sala(integer,integer)', 'EXECUTE'),
    'PUBLIC no tiene acceso al esquema ni puede ejecutar funciones');
SELECT pg_temp.verificar('ROLES',
    NOT has_table_privilege('bodegas_api', 'bodegas.stock_sala', 'UPDATE')
    AND NOT has_table_privilege('bodegas_api', 'bodegas.stock_deposito', 'INSERT')
    AND NOT has_table_privilege('bodegas_api', 'bodegas.auditoria_precio', 'DELETE')
    AND has_table_privilege('bodegas_api', 'bodegas.comprobante', 'INSERT'),
    'la API escribe comprobantes pero no stock ni auditoría');
SELECT pg_temp.verificar('ROLES',
    (SELECT rolsuper FROM pg_roles WHERE rolname = 'bodegas_api') = false
    AND (SELECT rolcanlogin FROM pg_roles WHERE rolname = 'bodegas_owner') = false,
    'la API no es superusuario y el propietario no inicia sesión directamente');

-- ---- Rol de reportes: sólo lectura ----------------------------------
SET ROLE bodegas_reportes;
SELECT pg_temp.verificar('ROL reportes',
    (SELECT COUNT(*) FROM v_stock_total_vino WHERE id_vino = 900001) = 1
    AND fn_stock_sala(900002, 900001) = 4,
    'puede leer vistas y usar funciones de consulta');
SELECT pg_temp.debe_fallar('ROL reportes',
    $$INSERT INTO bodega (cuit, razon_social, calle, numero) VALUES ('30900000099', 'X', 'X', '1')$$, '42501');
SELECT pg_temp.debe_fallar('ROL reportes',
    $$UPDATE vino SET precio_venta = 1 WHERE id_vino = 900001$$, '42501');
SELECT pg_temp.debe_fallar('ROL reportes',
    $$DELETE FROM comprobante WHERE id_comprobante = 900003$$, '42501');
SELECT pg_temp.debe_fallar('ROL reportes',
    $$CALL sp_procesar_transferencia(900003)$$, '42501');
RESET ROLE;

-- ---- Rol de la API --------------------------------------------------
SET ROLE bodegas_api;
SELECT pg_temp.debe_fallar('ROL api',
    $$UPDATE stock_sala SET cantidad = 999 WHERE id_sala = 900001$$, '42501');
SELECT pg_temp.debe_fallar('ROL api',
    $$INSERT INTO stock_deposito (id_vino, cantidad) VALUES (900012, 999)$$, '42501');
SELECT pg_temp.debe_fallar('ROL api',
    $$DELETE FROM auditoria_precio$$, '42501');
SELECT pg_temp.debe_fallar('ROL api',
    $$UPDATE transferencia SET estado = 'procesado' WHERE id_transferencia = 900003$$,
    'P0001', 'sólo puede pasar a procesado con CALL');
-- Una venta completa hecha por la API funciona (los triggers mueven el stock)
INSERT INTO comprobante (id_comprobante, num_comprobante, id_cliente, id_sala) VALUES (900010, 'TEST-C-API', 900002, 900002);
INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon)
VALUES (900010, 900001, 2, 0, 0, 0);
SELECT pg_temp.verificar('ROL api',
    (SELECT total FROM comprobante WHERE id_comprobante = 900010) = 20800.00
    AND fn_stock_sala(900002, 900001) = 2,
    'la API vende 2 botellas a $13000 con 20 %: total 20800 y la sala baja de 4 a 2');
-- La API cambia un precio: queda auditado
UPDATE vino SET precio_venta = 13500 WHERE id_vino = 900001;
SELECT pg_temp.verificar('ROL api',
    (SELECT COUNT(*) FROM auditoria_precio WHERE id_vino = 900001 AND precio_nuevo = 13500) = 1,
    'un cambio de precio hecho por la API queda auditado');
-- La API procesa por medio del procedimiento
INSERT INTO transferencia (id_transferencia, num_solicitud, id_sala) VALUES (900020, 'TEST-TR-API', 900002);
INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas) VALUES (900020, 900002, 3);
UPDATE transferencia SET estado = 'terminado' WHERE id_transferencia = 900020;
CALL sp_procesar_transferencia(900020);
SELECT pg_temp.verificar('ROL api',
    fn_stock_sala(900002, 900002) = 3
    AND (SELECT estado FROM transferencia WHERE id_transferencia = 900020) = 'procesado',
    'la API procesa una transferencia con CALL sp_procesar_transferencia');
RESET ROLE;


-- =====================================================================
-- Borrado de un ingreso procesado completo (consulta D5): el CASCADE de
-- sus renglones no queda bloqueado por RN-12 y el stock no cambia
-- =====================================================================
DELETE FROM ingreso WHERE id_ingreso = 900002;
SELECT pg_temp.verificar('RN-12',
    NOT EXISTS (SELECT 1 FROM renglon_ingreso WHERE id_ingreso = 900002)
    AND (SELECT cantidad FROM stock_deposito WHERE id_vino = 900003) = 30,
    'borrar un ingreso procesado borra sus renglones (CASCADE) sin tocar el depósito');


DO $$ BEGIN RAISE NOTICE '=== TODAS LAS PRUEBAS PASARON ==='; END $$;

ROLLBACK;
