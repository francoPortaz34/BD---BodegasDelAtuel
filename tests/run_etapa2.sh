#!/bin/sh
# ---------------------------------------------------------------------
# Recrea una base de PRUEBAS desde cero, aplica las migraciones 001 a
# 007 y ejecuta tests/db_tests.sql. Se ejecuta DENTRO del contenedor:
#
#   docker exec bodegas_atuel_db sh /tests/run_etapa2.sh            (base bodegas_test)
#   docker exec bodegas_atuel_db sh /tests/run_etapa2.sh otra_base
#
# Por seguridad se niega a usar la base principal ($POSTGRES_DB),
# porque la borra y la vuelve a crear.
# ---------------------------------------------------------------------
set -e

DB="${1:-bodegas_test}"
U="${POSTGRES_USER}"

if [ "$DB" = "$POSTGRES_DB" ]; then
    echo "ERROR: no se usa la base principal ($POSTGRES_DB) para las pruebas." >&2
    exit 1
fi

echo ">> Recreando la base $DB"
psql -v ON_ERROR_STOP=1 -q -U "$U" -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"

for f in /db/migrations/00[1-7]_*.sql; do
    echo ">> Aplicando $f"
    psql -v ON_ERROR_STOP=1 -q -U "$U" -d "$DB" -f "$f"
done

echo ">> Ejecutando /tests/db_tests.sql"
psql -v ON_ERROR_STOP=1 -q -U "$U" -d "$DB" -f /tests/db_tests.sql
