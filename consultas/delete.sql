-- =====================================================================
-- consultas/delete.sql  -  Etapa 5: borrado de datos (DELETE)
-- =====================================================================
-- Cómo ejecutarlo (desde la raíz del repo):
--   docker exec -i bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < consultas/delete.sql
-- Cada consigna se prueba en una transacción que termina en ROLLBACK.
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- D1. Borrar los comprobantes con más de 5 años de antigüedad de clientes
--     socios del club.
-- Estrategia: subconsulta con IN sobre la tabla socio. Los renglones se
-- borran solos por ON DELETE CASCADE. El stock no cambia: el trigger de la
-- venta detecta que se borró el comprobante entero (es una depuración de
-- historial, no una devolución).
-- ---------------------------------------------------------------------
\echo '=== D1: comprobantes de socios con más de 5 años'
BEGIN;
SELECT (SELECT COUNT(*) FROM comprobante)         AS comprobantes_antes,
       (SELECT COUNT(*) FROM detalle_comprobante) AS renglones_antes;

DELETE FROM comprobante
WHERE fecha < CURRENT_DATE - INTERVAL '5 years'
  AND id_cliente IN (SELECT id_cliente FROM socio);

SELECT (SELECT COUNT(*) FROM comprobante)         AS comprobantes_despues,
       (SELECT COUNT(*) FROM detalle_comprobante) AS renglones_despues;
ROLLBACK;


-- ---------------------------------------------------------------------
-- D2. Eliminar las cepas que no componen ningún vino ni están plantadas
--     en ninguna parcela.
-- Estrategia: doble NOT EXISTS. Con los datos cargados todas las cepas se
-- usan, así que para ver el efecto primero se agrega una cepa sin uso.
-- ---------------------------------------------------------------------
\echo '=== D2: cepas sin vinos ni parcelas'
BEGIN;
INSERT INTO cepa (nombre, tipo) VALUES ('Cepa de prueba', 'tinta');

DELETE FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM vino_cepa vc WHERE vc.id_cepa = c.id_cepa)
  AND NOT EXISTS (SELECT 1 FROM parcela p    WHERE p.id_cepa = c.id_cepa);

SELECT COUNT(*) AS queda_la_cepa_de_prueba FROM cepa WHERE nombre = 'Cepa de prueba';
ROLLBACK;


-- ---------------------------------------------------------------------
-- D3. La sala de una localidad determinada fue dada de baja: eliminar los
--     empleados de esa sala que trabajaron menos de dos años.
-- Estrategia: subconsulta que busca la sala por el nombre de la localidad
-- y fn_antiguedad_anios (etapa 2) para la antigüedad.
-- ---------------------------------------------------------------------
\echo '=== D3: empleados con menos de 2 años de la sala de Valle Grande'
BEGIN;
SELECT COUNT(*) AS empleados_de_la_sala_antes
FROM empleado
WHERE id_sala IN (SELECT s.id_sala
                  FROM sala_de_ventas s
                  JOIN localidad l ON l.id_localidad = s.id_localidad
                  WHERE l.nombre = 'Valle Grande');

DELETE FROM empleado
WHERE id_sala IN (SELECT s.id_sala
                  FROM sala_de_ventas s
                  JOIN localidad l ON l.id_localidad = s.id_localidad
                  WHERE l.nombre = 'Valle Grande')                  -- <- parámetro: localidad
  AND fn_antiguedad_anios(fecha_ingreso) < 2;

SELECT COUNT(*) AS empleados_de_la_sala_despues
FROM empleado
WHERE id_sala IN (SELECT s.id_sala
                  FROM sala_de_ventas s
                  JOIN localidad l ON l.id_localidad = s.id_localidad
                  WHERE l.nombre = 'Valle Grande');
ROLLBACK;


-- ---------------------------------------------------------------------
-- D4. Borrar los clientes socios que nunca compraron y se dieron de alta
--     hace más de 5 años.
-- Estrategia: IN sobre socio y NOT EXISTS sobre comprobante. La fila de
-- la tabla socio se borra sola por ON DELETE CASCADE.
-- ---------------------------------------------------------------------
\echo '=== D4: socios sin compras dados de alta hace más de 5 años'
BEGIN;
SELECT COUNT(*) AS socios_antes FROM socio;

DELETE FROM cliente c
WHERE c.id_cliente IN (SELECT id_cliente FROM socio)
  AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

SELECT COUNT(*) AS socios_despues FROM socio;
ROLLBACK;


-- ---------------------------------------------------------------------
-- D5. Eliminar los ingresos en estado procesado de hace más de 365 días.
-- Estrategia: DELETE con dos condiciones. Los renglones se borran por
-- CASCADE. El trigger que bloquea los renglones de un documento cerrado
-- (RN-12) deja pasar este caso porque se borra el ingreso completo. El
-- stock del depósito no cambia.
-- ---------------------------------------------------------------------
\echo '=== D5: ingresos procesados de hace más de 365 días'
BEGIN;
SELECT (SELECT COUNT(*) FROM ingreso)         AS ingresos_antes,
       (SELECT COUNT(*) FROM renglon_ingreso) AS renglones_antes,
       (SELECT SUM(cantidad) FROM stock_deposito) AS stock_deposito_antes;

DELETE FROM ingreso
WHERE estado = 'procesado'
  AND fecha < CURRENT_DATE - 365;

SELECT (SELECT COUNT(*) FROM ingreso)         AS ingresos_despues,
       (SELECT COUNT(*) FROM renglon_ingreso) AS renglones_despues,
       (SELECT SUM(cantidad) FROM stock_deposito) AS stock_deposito_despues;
ROLLBACK;


-- ---------------------------------------------------------------------
-- D6. Borrar los clientes socios sin compras que viven en una localidad
--     específica.
-- Estrategia: igual que D4, con la localidad buscada por nombre.
-- ---------------------------------------------------------------------
\echo '=== D6: socios sin compras de Ciudad de San Rafael'
BEGIN;
SELECT COUNT(*) AS clientes_de_la_localidad_antes
FROM cliente
WHERE id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = 'Ciudad de San Rafael');

DELETE FROM cliente c
WHERE c.id_localidad = (SELECT id_localidad FROM localidad
                        WHERE nombre = 'Ciudad de San Rafael')            -- <- parámetro: localidad
  AND c.id_cliente IN (SELECT id_cliente FROM socio)
  AND NOT EXISTS (SELECT 1 FROM comprobante co WHERE co.id_cliente = c.id_cliente);

SELECT COUNT(*) AS clientes_de_la_localidad_despues
FROM cliente
WHERE id_localidad = (SELECT id_localidad FROM localidad WHERE nombre = 'Ciudad de San Rafael');
ROLLBACK;
