-- =====================================================================
-- 007_roles.sql  -  Etapa 2: roles y privilegios mínimos
-- =====================================================================
-- Roles:
--   bodegas_owner     Propietario del esquema y de todos los objetos.
--                     NOLOGIN: un administrador lo usa con SET ROLE.
--   bodegas_api       Rol con el que se conecta la API. Lee todo y
--                     escribe en las tablas de negocio, pero NO puede
--                     escribir stock ni auditoría: eso sólo ocurre a
--                     través de los procedimientos y triggers.
--   bodegas_reportes  Sólo lectura (tablas, vistas y funciones de
--                     consulta).
--
-- Contraseñas: NO se escriben en este archivo. Los roles con LOGIN se
-- crean sin contraseña y un administrador la asigna después desde psql
-- con el comando interactivo (no queda en el historial ni en Git):
--     \password bodegas_api
--     \password bodegas_reportes
--
-- Se ejecuta con un superusuario (en Docker: POSTGRES_USER).
-- Se puede volver a ejecutar: si los roles ya existen, no falla.
-- =====================================================================
SET search_path TO bodegas;


-- ---------------------------------------------------------------------
-- 1. Crear los roles (sólo si no existen; los roles son del servidor,
--    no de la base, por eso pueden existir de una ejecución anterior)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_owner') THEN
        CREATE ROLE bodegas_owner NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_api') THEN
        CREATE ROLE bodegas_api LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_reportes') THEN
        CREATE ROLE bodegas_reportes LOGIN;
    END IF;
END $$;


-- ---------------------------------------------------------------------
-- 2. bodegas_owner pasa a ser el dueño REAL del esquema y de sus objetos
--    (las migraciones las corrió el superusuario, que quedó como dueño).
--    Esto es importante porque los procedimientos y triggers SECURITY
--    DEFINER se ejecutan con los permisos de su dueño: tiene que ser
--    bodegas_owner y no un superusuario.
--    Se recorre el catálogo y se cambia el dueño de cada objeto.
--    (Las secuencias de los SERIAL cambian solas junto con su tabla.)
-- ---------------------------------------------------------------------
ALTER SCHEMA bodegas OWNER TO bodegas_owner;

DO $$
DECLARE
    r RECORD;
BEGIN
    -- Tablas, vistas y vistas materializadas
    FOR r IN SELECT c.relname, c.relkind
             FROM pg_class c
             JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'bodegas' AND c.relkind IN ('r', 'v', 'm')
    LOOP
        IF r.relkind = 'm' THEN
            EXECUTE format('ALTER MATERIALIZED VIEW bodegas.%I OWNER TO bodegas_owner', r.relname);
        ELSIF r.relkind = 'v' THEN
            EXECUTE format('ALTER VIEW bodegas.%I OWNER TO bodegas_owner', r.relname);
        ELSE
            EXECUTE format('ALTER TABLE bodegas.%I OWNER TO bodegas_owner', r.relname);
        END IF;
    END LOOP;

    -- Funciones y procedimientos
    FOR r IN SELECT p.oid::regprocedure AS firma, p.prokind
             FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'bodegas'
    LOOP
        IF r.prokind = 'p' THEN
            EXECUTE format('ALTER PROCEDURE %s OWNER TO bodegas_owner', r.firma);
        ELSE
            EXECUTE format('ALTER FUNCTION %s OWNER TO bodegas_owner', r.firma);
        END IF;
    END LOOP;

    -- Tipos ENUM y dominios
    FOR r IN SELECT t.typname, t.typtype
             FROM pg_type t
             JOIN pg_namespace n ON n.oid = t.typnamespace
             WHERE n.nspname = 'bodegas' AND t.typtype IN ('e', 'd')
    LOOP
        IF r.typtype = 'd' THEN
            EXECUTE format('ALTER DOMAIN bodegas.%I OWNER TO bodegas_owner', r.typname);
        ELSE
            EXECUTE format('ALTER TYPE bodegas.%I OWNER TO bodegas_owner', r.typname);
        END IF;
    END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 3. Quitar los privilegios públicos
--    Por defecto PUBLIC (todos los usuarios) puede ejecutar cualquier
--    función. Se le quita todo y después se otorga sólo lo necesario.
-- ---------------------------------------------------------------------
REVOKE ALL     ON SCHEMA bodegas                  FROM PUBLIC;
REVOKE ALL     ON ALL TABLES    IN SCHEMA bodegas FROM PUBLIC;
REVOKE ALL     ON ALL SEQUENCES IN SCHEMA bodegas FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES  IN SCHEMA bodegas FROM PUBLIC;


-- ---------------------------------------------------------------------
-- 4. bodegas_api: lectura y escritura de las tablas de negocio
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA bodegas TO bodegas_api;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA bodegas TO bodegas_api;

-- Tablas protegidas: sólo lectura para la API.
--   stock_sala / stock_deposito: los modifican sp_procesar_ingreso,
--     sp_procesar_transferencia y los triggers de venta.
--   auditoria_precio: la completa el trigger de RN-13 y nadie la modifica.
REVOKE INSERT, UPDATE, DELETE ON stock_sala, stock_deposito, auditoria_precio FROM bodegas_api;

-- Las vistas son de consulta: sin escritura
REVOKE INSERT, UPDATE, DELETE ON v_stock_total_vino, v_documentos_pendientes FROM bodegas_api;

-- Secuencias de los SERIAL (necesarias para insertar)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA bodegas TO bodegas_api;

-- Sólo las funciones y procedimientos de negocio. Las funciones de los
-- triggers no necesitan EXECUTE: las dispara PostgreSQL.
GRANT EXECUTE ON FUNCTION  fn_total_comprobante(INTEGER),
                           fn_stock_sala(INTEGER, INTEGER),
                           fn_descuento_cliente(INTEGER),
                           fn_antiguedad_anios(DATE)          TO bodegas_api;
GRANT EXECUTE ON PROCEDURE sp_procesar_ingreso(INTEGER),
                           sp_procesar_transferencia(INTEGER) TO bodegas_api;


-- ---------------------------------------------------------------------
-- 5. bodegas_reportes: sólo lectura
-- ---------------------------------------------------------------------
GRANT USAGE  ON SCHEMA bodegas               TO bodegas_reportes;
GRANT SELECT ON ALL TABLES IN SCHEMA bodegas TO bodegas_reportes;   -- incluye vistas

GRANT EXECUTE ON FUNCTION fn_total_comprobante(INTEGER),
                          fn_stock_sala(INTEGER, INTEGER),
                          fn_descuento_cliente(INTEGER),
                          fn_antiguedad_anios(DATE)          TO bodegas_reportes;


-- ---------------------------------------------------------------------
-- 6. Privilegios por defecto para objetos que cree bodegas_owner más
--    adelante (por ejemplo tablas nuevas). Para que se apliquen, las
--    próximas migraciones se ejecutan con:  SET ROLE bodegas_owner;
--    Las funciones nuevas NO quedan ejecutables por PUBLIC.
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE bodegas_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE bodegas_owner IN SCHEMA bodegas
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO bodegas_api;
ALTER DEFAULT PRIVILEGES FOR ROLE bodegas_owner IN SCHEMA bodegas
    GRANT USAGE, SELECT ON SEQUENCES TO bodegas_api;
ALTER DEFAULT PRIVILEGES FOR ROLE bodegas_owner IN SCHEMA bodegas
    GRANT SELECT ON TABLES TO bodegas_reportes;


-- ---------------------------------------------------------------------
-- 7. search_path por defecto: los roles encuentran las tablas del
--    esquema bodegas sin tener que escribir "bodegas." adelante.
-- ---------------------------------------------------------------------
ALTER ROLE bodegas_owner    SET search_path = bodegas;
ALTER ROLE bodegas_api      SET search_path = bodegas;
ALTER ROLE bodegas_reportes SET search_path = bodegas;
