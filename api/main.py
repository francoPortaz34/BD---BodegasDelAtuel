from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from psycopg_pool import PoolTimeout

from db import pool
from errores import error_postgres
from rutas import catalogos, clientes, comprobantes, ingresos, reportes, transferencias, vinos


@asynccontextmanager
async def lifespan(app):
    # wait=False: la API arranca aunque la base no esté disponible;
    # el pool sigue intentando conectar en segundo plano.
    pool.open(wait=False)
    yield
    pool.close()


app = FastAPI(title="API Bodegas del Atuel", lifespan=lifespan)

# Todo error de PostgreSQL que llegue sin capturar desde un endpoint pasa por acá
app.add_exception_handler(psycopg.Error, error_postgres)

app.include_router(vinos.router)
app.include_router(clientes.router)
app.include_router(comprobantes.router)
app.include_router(transferencias.router)
app.include_router(ingresos.router)
app.include_router(reportes.router)
app.include_router(catalogos.router)


@app.get("/salud")
def salud():
    try:
        # timeout corto: si no hay conexión en 3 s se responde 503
        with pool.connection(timeout=3) as conn:
            conn.execute("SELECT 1")
    except (PoolTimeout, psycopg.OperationalError):
        # No se devuelve el error de PostgreSQL para no exponer datos internos
        return JSONResponse(status_code=503,
                            content={"api": "ok", "base_de_datos": "no disponible"})
    return {"api": "ok", "base_de_datos": "ok"}
