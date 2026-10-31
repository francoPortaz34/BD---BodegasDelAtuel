-- =====================================================================
-- 004_procedimientos.sql  -  Etapa 2: procedimientos transaccionales
-- =====================================================================
-- Ambos procedimientos siguen los mismos pasos:
--   1. Bloquean la cabecera con SELECT ... FOR UPDATE. Si otra sesión
--      intenta procesar el mismo documento, espera; cuando entra ve el
--      estado 'procesado' y se rechaza (no se procesa dos veces).
--   2. Validan: que exista, que esté 'terminado' y que tenga renglones.
--   3. Modifican los stocks.
--   4. Pasan la cabecera a 'procesado'.
--
-- Atomicidad: un CALL es una sola sentencia. Si cualquier paso lanza un
-- error, PostgreSQL revierte TODO lo que hizo el procedimiento (y la
-- transacción que lo contiene). No queda ningún cambio a medias.
-- Los procedimientos no hacen COMMIT: así se pueden usar dentro de una
-- transacción más grande de la API.
--
-- SECURITY DEFINER: se ejecutan con los permisos del propietario
-- (bodegas_owner, ver 007_roles.sql). El rol de la API no puede escribir
-- directamente stock_deposito ni stock_sala; sólo puede hacerlo a
-- través de estos procedimientos. "SET search_path" fija el esquema para
-- que nadie pueda reemplazar las tablas con otras de su propio esquema.
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- sp_procesar_ingreso(p_id_ingreso)                              RN-10
-- Suma las botellas del ingreso al stock del depósito central y pasa el
-- ingreso de 'terminado' a 'procesado'.
-- Uso: CALL sp_procesar_ingreso(15);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_id_ingreso INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
    v_estado estado_movimiento;
BEGIN
    -- 1. Bloquear la cabecera
    SELECT estado INTO v_estado
    FROM ingreso
    WHERE id_ingreso = p_id_ingreso
    FOR UPDATE;

    -- 2. Validaciones
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ingreso % no existe (RN-10)', p_id_ingreso;
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'El ingreso % está "%": sólo se puede procesar un ingreso terminado (RN-10)',
                        p_id_ingreso, v_estado;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM renglon_ingreso WHERE id_ingreso = p_id_ingreso) THEN
        RAISE EXCEPTION 'El ingreso % no tiene renglones (RN-10)', p_id_ingreso;
    END IF;

    -- 3. Sumar al depósito central. Si el vino todavía no tiene fila de
    --    stock, se crea; si ya la tiene, se suma la cantidad.
    INSERT INTO stock_deposito (id_vino, cantidad)
    SELECT id_vino, cantidad_botellas
    FROM renglon_ingreso
    WHERE id_ingreso = p_id_ingreso
    ON CONFLICT (id_vino)
    DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;

    -- 4. Cambiar el estado (el trigger trg_ingreso_estado valida la transición)
    UPDATE ingreso
    SET estado = 'procesado'
    WHERE id_ingreso = p_id_ingreso;
END;
$$;


-- ---------------------------------------------------------------------
-- sp_procesar_transferencia(p_id_transferencia)            RN-11, RN-09
-- Descuenta las botellas del depósito central, las suma al stock de la
-- sala solicitante y pasa la transferencia a 'procesado'.
-- Si el depósito no tiene stock suficiente para ALGÚN renglón, no se
-- mueve nada.
-- Uso: CALL sp_procesar_transferencia(42);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_id_transferencia INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
    v_estado   estado_movimiento;
    v_sala     INTEGER;
    v_faltante RECORD;
BEGIN
    -- 1. Bloquear la cabecera
    SELECT estado, id_sala INTO v_estado, v_sala
    FROM transferencia
    WHERE id_transferencia = p_id_transferencia
    FOR UPDATE;

    -- 2. Validaciones
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La transferencia % no existe (RN-11)', p_id_transferencia;
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'La transferencia % está "%": sólo se puede procesar una transferencia terminada (RN-11)',
                        p_id_transferencia, v_estado;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM renglon_transferencia WHERE id_transferencia = p_id_transferencia) THEN
        RAISE EXCEPTION 'La transferencia % no tiene renglones (RN-11)', p_id_transferencia;
    END IF;

    -- 3. Bloquear el stock del depósito de los vinos pedidos, para que
    --    nadie lo cambie entre el control y el descuento. Se bloquea
    --    siempre en el mismo orden (id_vino) para evitar deadlocks.
    PERFORM 1
    FROM stock_deposito d
    JOIN renglon_transferencia r ON r.id_vino = d.id_vino
    WHERE r.id_transferencia = p_id_transferencia
    ORDER BY d.id_vino
    FOR UPDATE OF d;

    -- 4. Controlar stock suficiente. El LEFT JOIN detecta también el
    --    vino que no tiene fila en stock_deposito (disponible = 0).
    SELECT r.id_vino,
           r.cantidad_botellas       AS solicitado,
           COALESCE(d.cantidad, 0)   AS disponible
      INTO v_faltante
    FROM renglon_transferencia r
    LEFT JOIN stock_deposito d ON d.id_vino = r.id_vino
    WHERE r.id_transferencia = p_id_transferencia
      AND COALESCE(d.cantidad, 0) < r.cantidad_botellas
    ORDER BY r.id_vino
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Stock insuficiente en el depósito central para el vino %: disponible %, solicitado % (RN-09/RN-11)',
                        v_faltante.id_vino, v_faltante.disponible, v_faltante.solicitado;
    END IF;

    -- 5. Descontar del depósito central
    UPDATE stock_deposito d
    SET cantidad = d.cantidad - r.cantidad_botellas
    FROM renglon_transferencia r
    WHERE r.id_transferencia = p_id_transferencia
      AND d.id_vino = r.id_vino;

    -- 6. Sumar al stock de la sala (crea la fila si no existía)
    INSERT INTO stock_sala (id_sala, id_vino, cantidad)
    SELECT v_sala, id_vino, cantidad_botellas
    FROM renglon_transferencia
    WHERE id_transferencia = p_id_transferencia
    ON CONFLICT (id_sala, id_vino)
    DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;

    -- 7. Cambiar el estado (el trigger trg_transferencia_estado valida la transición)
    UPDATE transferencia
    SET estado = 'procesado'
    WHERE id_transferencia = p_id_transferencia;
END;
$$;
