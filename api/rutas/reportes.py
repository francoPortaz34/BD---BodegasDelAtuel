from fastapi import APIRouter, HTTPException

from datos import reportes as datos
from datos.vinos import obtener_vino
from db import pool

router = APIRouter(prefix="/reportes", tags=["Reportes"])


@router.get("/top-vinos")
def top_vinos():
    with pool.connection() as conn:
        return datos.top_vinos(conn)


@router.get("/ventas-por-sala")
def ventas_por_sala():
    with pool.connection() as conn:
        return datos.ventas_por_sala(conn)


@router.get("/vinos-sin-stock")
def vinos_sin_stock(sala: int):
    with pool.connection() as conn:
        return datos.vinos_sin_stock(conn, sala)


@router.get("/transportista-activo")
def transportista_activo():
    with pool.connection() as conn:
        return datos.transportista_activo(conn)


@router.get("/trazabilidad/{cod}")
def trazabilidad(cod: str):
    with pool.connection() as conn:
        vino = obtener_vino(conn, cod)
        if vino is None:
            raise HTTPException(status_code=404, detail="Vino no encontrado")
        return {
            "vino": vino,
            "ingresos": datos.ingresos_del_vino(conn, vino["id_vino"]),
            "transferencias": datos.transferencias_del_vino(conn, vino["id_vino"]),
            "ventas_por_sala": datos.ventas_del_vino_por_sala(conn, vino["id_vino"]),
        }
