from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from datos import transferencias as datos
from db import pool

router = APIRouter(prefix="/transferencias", tags=["Transferencias"])


class TransferenciaNueva(BaseModel):
    num_solicitud: str
    id_sala: int


class Renglon(BaseModel):
    id_vino: int
    cantidad_botellas: int


def buscar(conn, nro):
    """Transferencia con sus renglones; 404 si no existe."""
    transferencia = datos.obtener_transferencia(conn, nro)
    if transferencia is None:
        raise HTTPException(status_code=404, detail="Transferencia no encontrada")
    transferencia["renglones"] = datos.renglones_de_transferencia(conn, transferencia["id_transferencia"])
    return transferencia


@router.post("", status_code=201)
def crear(transferencia: TransferenciaNueva):
    with pool.connection() as conn:
        datos.insertar_transferencia(conn, transferencia.num_solicitud, transferencia.id_sala)
        return buscar(conn, transferencia.num_solicitud)


@router.post("/{nro}/renglones", status_code=201)
def agregar_renglon(nro: str, renglon: Renglon):
    with pool.connection() as conn:
        id_transferencia = buscar(conn, nro)["id_transferencia"]
        datos.insertar_renglon(conn, id_transferencia, renglon.id_vino, renglon.cantidad_botellas)
        return buscar(conn, nro)


@router.post("/{nro}/terminar")
def terminar(nro: str):
    with pool.connection() as conn:
        if not datos.terminar_transferencia(conn, nro):
            raise HTTPException(status_code=404, detail="Transferencia no encontrada")
        return buscar(conn, nro)


@router.post("/{nro}/procesar")
def procesar(nro: str):
    # El procedimiento es atómico: si falta stock o el estado no es 'terminado',
    # lanza un error (P0001 -> 409) y no queda ningún cambio.
    with pool.connection() as conn:
        id_transferencia = buscar(conn, nro)["id_transferencia"]
        datos.procesar_transferencia(conn, id_transferencia)
        return buscar(conn, nro)
