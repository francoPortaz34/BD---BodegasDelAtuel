-- =====================================================================
-- consultas/update.sql  -  Etapa 5: modificación de datos (UPDATE)
-- =====================================================================
-- Cómo ejecutarlo (desde la raíz del repo):
--   docker exec -i bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < consultas/update.sql
--
-- Cada consigna se prueba dentro de una transacción:
--   BEGIN -> consulta de control antes -> UPDATE -> control después -> ROLLBACK
-- Así se ve el efecto y la base queda como estaba.
-- Los parámetros están marcados con "<- parámetro".
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- U1. Recalcular el total de todos los comprobantes aplicando el
--     descuento que corresponde al tipo de cliente.
-- Estrategia: el descuento de cada renglón ya se aplicó al vender (el
-- trigger de la venta usa fn_descuento_cliente, RN-06). Recalcular el
-- comprobante es sumar sus renglones: se usa fn_total_comprobante (etapa 2).
-- Además, el trigger trg_comprobante_totales recalcula también subtotal y
-- descuento en cada UPDATE (RN-08: el total nunca se carga a mano).
-- Como los triggers ya mantienen los totales al día, el control da 0
-- comprobantes mal calculados antes y después.
-- ---------------------------------------------------------------------
\echo '=== U1: recalcular el total de todos los comprobantes'
BEGIN;
SELECT COUNT(*) AS mal_calculados_antes
FROM comprobante c
WHERE c.total <> fn_total_comprobante(c.id_comprobante);

UPDATE comprobante
SET total = fn_total_comprobante(id_comprobante);

SELECT COUNT(*) AS mal_calculados_despues
FROM comprobante c
WHERE c.total <> fn_total_comprobante(c.id_comprobante);
ROLLBACK;


-- ---------------------------------------------------------------------
-- U2. Aumentar un 20 % el salario de los empleados con más de 5 años de
--     antigüedad.
-- Estrategia: la antigüedad se calcula con fn_antiguedad_anios (etapa 2),
-- que cuenta años completos desde la fecha de ingreso hasta hoy.
-- ---------------------------------------------------------------------
\echo '=== U2: +20 % de salario a los empleados con más de 5 años'
BEGIN;
SELECT COUNT(*) AS empleados, SUM(salario) AS total_salarios_antes
FROM empleado
WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

UPDATE empleado
SET salario = ROUND(salario * 1.20, 2)
WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

SELECT COUNT(*) AS empleados, SUM(salario) AS total_salarios_despues
FROM empleado
WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
ROLLBACK;


-- ---------------------------------------------------------------------
-- U3. Incrementar un 13 % el precio de los vinos elaborados por una
--     bodega determinada.
-- Estrategia: subconsulta escalar que busca el id de la bodega por su
-- nombre. Cada cambio de precio dispara el trigger de auditoría (RN-13):
-- se ve cómo aumentan las filas de auditoria_precio.
-- ---------------------------------------------------------------------
\echo '=== U3: +13 % al precio de los vinos de Bodega Campos'
BEGIN;
SELECT COUNT(*) AS filas_auditoria_antes FROM auditoria_precio;

UPDATE vino
SET precio_venta = ROUND(precio_venta * 1.13, 2)
WHERE id_bodega = (SELECT id_bodega
                   FROM bodega
                   WHERE razon_social = 'Bodega Campos');   -- <- parámetro: bodega

SELECT COUNT(*) AS filas_auditoria_despues FROM auditoria_precio;
SELECT cod_vino, nombre_comercial, precio_venta
FROM vino
WHERE id_bodega = (SELECT id_bodega FROM bodega WHERE razon_social = 'Bodega Campos')
ORDER BY cod_vino
LIMIT 5;
ROLLBACK;


-- ---------------------------------------------------------------------
-- U4. En las salas cuyo día de cierre es lunes cambiarlo a miércoles y
--     viceversa, en una sola sentencia.
-- Estrategia: un UPDATE con CASE (elige un valor según una condición).
-- Funciona en una sola sentencia porque el UPDATE evalúa todas las filas
-- con los valores que tenían ANTES de empezar: una sala que pasa de lunes a
-- miércoles no vuelve a cambiar a lunes. Con dos UPDATE separados, el
-- segundo desharía lo que hizo el primero.
-- El ::dia_semana convierte el texto al tipo ENUM de la columna.
-- ---------------------------------------------------------------------
\echo '=== U4: intercambiar el día de cierre lunes <-> miércoles'
BEGIN;
SELECT dia_cierre_semanal, COUNT(*) AS salas_antes
FROM sala_de_ventas
WHERE dia_cierre_semanal IN ('lunes', 'miercoles')
GROUP BY dia_cierre_semanal;

UPDATE sala_de_ventas
SET dia_cierre_semanal = CASE dia_cierre_semanal
                             WHEN 'lunes'     THEN 'miercoles'::dia_semana
                             WHEN 'miercoles' THEN 'lunes'::dia_semana
                         END
WHERE dia_cierre_semanal IN ('lunes', 'miercoles');

SELECT dia_cierre_semanal, COUNT(*) AS salas_despues
FROM sala_de_ventas
WHERE dia_cierre_semanal IN ('lunes', 'miercoles')
GROUP BY dia_cierre_semanal;
ROLLBACK;


-- ---------------------------------------------------------------------
-- U5. Aplicar un 15 % de descuento de precio a los 10 vinos menos
--     vendidos de toda la red.
-- Estrategia: subconsulta con IN que arma el ranking (GROUP BY y SUM de
-- botellas, orden ascendente, LIMIT 10) y UPDATE de esos vinos.
-- Decisión: se toman los 10 menos vendidos ENTRE LOS QUE TUVIERON VENTAS.
-- Hay vinos que nunca se vendieron: si se incluyeran (con LEFT JOIN y
-- COALESCE(SUM(...), 0)), los 10 saldrían al azar entre todos los empatados en 0.
-- Los cambios de precio también quedan auditados (RN-13).
-- ---------------------------------------------------------------------
\echo '=== U5: -15 % al precio de los 10 vinos menos vendidos'
BEGIN;
SELECT v.cod_vino, v.precio_venta AS precio_antes, SUM(d.cantidad) AS botellas
FROM vino v
JOIN detalle_comprobante d ON d.id_vino = v.id_vino
GROUP BY v.id_vino, v.cod_vino, v.precio_venta
ORDER BY botellas, v.id_vino
LIMIT 10;

UPDATE vino
SET precio_venta = ROUND(precio_venta * 0.85, 2)
WHERE id_vino IN (SELECT d.id_vino
                  FROM detalle_comprobante d
                  GROUP BY d.id_vino
                  ORDER BY SUM(d.cantidad), d.id_vino
                  LIMIT 10);

SELECT v.cod_vino, v.precio_venta AS precio_despues, SUM(d.cantidad) AS botellas
FROM vino v
JOIN detalle_comprobante d ON d.id_vino = v.id_vino
GROUP BY v.id_vino, v.cod_vino, v.precio_venta
ORDER BY botellas, v.id_vino
LIMIT 10;
ROLLBACK;


-- ---------------------------------------------------------------------
-- U6. A los exportadores con más de 3 permisos de exportación, subirles
--     el descuento al 35 %.
-- Estrategia: en el modelo, el descuento es del TIPO de cliente
-- (tipo_cliente.porcentaje_descuento), no de cada cliente. Cambiar el tipo
-- Exportador a 35 % afectaría a todos los exportadores. Por eso:
--   1. Se crea el tipo "Exportador Premium" con 35 %.
--   2. Se pasa a ese tipo a los exportadores con más de 3 permisos
--      (subconsulta con GROUP BY y HAVING).
-- Siguen siendo exportadores (su fila en la tabla exportador no cambia).
-- Desde ese momento, fn_descuento_cliente devuelve 35 y el trigger de
-- venta les aplica ese descuento en las compras nuevas. Las ventas
-- anteriores conservan el descuento con el que se hicieron.
-- ---------------------------------------------------------------------
\echo '=== U6: exportadores con más de 3 permisos pasan al 35 %'
BEGIN;
INSERT INTO tipo_cliente (nombre, porcentaje_descuento)
VALUES ('Exportador Premium', 35);

UPDATE cliente
SET id_tipo_cliente = (SELECT id_tipo_cliente
                       FROM tipo_cliente
                       WHERE nombre = 'Exportador Premium')
WHERE id_cliente IN (SELECT id_cliente
                     FROM permiso_exportacion
                     GROUP BY id_cliente
                     HAVING COUNT(*) > 3);

SELECT t.nombre AS tipo, t.porcentaje_descuento, COUNT(*) AS clientes
FROM cliente c
JOIN tipo_cliente t ON t.id_tipo_cliente = c.id_tipo_cliente
GROUP BY t.nombre, t.porcentaje_descuento
ORDER BY t.porcentaje_descuento;
ROLLBACK;
