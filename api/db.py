import os

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

# Pool de conexiones con el rol bodegas_api. Los datos salen de variables de
# entorno: ninguna credencial queda escrita en el código.
# open=False: el pool se abre al iniciar la app (ver lifespan en main.py).
pool = ConnectionPool(
    open=False,
    kwargs={
        "host": os.environ.get("API_DB_HOST", "localhost"),
        "port": os.environ.get("API_DB_PORT", "5432"),
        "dbname": os.environ.get("API_DB_NAME", "bodegas_atuel"),
        "user": os.environ.get("API_DB_USER", "bodegas_api"),
        "password": os.environ.get("API_DB_PASSWORD"),
        "sslmode": os.environ.get("API_DB_SSLMODE", "prefer"),
        "row_factory": dict_row,  # cada fila se devuelve como diccionario {columna: valor}
    },
)
