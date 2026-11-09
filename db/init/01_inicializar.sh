#!/bin/sh
# ---------------------------------------------------------------------
# Inicialización automática de la base (para que "docker compose up"
# deje todo funcionando en una instalación limpia).
#
# La imagen oficial de PostgreSQL ejecuta los scripts de
# /docker-entrypoint-initdb.d SOLO cuando el volumen de datos está vacío
# (primer arranque). Si el volumen ya tiene una base, este script NO se
# ejecuta y los datos existentes no se tocan.
#
# Pasos (no modifica migraciones ni el dump, solo los usa):
#   1. Crea los roles (el dump les asigna objetos, pero no los crea).
#   2. Restaura dump_completo.sql.gz (esquema, datos, triggers, índices, permisos).
#   3. Ejecuta 007_roles.sql: el dump no guarda el search_path de los roles
#      y la API lo necesita. La 007 se puede ejecutar más de una vez.
#   4. Asigna la contraseña de bodegas_api desde la variable API_DB_PASSWORD
#      (viene del .env; no queda escrita en ningún archivo del repositorio).
#   5. ANALYZE para que el planificador tenga estadísticas.
# ---------------------------------------------------------------------
set -e

psql_base() {
    psql -v ON_ERROR_STOP=1 -q --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" "$@"
}

echo ">> [1/5] Creando los roles"
psql_base <<'SQL'
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
SQL

echo ">> [2/5] Restaurando dump_completo.sql.gz (puede tardar unos minutos)"
gunzip -c /dump/dump_completo.sql.gz | psql_base

echo ">> [3/5] Aplicando 007_roles.sql (privilegios y search_path de los roles)"
psql_base -f /db/migrations/007_roles.sql

echo ">> [4/5] Contraseña de bodegas_api"
if [ -n "$API_DB_PASSWORD" ]; then
    # :'clave' hace que psql la escriba como texto entre comillas (escapada)
    psql_base -v clave="$API_DB_PASSWORD" <<'SQL'
ALTER ROLE bodegas_api PASSWORD :'clave';
SQL
else
    echo "   AVISO: API_DB_PASSWORD está vacía; bodegas_api queda sin contraseña y la API no podrá conectarse."
fi

echo ">> [5/5] ANALYZE"
psql_base -c "ANALYZE"

echo ">> Inicialización terminada"
