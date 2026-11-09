from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from datos import comprobantes as datos
from db import pool

router = APIRouter(prefix="/comprobantes", tags=["Comprobantes"])


# Solo se envían los datos de la venta; precios, descuentos, subtotales, totales
# y stock los resuelve PostgreSQL.
class Renglon(BaseModel):
    id_vino: int
    cantidad: int


class ComprobanteNuevo(BaseModel):
    num_comprobante: str
    id_cliente: int
    id_sala: int
    renglones: list[Renglon]


def buscar(conn, nro):
    comprobante = datos.obtener_comprobante(conn, nro)
    if comprobante is None:
        raise HTTPException(status_code=404, detail="Comprobante no encontrado")
    comprobante["renglones"] = datos.renglones_del_comprobante(conn, comprobante["id_comprobante"])
    return comprobante


@router.post("", status_code=201)
def crear(comprobante: ComprobanteNuevo):
    with pool.connection() as conn:
        # BEGIN; cabecera + renglones; COMMIT. Si un renglón falla (por ejemplo,
        # stock insuficiente) -> ROLLBACK de toda la venta.
        with conn.transaction():
            id_comprobante = datos.insertar_comprobante(conn, comprobante.num_comprobante,
                                                        comprobante.id_cliente, comprobante.id_sala)
            for r in comprobante.renglones:
                datos.insertar_renglon(conn, id_comprobante, r.id_vino, r.cantidad)
        return buscar(conn, comprobante.num_comprobante)


@router.get("/{nro}")
def detalle(nro: str):
    with pool.connection() as conn:
        return buscar(conn, nro)
