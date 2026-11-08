-- =====================================================================
-- consultas/insert.sql  -  Etapa 5: inserción de datos (INSERT)
-- =====================================================================
-- Cómo ejecutarlo (desde la raíz del repo):
--   docker exec -i bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < consultas/insert.sql
-- Cada consigna se prueba en una transacción que termina en ROLLBACK.
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- I1. Agregar la cobertura de General Alvear al transportista que menos
--     ingresos trasladó en el último trimestre.
-- Estrategia: subconsulta con LEFT JOIN (así cuentan también los que no
-- trasladaron nada), COUNT, orden ascendente y LIMIT 1.
-- ---------------------------------------------------------------------
\echo '=== I1: cobertura de General Alvear para el transportista con menos envíos'
BEGIN;
INSERT INTO transportista_localidad (id_transportista, id_localidad)
VALUES (
    (SELECT t.id_transportista
     FROM transportista t
     LEFT JOIN ingreso i ON i.id_transportista = t.id_transportista
                        AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
     GROUP BY t.id_transportista
     ORDER BY COUNT(i.id_ingreso), t.id_transportista
     LIMIT 1),
    (SELECT id_localidad FROM localidad WHERE nombre = 'Ciudad de General Alvear')
);

SELECT t.cod_transporte, t.razon_social, l.nombre AS localidad
FROM transportista_localidad tl
JOIN transportista t ON t.id_transportista = tl.id_transportista
JOIN localidad l     ON l.id_localidad = tl.id_localidad
WHERE l.nombre = 'Ciudad de General Alvear';
ROLLBACK;


-- ---------------------------------------------------------------------
-- I2. Si existe algún vino tinto de 14° o más, crear el maridaje
--     "Cordero al disco" y asociarlo a todos esos vinos.
-- Estrategia: INSERT ... SELECT ... WHERE EXISTS crea el maridaje solo si
-- hay algún vino que cumpla. Después, INSERT ... SELECT asocia el maridaje
-- a cada vino tinto de 14° o más.
-- ---------------------------------------------------------------------
\echo '=== I2: maridaje "Cordero al disco" para los tintos de 14° o más'
BEGIN;
INSERT INTO maridaje (nombre, temperatura_sugerida)
SELECT 'Cordero al disco', 16
WHERE EXISTS (SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion_alcoholica >= 14);

INSERT INTO vino_maridaje (id_vino, id_maridaje)
SELECT v.id_vino, (SELECT id_maridaje FROM maridaje WHERE nombre = 'Cordero al disco')
FROM vino v
WHERE v.tipo = 'tinto' AND v.graduacion_alcoholica >= 14;

SELECT COUNT(*) AS vinos_con_cordero_al_disco
FROM vino_maridaje vm
JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
WHERE m.nombre = 'Cordero al disco';
ROLLBACK;


-- ---------------------------------------------------------------------
-- I3. Crear un comprobante con tres renglones para un cliente dado, en la
--     sala 1, dentro de una transacción y usando las funciones de cálculo.
-- Estrategia: se inserta la cabecera y después los renglones. Precio,
-- descuento y subtotal van en 0: el trigger de la venta los completa con
-- el precio del vino y fn_descuento_cliente. Otro trigger descuenta el
-- stock y calcula el total del comprobante con fn_total_comprobante.
-- Se eligen 3 vinos que tengan stock en la sala (si no, el trigger rechaza
-- la venta, RN-09).
-- ---------------------------------------------------------------------
\echo '=== I3: venta de 3 vinos al cliente 1 en la sala 1'
BEGIN;
INSERT INTO comprobante (num_comprobante, id_cliente, id_sala)
VALUES ('C-PRUEBA-I3', 1, 1);                    -- <- parámetro: cliente

INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad,
                                 precio_unitario_venta, descuento_aplicado, subtotal_renglon)
SELECT (SELECT id_comprobante FROM comprobante WHERE num_comprobante = 'C-PRUEBA-I3'),
       id_vino, 2, 0, 0, 0
FROM stock_sala
WHERE id_sala = 1 AND cantidad >= 2
ORDER BY id_vino
LIMIT 3;

SELECT d.id_vino, d.cantidad, d.precio_unitario_venta, d.descuento_aplicado, d.subtotal_renglon
FROM detalle_comprobante d
JOIN comprobante c ON c.id_comprobante = d.id_comprobante
WHERE c.num_comprobante = 'C-PRUEBA-I3';

SELECT subtotal, descuento, total,
       fn_total_comprobante(id_comprobante) AS total_con_funcion,
       fn_descuento_cliente(id_cliente)     AS porcentaje_cliente
FROM comprobante
WHERE num_comprobante = 'C-PRUEBA-I3';
ROLLBACK;


-- ---------------------------------------------------------------------
-- I4. Insertar una nueva bodega.
-- ---------------------------------------------------------------------
\echo '=== I4: nueva bodega'
BEGIN;
INSERT INTO bodega (cuit, razon_social, calle, numero)
VALUES ('30712345678', 'Bodega Los Álamos', 'Ruta 143', '1500');

SELECT * FROM bodega WHERE cuit = '30712345678';
ROLLBACK;


-- ---------------------------------------------------------------------
-- I5. Insertar una nueva sala de venta.
-- Estrategia: la localidad se busca por nombre con una subconsulta.
-- ---------------------------------------------------------------------
\echo '=== I5: nueva sala de venta'
BEGIN;
INSERT INTO sala_de_ventas (calle, numero, dia_cierre_semanal, id_localidad)
VALUES ('Av. San Martín', '250', 'lunes',
        (SELECT id_localidad FROM localidad WHERE nombre = 'Ciudad de San Rafael'));

SELECT s.id_sala, s.calle, s.numero, s.dia_cierre_semanal, l.nombre AS localidad
FROM sala_de_ventas s
JOIN localidad l ON l.id_localidad = s.id_localidad
WHERE s.calle = 'Av. San Martín' AND s.numero = '250';
ROLLBACK;


-- ---------------------------------------------------------------------
-- I6. Crear un ingreso en confección de 120 botellas de "Malbec Reserva"
--     de 750 ml, de una bodega dada y con un transportista dado.
-- Estrategia: el estado (en_confeccion) y la fecha (hoy) los pone el
-- DEFAULT. El vino, la bodega y el transportista se buscan por nombre o código.
-- ---------------------------------------------------------------------
\echo '=== I6: ingreso en confección de 120 Malbec Reserva 750 ml'
BEGIN;
INSERT INTO ingreso (cod_ingreso, id_transportista, id_bodega)
VALUES ('IN-PRUEBA-I6',
        (SELECT id_transportista FROM transportista WHERE cod_transporte = 'T001'),   -- <- transportista
        (SELECT id_bodega FROM bodega WHERE razon_social = 'Bodega Campos'));      -- <- bodega

INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas)
VALUES ((SELECT id_ingreso FROM ingreso WHERE cod_ingreso = 'IN-PRUEBA-I6'),
        (SELECT v.id_vino
         FROM vino v
         JOIN bodega b ON b.id_bodega = v.id_bodega
         WHERE v.nombre_comercial = 'Malbec Reserva' AND v.presentacion_ml = 750
           AND v.anada = 2021 AND b.razon_social = 'Bodega Campos'),
        120);

SELECT i.cod_ingreso, i.fecha, i.estado, v.nombre_comercial, r.cantidad_botellas
FROM ingreso i
JOIN renglon_ingreso r ON r.id_ingreso = i.id_ingreso
JOIN vino v            ON v.id_vino = r.id_vino
WHERE i.cod_ingreso = 'IN-PRUEBA-I6';
ROLLBACK;
