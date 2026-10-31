#!/bin/sh
# ---------------------------------------------------------------------
# Ejecuta la demostración de concurrencia con DOS conexiones psql
# independientes que corren al mismo tiempo (A en segundo plano y B un
# segundo después). Se ejecuta DENTRO del contenedor, sobre la base de
# pruebas recién creada por run_etapa2.sh:
#
#   docker exec bodegas_atuel_db sh /tests/run_etapa2.sh
#   docker exec bodegas_atuel_db sh /tests/concurrencia/run_demo.sh
#
# Para hacerlo a mano (con capturas), ver docs/etapa2_concurrencia.md.
# ---------------------------------------------------------------------
set -e
DB="${1:-bodegas_test}"
U="${POSTGRES_USER}"
DIR=/tests/concurrencia
PSQL="psql -X -q -U $U -d $DB"

if [ "$DB" = "$POSTGRES_DB" ]; then
    echo "ERROR: la demostración se ejecuta sobre la base de pruebas, no sobre $POSTGRES_DB." >&2
    exit 1
fi

echo "=== Preparación: la sala 800001 tiene 1 botella del vino 800001 ==="
$PSQL -v ON_ERROR_STOP=1 -f $DIR/00_preparar.sql

echo
echo "=== Escenario 1: CON bloqueo (trigger con SELECT ... FOR UPDATE) ==="
$PSQL -f $DIR/con_bloqueo_sesion_a.sql > /tmp/conc_a.txt 2>&1 &
PID_A=$!
sleep 1
$PSQL -f $DIR/con_bloqueo_sesion_b.sql > /tmp/conc_b.txt 2>&1 || true
wait $PID_A
echo "--- Salida sesión A ---"; cat /tmp/conc_a.txt
echo "--- Salida sesión B ---"; cat /tmp/conc_b.txt
echo "--- Estado final ---"
$PSQL -c "SELECT cantidad AS stock_final FROM bodegas.stock_sala WHERE id_sala = 800001 AND id_vino = 800001" \
      -c "SELECT c.num_comprobante, COUNT(d.id_vino) AS renglones, c.total FROM bodegas.comprobante c LEFT JOIN bodegas.detalle_comprobante d USING (id_comprobante) WHERE c.id_comprobante IN (800001, 800002) GROUP BY c.num_comprobante, c.total ORDER BY 1"

echo
echo "=== Escenario 2: SIN bloqueo (la aplicación lee y escribe el stock por su cuenta) ==="
$PSQL -c "UPDATE bodegas.stock_sala SET cantidad = 1 WHERE id_sala = 800001 AND id_vino = 800001"
$PSQL -f $DIR/sin_bloqueo_sesion_a.sql > /tmp/conc_a.txt 2>&1 &
PID_A=$!
sleep 1
$PSQL -f $DIR/sin_bloqueo_sesion_b.sql > /tmp/conc_b.txt 2>&1 || true
wait $PID_A
echo "--- Salida sesión A ---"; cat /tmp/conc_a.txt
echo "--- Salida sesión B ---"; cat /tmp/conc_b.txt
echo "--- Estado final ---"
$PSQL -c "SELECT cantidad AS stock_final FROM bodegas.stock_sala WHERE id_sala = 800001 AND id_vino = 800001"
echo "Las DOS sesiones confirmaron su venta de la única botella: actualización perdida."
