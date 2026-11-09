from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from datos import ingresos as datos
from db import pool

router = APIRouter(prefix="/ingresos", tags=["Ingresos"])


class IngresoNuevo(BaseModel):
    cod_ingreso: str
    id_transportista: int
    id_bodega: int


class Renglon(BaseModel):
    id_vino: int
    cantidad_botellas: int


def buscar(conn, cod):
    """Ingreso con sus renglones; 404 si no existe."""
    ingreso = datos.obtener_ingreso(conn, cod)
    if ingreso is None:
        raise HTTPException(status_code=404, detail="Ingreso no encontrado")
    ingreso["renglones"] = datos.renglones_de_ingreso(conn, ingreso["id_ingreso"])
    return ingreso


@router.post("", status_code=201)
def crear(ingreso: IngresoNuevo):
    with pool.connection() as conn:
        datos.insertar_ingreso(conn, ingreso.cod_ingreso, ingreso.id_transportista, ingreso.id_bodega)
        return buscar(conn, ingreso.cod_ingreso)


@router.post("/{cod}/renglones", status_code=201)
def agregar_renglon(cod: str, renglon: Renglon):
    with pool.connection() as conn:
        id_ingreso = buscar(conn, cod)["id_ingreso"]
        datos.insertar_renglon(conn, id_ingreso, renglon.id_vino, renglon.cantidad_botellas)
        return buscar(conn, cod)


@router.post("/{cod}/procesar")
def procesar(cod: str):
    # La consigna no tiene /terminar para ingresos: procesar pasa el ingreso a
    # 'terminado' y llama al procedimiento, en UNA transacción. Si el procedimiento
    # falla (por ejemplo, ingreso sin renglones), ROLLBACK de los dos pasos.
    with pool.connection() as conn:
        with conn.transaction():
            id_ingreso = buscar(conn, cod)["id_ingreso"]
            datos.terminar_ingreso(conn, id_ingreso)
            datos.procesar_ingreso(conn, id_ingreso)
        return buscar(conn, cod)
