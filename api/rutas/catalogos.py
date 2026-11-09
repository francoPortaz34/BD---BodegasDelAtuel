from fastapi import APIRouter

from datos import catalogos as datos
from db import pool

# Catálogos de solo lectura que necesita el front (Etapa 7): salas para la venta,
# las transferencias y el tablero; bodegas, cepas y maridajes para el alta y la
# edición de vinos y para los filtros del catálogo.
router = APIRouter(tags=["Catálogos"])


@router.get("/salas")
def salas():
    with pool.connection() as conn:
        return datos.listar_salas(conn)


@router.get("/bodegas")
def bodegas():
    with pool.connection() as conn:
        return datos.listar_bodegas(conn)


@router.get("/cepas")
def cepas():
    with pool.connection() as conn:
        return datos.listar_cepas(conn)


@router.get("/maridajes")
def maridajes():
    with pool.connection() as conn:
        return datos.listar_maridajes(conn)
