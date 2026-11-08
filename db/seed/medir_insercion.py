"""
medir_insercion.py - Etapa 3, paso 6: compara la inserción fila por fila con la
inserción por lotes (executemany y COPY).

Inserta N filas de prueba en la tabla encargado con cada método y mide el tiempo.
No deja datos: todo corre en una transacción que termina en ROLLBACK.

Uso (desde la raíz del repo):
    uv run python db/seed/medir_insercion.py           # 5.000 filas por método
    uv run python db/seed/medir_insercion.py 20000
"""
import sys
import time

from carga_masiva import conectar

N = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
SQL = "INSERT INTO encargado (id_encargado, nombre, apellido, dni) VALUES (%s, %s, %s, %s)"


def filas(desde):
    """Filas de prueba con id y dni que no chocan con los datos reales."""
    return [(desde + i, "Prueba", "Medicion", f"BENCH-{desde + i}") for i in range(N)]


def medir(nombre, cur, funcion):
    inicio = time.perf_counter()
    funcion(cur)
    segundos = time.perf_counter() - inicio
    print(f"{nombre:<22} {segundos:8.3f} s   {N / segundos:>10,.0f} filas/s")


def fila_por_fila(cur):
    for fila in filas(1_000_000):
        cur.execute(SQL, fila)            # una sentencia y un viaje a la base por fila


def executemany(cur):
    cur.executemany(SQL, filas(2_000_000))


def copy(cur):
    with cur.copy("COPY encargado (id_encargado, nombre, apellido, dni) FROM STDIN") as cp:
        for fila in filas(3_000_000):
            cp.write_row(fila)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"Inserción de {N:,} filas por método (todo se deshace al final)\n")
    with conectar() as conn, conn.cursor() as cur:
        medir("Fila por fila", cur, fila_por_fila)
        medir("Por lotes (executemany)", cur, executemany)
        medir("Por lotes (COPY)", cur, copy)
        conn.rollback()
