-- =====================================================================
-- 005_triggers.sql  -  Etapa 2: triggers
-- =====================================================================
-- Resumen (tabla -> trigger -> momento -> regla)
--   vino                  trg_vino_auditoria_precio      AFTER UPDATE          RN-13
--   transferencia        trg_transferencia_fecha        BEFORE INSERT/UPDATE  RN-11
--   ingreso               trg_ingreso_estado             BEFORE INSERT/UPDATE  RN-10
--   transferencia         trg_transferencia_estado       BEFORE INSERT/UPDATE  RN-11
--   renglon_ingreso       trg_renglon_ingreso_bloqueo    BEFORE I/U/D          RN-12
--   renglon_transferencia trg_renglon_transferencia_bloqueo BEFORE I/U/D       RN-12
--   vino_cepa             trg_vino_cepa_suma_100         CONSTRAINT DEFERRED   RN-05
--   detalle_comprobante   trg_detalle_validar            BEFORE INSERT/UPDATE  RN-09, RN-06, RN-01
--   detalle_comprobante   trg_detalle_actualizar         AFTER I/U/D           RN-09, RN-08
--   comprobante           trg_comprobante_totales        BEFORE INSERT/UPDATE  RN-08
-- =====================================================================
SET search_path TO bodegas;


-- =====================================================================
-- RN-13: todo cambio de precio de un vino queda auditado
-- Tipo: AFTER UPDATE (el cambio ya ocurrió; se registra)
-- SECURITY DEFINER: el rol de la API no tiene permiso de escritura sobre
-- auditoria_precio; la inserción la hace el trigger con permisos del
-- propietario. Por eso el usuario se toma de session_user (el usuario
-- que se conectó), no de current_user (que acá sería el propietario).
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_auditar_precio()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
BEGIN
    INSERT INTO auditoria_precio (id_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
    VALUES (NEW.id_vino, OLD.precio_venta, NEW.precio_venta, now(), session_user);
    RETURN NULL;   -- en un trigger AFTER el valor de retorno se ignora
END;
$$;

CREATE TRIGGER trg_vino_auditoria_precio
AFTER UPDATE OF precio_venta ON vino
FOR EACH ROW
WHEN (OLD.precio_venta IS DISTINCT FROM NEW.precio_venta)
EXECUTE FUNCTION trg_auditar_precio();
-- La auditoría no se puede modificar ni borrar desde la API: 007_roles.sql
-- le da a bodegas_api solo SELECT sobre auditoria_precio.


-- =====================================================================
-- RN-11: la fecha de confección de una transferencia es la fecha actual
-- y no se puede modificar
-- Tipo: BEFORE INSERT OR UPDATE
--   INSERT: se pisa la fecha recibida con CURRENT_DATE.
--   UPDATE: si se intenta cambiar la fecha, se rechaza.
-- =====================================================================
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


-- =====================================================================
-- RN-10 y RN-11: control de estados de ingresos y transferencias
-- Tipo: BEFORE INSERT OR UPDATE OF estado. Una sola función para las
-- dos tablas (las dos tienen la columna estado).
--   INSERT: un documento nuevo sólo puede nacer 'en_confeccion'.
--   UPDATE: sólo  en_confeccion -> terminado -> procesado
--           (sin saltos ni retrocesos).
--   Pasar a 'procesado' sólo se permite desde sp_procesar_ingreso /
--   sp_procesar_transferencia: esos procedimientos son SECURITY DEFINER
--   y corren como el dueño de la tabla. Si quien hace el UPDATE no es el
--   dueño de la tabla, se rechaza. Así nadie puede marcar un documento
--   como procesado sin que se haya movido el stock.
--   (TG_RELID es el oid de la tabla que disparó el trigger.)
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_controlar_estado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_duenio NAME;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'Todo documento nuevo (%) debe crearse en estado en_confeccion, no "%" (RN-10/RN-11)',
                            TG_TABLE_NAME, NEW.estado;
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE sin cambio de estado: no hay nada que controlar
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF NOT ( (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
          OR (OLD.estado = 'terminado'     AND NEW.estado = 'procesado') ) THEN
        RAISE EXCEPTION 'Cambio de estado no permitido en %: % -> % (RN-10/RN-11)',
                        TG_TABLE_NAME, OLD.estado, NEW.estado;
    END IF;

    IF NEW.estado = 'procesado' THEN
        SELECT pg_get_userbyid(relowner) INTO v_duenio
        FROM pg_class
        WHERE oid = TG_RELID;

        IF current_user <> v_duenio THEN
            RAISE EXCEPTION 'Un documento (%) sólo puede pasar a procesado con CALL sp_procesar_% (RN-10/RN-11)',
                            TG_TABLE_NAME, TG_TABLE_NAME;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_estado
BEFORE INSERT OR UPDATE OF estado ON ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_controlar_estado();

CREATE TRIGGER trg_transferencia_estado
BEFORE INSERT OR UPDATE OF estado ON transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_controlar_estado();


-- =====================================================================
-- RN-12: un ingreso o una transferencia que no está en confección no
-- admite agregar, modificar ni quitar renglones
-- Tipo: BEFORE INSERT OR UPDATE OR DELETE sobre los renglones
--   * INSERT: se mira la cabecera nueva (NEW).
--   * DELETE: se mira la cabecera vieja (OLD).
--   * UPDATE: se miran las dos (por si se mueve el renglón de documento).
--   Si la cabecera ya no existe es porque se está borrando el documento
--   completo (ON DELETE CASCADE, por ejemplo la consulta D5): en ese caso
--   no hay nada que bloquear.
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_bloquear_renglon_ingreso()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_movimiento;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT estado INTO v_estado FROM ingreso WHERE id_ingreso = OLD.id_ingreso;
        IF FOUND AND v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'El ingreso % está "%": no se pueden cambiar sus renglones (RN-12)',
                            OLD.id_ingreso, v_estado;
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT estado INTO v_estado FROM ingreso WHERE id_ingreso = NEW.id_ingreso;
        IF FOUND AND v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'El ingreso % está "%": no se pueden cambiar sus renglones (RN-12)',
                            NEW.id_ingreso, v_estado;
        END IF;
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
    v_estado estado_movimiento;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT estado INTO v_estado FROM transferencia WHERE id_transferencia = OLD.id_transferencia;
        IF FOUND AND v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'La transferencia % está "%": no se pueden cambiar sus renglones (RN-12)',
                            OLD.id_transferencia, v_estado;
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT estado INTO v_estado FROM transferencia WHERE id_transferencia = NEW.id_transferencia;
        IF FOUND AND v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'La transferencia % está "%": no se pueden cambiar sus renglones (RN-12)',
                            NEW.id_transferencia, v_estado;
        END IF;
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


-- =====================================================================
-- RN-05: los porcentajes de corte de un vino suman exactamente 100
-- Tipo: CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED.
-- Se controla al hacer COMMIT (o con SET CONSTRAINTS ... IMMEDIATE), así
-- se pueden cargar el vino y todas sus cepas dentro de la transacción.
-- Se dispara en vino_cepa al agregar, cambiar o quitar una cepa.
-- En un UPDATE de vino_cepa se controlan el vino viejo y el nuevo.
-- Si el vino ya no existe (se borró, y su composición con él por
-- CASCADE) no hay nada que controlar.
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_validar_porcentajes_corte()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_vinos INTEGER[] := '{}';
    v_id    INTEGER;
    v_suma  NUMERIC;
BEGIN
    IF TG_OP <> 'DELETE' THEN
        v_vinos := v_vinos || NEW.id_vino;
    END IF;
    IF TG_OP <> 'INSERT' THEN
        v_vinos := v_vinos || OLD.id_vino;
    END IF;

    FOREACH v_id IN ARRAY v_vinos LOOP
        IF EXISTS (SELECT 1 FROM vino WHERE id_vino = v_id) THEN
            SELECT COALESCE(SUM(porcentaje_corte), 0) INTO v_suma
            FROM vino_cepa
            WHERE id_vino = v_id;

            IF v_suma <> 100 THEN
                RAISE EXCEPTION 'Los porcentajes de corte del vino % suman % y deben sumar 100 (RN-05)',
                                v_id, v_suma;
            END IF;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_vino_cepa_suma_100
AFTER INSERT OR UPDATE OR DELETE ON vino_cepa
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_porcentajes_corte();


-- =====================================================================
-- RN-09 (y RN-01, RN-06): validación del renglón de venta
-- Tipo: BEFORE INSERT OR UPDATE en detalle_comprobante
--   1. Completa los datos derivados (no se cargan a mano):
--        precio_unitario_venta = precio vigente del vino (RN-01: un único
--                                precio para toda la red),
--        descuento_aplicado    = fn_descuento_cliente (RN-06),
--        subtotal_renglon      = cantidad * precio * (1 - descuento/100).
--      En un UPDATE el precio queda congelado (es el del momento de la
--      venta) y sólo se puede cambiar la cantidad.
--   2. Controla que haya stock suficiente en la sala (RN-09). Antes de
--      leer el stock BLOQUEA la fila con FOR UPDATE: si dos sesiones
--      venden el mismo vino en la misma sala a la vez, la segunda espera
--      a que la primera termine y recién entonces lee el stock real.
-- SECURITY DEFINER: FOR UPDATE exige permiso de escritura sobre
-- stock_sala, que el rol de la API no tiene.
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_validar_renglon_venta()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
    v_sala      INTEGER;
    v_cliente   INTEGER;
    v_necesario INTEGER;
BEGIN
    SELECT id_sala, id_cliente INTO v_sala, v_cliente
    FROM comprobante
    WHERE id_comprobante = NEW.id_comprobante;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El comprobante % no existe', NEW.id_comprobante;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT precio_venta INTO NEW.precio_unitario_venta
        FROM vino
        WHERE id_vino = NEW.id_vino;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'El vino % no existe', NEW.id_vino;
        END IF;

        v_necesario := NEW.cantidad;
    ELSE
        IF NEW.id_comprobante <> OLD.id_comprobante OR NEW.id_vino <> OLD.id_vino THEN
            RAISE EXCEPTION 'No se puede cambiar el comprobante ni el vino de un renglón: bórrelo y cárguelo de nuevo (RN-08)';
        END IF;

        NEW.precio_unitario_venta := OLD.precio_unitario_venta;
        v_necesario := NEW.cantidad - OLD.cantidad;   -- botellas adicionales
    END IF;

    NEW.descuento_aplicado := fn_descuento_cliente(v_cliente);

    -- RN-09: bloquear la fila de stock y controlar que alcance
    IF v_necesario > 0 THEN
        PERFORM 1
        FROM stock_sala
        WHERE id_sala = v_sala AND id_vino = NEW.id_vino
        FOR UPDATE;

        IF fn_stock_sala(v_sala, NEW.id_vino) < v_necesario THEN
            RAISE EXCEPTION 'Stock insuficiente del vino % en la sala %: disponible %, solicitado % (RN-09)',
                            NEW.id_vino, v_sala, fn_stock_sala(v_sala, NEW.id_vino), v_necesario;
        END IF;
    END IF;

    NEW.subtotal_renglon := ROUND(NEW.cantidad * NEW.precio_unitario_venta
                                  * (1 - NEW.descuento_aplicado / 100), 2);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_detalle_validar
BEFORE INSERT OR UPDATE ON detalle_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_validar_renglon_venta();


-- =====================================================================
-- RN-09 y RN-08: actualización de stock y totales después de la venta
-- Tipo: AFTER INSERT OR UPDATE OR DELETE en detalle_comprobante
--   INSERT: descuenta del stock de la sala.
--   UPDATE: descuenta (o devuelve) la diferencia de cantidad.
--   DELETE de un renglón: devuelve las botellas a la sala (se anuló
--          parte de la venta).
--   En los tres casos recalcula los importes del comprobante.
--   Si el comprobante ya no existe es porque se está borrando el
--   comprobante completo (CASCADE, depuración de historial como la
--   consulta D1): ahí no se toca el stock.
-- SECURITY DEFINER: el rol de la API no puede escribir stock_sala.
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_actualizar_stock_y_totales()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bodegas, pg_temp
AS $$
DECLARE
    v_id_comprobante INTEGER;
    v_sala           INTEGER;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id_comprobante := OLD.id_comprobante;
    ELSE
        v_id_comprobante := NEW.id_comprobante;
    END IF;

    SELECT id_sala INTO v_sala
    FROM comprobante
    WHERE id_comprobante = v_id_comprobante;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'INSERT' THEN
        UPDATE stock_sala SET cantidad = cantidad - NEW.cantidad
        WHERE id_sala = v_sala AND id_vino = NEW.id_vino;
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE stock_sala SET cantidad = cantidad - (NEW.cantidad - OLD.cantidad)
        WHERE id_sala = v_sala AND id_vino = NEW.id_vino;
    ELSE
        UPDATE stock_sala SET cantidad = cantidad + OLD.cantidad
        WHERE id_sala = v_sala AND id_vino = OLD.id_vino;
    END IF;

    -- El trigger trg_comprobante_totales completa subtotal y descuento
    UPDATE comprobante
    SET total = fn_total_comprobante(v_id_comprobante)
    WHERE id_comprobante = v_id_comprobante;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_detalle_actualizar
AFTER INSERT OR UPDATE OR DELETE ON detalle_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_stock_y_totales();


-- =====================================================================
-- RN-08: los importes del comprobante no se cargan a mano
-- Tipo: BEFORE INSERT OR UPDATE en comprobante
-- Cualquier valor que se intente poner en subtotal, descuento o total se
-- reemplaza por el calculado a partir de los renglones:
--   subtotal  = suma de cantidad * precio_unitario_venta
--   total     = fn_total_comprobante (suma de subtotales con descuento)
--   descuento = subtotal - total
-- Al insertar, todavía no hay renglones: los tres quedan en 0.
-- Además impide cambiar la sala o el cliente de un comprobante que ya
-- tiene renglones (el stock ya se descontó de esa sala y el descuento
-- es el de ese cliente).
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_calcular_totales_comprobante()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE'
       AND (NEW.id_sala <> OLD.id_sala OR NEW.id_cliente <> OLD.id_cliente)
       AND EXISTS (SELECT 1 FROM detalle_comprobante WHERE id_comprobante = OLD.id_comprobante) THEN
        RAISE EXCEPTION 'No se puede cambiar la sala ni el cliente del comprobante % porque ya tiene renglones (RN-08)',
                        OLD.num_comprobante;
    END IF;

    SELECT COALESCE(SUM(cantidad * precio_unitario_venta), 0)
      INTO NEW.subtotal
    FROM detalle_comprobante
    WHERE id_comprobante = NEW.id_comprobante;

    NEW.total     := fn_total_comprobante(NEW.id_comprobante);
    NEW.descuento := NEW.subtotal - NEW.total;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_totales
BEFORE INSERT OR UPDATE ON comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_calcular_totales_comprobante();
