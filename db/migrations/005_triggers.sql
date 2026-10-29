SET search_path TO bodegas;

-- RN-13: todo cambio de precio de un vino queda auditado
-- Tipo: AFTER UPDATE (el cambio ya ocurrió, se registra)
CREATE OR REPLACE FUNCTION trg_auditar_precio()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO auditoria_precio (id_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
    VALUES (NEW.id_vino, OLD.precio_venta, NEW.precio_venta, now(), current_user);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_vino_auditoria_precio
AFTER UPDATE OF precio_venta ON vino
FOR EACH ROW
WHEN (OLD.precio_venta IS DISTINCT FROM NEW.precio_venta)
EXECUTE FUNCTION trg_auditar_precio();


-- RN-11: la fecha de confección de una transferencia es la fecha actual y no se puede modificar
-- Tipo: BEFORE INSERT OR UPDATE
CREATE OR REPLACE FUNCTION trg_fecha_confeccion_transferencia()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION 'La fecha de confección de la transferencia % no se puede modificar (RN-11)',
                        OLD.num_solicitud;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_fecha_confeccion_transferencia();


-- RN-10 y RN-11: los estados de ingresos y transferencias sólo avanzan
--  en_confeccion -> terminado -> procesado   (sin saltos ni retrocesos)
-- Tipo: BEFORE UPDATE. Una sola función para las dos tablas.
CREATE OR REPLACE FUNCTION trg_controlar_estado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT ( (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
          OR (OLD.estado = 'terminado'     AND NEW.estado = 'procesado') ) THEN
        RAISE EXCEPTION 'Cambio de estado no permitido en %: % -> % (RN-10/RN-11)',
                        TG_TABLE_NAME, OLD.estado, NEW.estado;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_estado
BEFORE UPDATE OF estado ON ingreso
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION trg_controlar_estado();

CREATE TRIGGER trg_transferencia_estado
BEFORE UPDATE OF estado ON transferencia
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION trg_controlar_estado();


-- RN-12: un ingreso o una transferencia que no está en confección
--  no admite agregar, modificar ni quitar renglones
-- Tipo: BEFORE INSERT OR UPDATE OR DELETE sobre los renglones
CREATE OR REPLACE FUNCTION trg_bloquear_renglon_ingreso()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id     INTEGER;
    v_estado estado_movimiento;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id := OLD.id_ingreso;
    ELSE
        v_id := NEW.id_ingreso;
    END IF;

    SELECT estado INTO v_estado FROM ingreso WHERE id_ingreso = v_id;

    IF v_estado <> 'en_confeccion' THEN
        RAISE EXCEPTION 'El ingreso % está "%": no se pueden cambiar sus renglones (RN-12)',
                        v_id, v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_bloquear_renglon_ingreso();


CREATE OR REPLACE FUNCTION trg_bloquear_renglon_transferencia()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id     INTEGER;
    v_estado estado_movimiento;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id := OLD.id_transferencia;
    ELSE
        v_id := NEW.id_transferencia;
    END IF;

    SELECT estado INTO v_estado FROM transferencia WHERE id_transferencia = v_id;

    IF v_estado <> 'en_confeccion' THEN
        RAISE EXCEPTION 'La transferencia % está "%": no se pueden cambiar sus renglones (RN-12)',
                        v_id, v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_transferencia_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_bloquear_renglon_transferencia();


-- RN-05: los porcentajes de corte de un vino suman exactamente 100
-- Tipo: CONSTRAINT TRIGGER diferido. Se controla al hacer COMMIT, así
--       se pueden cargar todas las cepas del vino dentro de la transacción.
CREATE OR REPLACE FUNCTION trg_validar_porcentajes_corte()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id    INTEGER;
    v_suma  NUMERIC;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id := OLD.id_vino;
    ELSE
        v_id := NEW.id_vino;
    END IF;

    -- Si el vino se borró completo, no hay nada que controlar
    IF NOT EXISTS (SELECT 1 FROM vino WHERE id_vino = v_id) THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(porcentaje_corte), 0) INTO v_suma
    FROM vino_cepa
    WHERE id_vino = v_id;

    IF v_suma <> 100 THEN
        RAISE EXCEPTION 'Los porcentajes de corte del vino % suman % y deben sumar 100 (RN-05)',
                        v_id, v_suma;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_vino_cepa_suma_100
AFTER INSERT OR UPDATE OR DELETE ON vino_cepa
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_porcentajes_corte();