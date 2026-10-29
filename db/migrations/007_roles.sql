SET search_path TO bodegas;
-- 1. Crear los roles (los roles son del servidor, no de la base)
CREATE ROLE bodegas_owner NOLOGIN;
CREATE ROLE bodegas_api LOGIN PASSWORD 'api123';
CREATE ROLE bodegas_reportes LOGIN PASSWORD 'reportes123';

-- 2. Quitar los privilegios públicos
REVOKE ALL     ON SCHEMA bodegas                  FROM PUBLIC;
REVOKE ALL     ON ALL TABLES    IN SCHEMA bodegas FROM PUBLIC;
REVOKE ALL     ON ALL SEQUENCES IN SCHEMA bodegas FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES  IN SCHEMA bodegas FROM PUBLIC;

-- 3. Propietario: todo
GRANT ALL ON SCHEMA bodegas                  TO bodegas_owner;
GRANT ALL ON ALL TABLES    IN SCHEMA bodegas TO bodegas_owner;
GRANT ALL ON ALL SEQUENCES IN SCHEMA bodegas TO bodegas_owner;
GRANT ALL ON ALL ROUTINES  IN SCHEMA bodegas TO bodegas_owner;

-- 4. API: leer y escribir datos, usar secuencias (SERIAL) y ejecutar funciones y procedimientos.
GRANT USAGE                          ON SCHEMA bodegas                  TO bodegas_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA bodegas TO bodegas_api;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA bodegas TO bodegas_api;
GRANT EXECUTE                        ON ALL ROUTINES  IN SCHEMA bodegas TO bodegas_api;

-- 5. Reportes: sólo lectura (tablas, vistas y vista materializada)
GRANT USAGE  ON SCHEMA bodegas               TO bodegas_reportes;
GRANT SELECT ON ALL TABLES IN SCHEMA bodegas TO bodegas_reportes;

-- 6. Objetos que se creen más adelante (por ejemplo, en 008_indices.sql
--    o tablas nuevas) reciben los mismos permisos
ALTER DEFAULT PRIVILEGES IN SCHEMA bodegas
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO bodegas_api;
ALTER DEFAULT PRIVILEGES IN SCHEMA bodegas
    GRANT USAGE, SELECT ON SEQUENCES TO bodegas_api;
ALTER DEFAULT PRIVILEGES IN SCHEMA bodegas
    GRANT EXECUTE ON ROUTINES TO bodegas_api;
ALTER DEFAULT PRIVILEGES IN SCHEMA bodegas
    GRANT SELECT ON TABLES TO bodegas_reportes;