# Herramientas compartidas por las pruebas.
# Las pruebas NO usan la base real: reemplazan pool.connection por una conexión
# falsa que registra el SQL recibido y puede simular los errores de PostgreSQL.
from contextlib import contextmanager
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from psycopg import errors

from db import pool
from main import app


def error_pg(sqlstate, mensaje="error de prueba"):
    """El error que lanza psycopg cuando PostgreSQL rechaza una sentencia
    (mismo SQLSTATE y mismo mensaje que mandaría la base)."""
    clase = errors.lookup(sqlstate)
    con_mensaje = type(clase.__name__, (clase,), {"diag": SimpleNamespace(message_primary=mensaje)})
    return con_mensaje(mensaje)


class ConexionFalsa:
    def __init__(self):
        self.eventos = []      # SQL ejecutado y BEGIN / COMMIT / ROLLBACK, en orden
        self.parametros = []   # parámetros enviados en cada execute
        self.fila = None       # lo que devuelve fetchone() (None = no existe)
        self.falla_si = None   # (texto del SQL, error): simula un rechazo de la base

    def execute(self, sql, params=None):
        sql = " ".join(sql.split())
        self.eventos.append(sql)
        self.parametros.append(params)
        if self.falla_si and self.falla_si[0] in sql:
            raise self.falla_si[1]
        return self

    def fetchone(self):
        return self.fila

    def fetchall(self):
        return []

    @contextmanager
    def transaction(self):
        self.eventos.append("BEGIN")
        try:
            yield
        except Exception:
            self.eventos.append("ROLLBACK")
            raise
        self.eventos.append("COMMIT")


@pytest.fixture
def conn(monkeypatch):
    """Conexión falsa que usan todos los endpoints durante la prueba."""
    falsa = ConexionFalsa()

    @contextmanager
    def connection(*args, **kwargs):
        yield falsa

    monkeypatch.setattr(pool, "connection", connection)
    return falsa


@pytest.fixture
def client():
    # Sin "with": no se ejecuta el lifespan, así que nunca se abre el pool real
    return TestClient(app)
