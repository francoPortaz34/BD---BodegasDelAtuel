#!/usr/bin/env bash
# =====================================================================
# etapa4.sh  -  Ejecuta TODAS las mediciones de la etapa 4 de una vez.
# Requisitos: contenedor bodegas_atuel_db levantado y con la carga
# masiva hecha (migraciones 001-007 + datos de la etapa 3).
# Uso (Git Bash, desde la carpeta del repo):
#     bash db/rendimiento/etapa4.sh
# Deja los resultados en docs/etapa4/.
# =====================================================================
set -e
export MSYS_NO_PATHCONV=1          # que Git Bash no cambie las rutas /db/...
CONTENEDOR=bodegas_atuel_db
SALIDA=docs/etapa4
mkdir -p "$SALIDA"

psql_c() {   # ejecuta psql dentro del contenedor con el usuario y la base del .env
    docker exec "$CONTENEDOR" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 "$@"' psql "$@"
}

echo "1) Controlando que haya datos..."
FILAS=$(psql_c -Atc "SELECT count(*) FROM bodegas.detalle_comprobante;")
echo "   detalle_comprobante: $FILAS filas"
if [ "$FILAS" -lt 100000 ]; then
    echo "   ERROR: faltan datos. Primero hay que hacer la carga masiva (etapa 3)." >&2
    exit 1
fi

echo "2) Midiendo ANTES de los índices (paso 2)..."
psql_c -qc "DROP INDEX IF EXISTS bodegas.idx_comprobante_cliente, bodegas.idx_detalle_vino,
            bodegas.idx_comprobante_sala_fecha, bodegas.idx_comprobante_fecha_cubriente,
            bodegas.idx_transferencia_pendiente, bodegas.idx_renglon_transf_vino;"
psql_c -qc "VACUUM ANALYZE;"
psql_c -f /db/rendimiento/medir.sql > "$SALIDA/antes.txt"

echo "3) Creando los índices (008_indices.sql)..."
psql_c -q -f /db/migrations/008_indices.sql
psql_c -qc "VACUUM ANALYZE;"

echo "4) Midiendo DESPUÉS de los índices (paso 5)..."
psql_c -f /db/rendimiento/medir.sql > "$SALIDA/despues.txt"

echo "5) Índices no usados y descartado (pasos 6 y 8)..."
psql_c -f /db/rendimiento/indices_no_usados.sql > "$SALIDA/indices_no_usados.txt"

echo "6) Costo de escritura (paso 7)..."
psql_c -f /db/rendimiento/costo_escritura.sql > "$SALIDA/costo_escritura.txt"

echo
echo "================ RESUMEN ================"
printf "%-9s %-14s %-14s\n" "Consulta" "Antes" "Después"
paste -d'|' <(printf "S3\nS4\nS8\nS12\n") \
      <(grep "Execution Time" "$SALIDA/antes.txt"   | awk '{print $3, $4}') \
      <(grep "Execution Time" "$SALIDA/despues.txt" | awk '{print $3, $4}') |
    while IFS='|' read -r c a d; do printf "%-9s %-14s %-14s\n" "$c" "$a" "$d"; done
echo
echo "Costo de escritura (tiempos del INSERT sin y con índices):"
grep -E "^Time:" "$SALIDA/costo_escritura.txt" | sed -n '2p;6p'
echo
echo "Resultados completos en $SALIDA/"
