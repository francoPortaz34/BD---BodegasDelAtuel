-- =====================================================================
-- 003_funciones.sql  -  Etapa 2: funciones de negocio
-- =====================================================================
-- Las cuatro funciones son de solo lectura: no modifican datos.
--   STABLE    = lee tablas o la fecha actual; dentro de una misma
--               sentencia devuelve siempre lo mismo para los mismos
--               parámetros.
--   IMMUTABLE = no lee tablas ni la fecha (ninguna de estas lo es).
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- fn_total_comprobante(p_id_comprobante)                        RN-08
-- Propósito : total NETO de un comprobante = suma de los subtotales
--             de sus renglones (cada renglón ya tiene el descuento
--             aplicado).
-- Parámetro : p_id_comprobante  id del comprobante.
-- Devuelve  : NUMERIC(12,2). 0 si el comprobante no tiene renglones.
-- Volatilidad: STABLE (lee detalle_comprobante).
-- Uso       : trigger trg_comprobante_totales (005) y consulta U1.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_id_comprobante INTEGER)
RETURNS NUMERIC(12,2)
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(subtotal_renglon), 0)::NUMERIC(12,2)
    FROM detalle_comprobante
    WHERE id_comprobante = p_id_comprobante;
$$;


-- ---------------------------------------------------------------------
-- fn_stock_sala(p_id_sala, p_id_vino)                           RN-09
-- Propósito : botellas disponibles de un vino en una sala.
-- Parámetros: p_id_sala, p_id_vino.
-- Devuelve  : INTEGER. 0 si la sala no tiene fila de stock para ese
--             vino (nunca devuelve NULL).
-- Volatilidad: STABLE (lee stock_sala).
-- Uso       : trigger de validación de stock en la venta (005).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_sala(p_id_sala INTEGER, p_id_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT cantidad
         FROM stock_sala
         WHERE id_sala = p_id_sala
           AND id_vino = p_id_vino), 0);
$$;


-- ---------------------------------------------------------------------
-- fn_descuento_cliente(p_id_cliente)                            RN-06
-- Propósito : porcentaje de descuento que corresponde al cliente según
--             su tipo (socio 10, distribuidor 20, exportador 30). El
--             valor se toma de tipo_cliente.porcentaje_descuento, así
--             la regla vive en un solo lugar.
-- Parámetro : p_id_cliente.
-- Devuelve  : NUMERIC(5,2), por ejemplo 10.00.
-- Errores   : si el cliente no existe lanza una excepción (no se puede
--             vender a un cliente inexistente).
-- Volatilidad: STABLE (lee cliente y tipo_cliente).
-- Uso       : trigger que completa el renglón de la venta (005).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER)
RETURNS NUMERIC(5,2)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_porcentaje NUMERIC(5,2);
BEGIN
    SELECT tc.porcentaje_descuento
      INTO v_porcentaje
    FROM cliente c
    JOIN tipo_cliente tc ON tc.id_tipo_cliente = c.id_tipo_cliente
    WHERE c.id_cliente = p_id_cliente;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cliente % no existe (RN-06)', p_id_cliente;
    END IF;

    RETURN v_porcentaje;
END;
$$;


-- ---------------------------------------------------------------------
-- fn_antiguedad_anios(p_fecha)
-- Propósito : años completos transcurridos desde una fecha hasta hoy.
--             Sirve para la antigüedad de un empleado (fecha_ingreso),
--             de un cliente (fecha_alta) o de un comprobante (fecha).
--             Ej.: consulta U2 (empleados con más de 5 años).
-- Parámetro : p_fecha  fecha de inicio.
-- Devuelve  : INTEGER.
--             NULL si p_fecha es NULL.
--             0 si p_fecha es futura (todavía no hay antigüedad).
-- Volatilidad: STABLE (depende de CURRENT_DATE, que no cambia dentro de
--             una transacción). No es IMMUTABLE porque mañana el
--             resultado puede ser otro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha DATE)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
               WHEN p_fecha IS NULL         THEN NULL
               WHEN p_fecha > CURRENT_DATE  THEN 0
               ELSE EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha))::INTEGER
           END;
$$;
