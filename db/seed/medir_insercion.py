#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
medir_insercion.py - Etapa 3, paso 6: compara la inserción fila por fila
con la inserción por lotes (executemany y COPY).

NO DEJA DATOS: todo ocurre dentro de UNA transacción que termina en
ROLLBACK. Se usa la tabla real `encargado` (con su PK, su UNIQUE y su
escritura en el WAL) con ids explícitos muy altos y dni 'BENCH-...', así
tampoco se consume la secuencia del SERIAL.

Uso (misma conexión que carga_masiva.py, por variables de entorno o .env):
    python medir_insercion.py                # 2.000 filas por método
    python medir_insercion.py --filas 10000

LIMITACIÓN (no se mide "un COMMIT por fila"):
    "Fila por fila" acá es una sentencia y un viaje de red por fila, pero
    todas dentro de la misma transacción. NO se mide confirmar cada fila
    con su propio COMMIT porque, por definición, eso deja datos
    persistentes en la base (aunque después se borraran, quedarían si el
    proceso se corta en el medio). Las alternativas tampoco sirven:
      * una tabla TEMPORARY no escribe WAL, así que su COMMIT no hace el
        fsync que es justamente el costo a medir (resultado engañoso);
      * una tabla UNLOGGED o una tabla auxiliar en `bodegas` modifica el
        esquema, lo que está prohibido.
    Por eso la diferencia real contra la carga por lotes es MAYOR que la
    que muestra este script (en la carga real cada lote confirma una sola
    vez). Si el grupo quiere medir el COMMIT por fila, debe hacerlo sobre
    una base descartable creada para eso (p. ej. la de tests/run_etapa2.sh)
    y dejarlo registrado.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from carga_masiva import DIR_REPO, ESQUEMA, ErrorCarga, conectar, parametros_conexion

ID_BASE = 2_000_000_000   # lejos de cualquier id real; nunca se confirma


def filas_prueba(metodo: int, n: int):
    base = ID_BASE + metodo * 10_000_000
    return [(base + i, f"Bench{metodo}", f"Fila {i:07d}", f"BENCH-{metodo}-{i:07d}") for i in range(n)]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Fila por fila vs. por lotes (con ROLLBACK)")
    ap.add_argument("--filas", type=int, default=2000)
    ap.add_argument("--env", default=str(DIR_REPO / ".env"))
    args = ap.parse_args(argv)
    sql = f"INSERT INTO {ESQUEMA}.encargado (id_encargado, nombre, apellido, dni) VALUES (%s, %s, %s, %s)"
    resultados = []
    try:
        conn = conectar(parametros_conexion(Path(args.env)))
        with conn:
            # force_rollback: al salir del bloque se hace ROLLBACK siempre (haya error o no)
            with conn.transaction(force_rollback=True), conn.cursor() as cur:
                filas = filas_prueba(1, args.filas)
                t = time.perf_counter()
                for fila in filas:                        # una sentencia (y un viaje) por fila
                    cur.execute(sql, fila)
                resultados.append(("Fila por fila (execute)", time.perf_counter() - t))

                filas = filas_prueba(2, args.filas)
                t = time.perf_counter()
                cur.executemany(sql, filas)               # lote: psycopg usa pipeline
                resultados.append(("Por lotes (executemany)", time.perf_counter() - t))

                filas = filas_prueba(3, args.filas)
                t = time.perf_counter()
                with cur.copy(f"COPY {ESQUEMA}.encargado (id_encargado, nombre, apellido, dni) "
                              "FROM STDIN") as cp:
                    for fila in filas:
                        cp.write_row(fila)
                resultados.append(("Por lotes (COPY)", time.perf_counter() - t))
    except ErrorCarga as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    base = resultados[0][1]
    print(f"\nInserción de {args.filas:,} filas en {ESQUEMA}.encargado (transacción revertida)".replace(",", "."))
    print(f"{'Método':<28}{'Segundos':>10}{'Filas/s':>12}{'vs. fila por fila':>20}")
    for nombre, seg in resultados:
        print(f"{nombre:<28}{seg:>10.3f}{args.filas / seg:>12,.0f}{base / seg:>19.1f}x".replace(",", "."))
    print("\nNota: las tres variantes corren en UNA transacción revertida. No se mide un COMMIT por fila "
          "(dejaría datos persistentes); la ventaja real de los lotes es mayor que la mostrada.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
