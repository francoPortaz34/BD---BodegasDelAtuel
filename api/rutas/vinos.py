from decimal import Decimal

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from datos import vinos as datos
from db import pool

router = APIRouter(prefix="/vinos", tags=["Vinos"])


# Cuerpos de los pedidos. No se validan reglas de negocio acá: las controla PostgreSQL.
class Corte(BaseModel):
    id_cepa: int
    porcentaje_corte: Decimal


class VinoDatos(BaseModel):
    nombre_comercial: str
    tipo: str
    anada: int
    presentacion_ml: int
    graduacion_alcoholica: Decimal
    precio_venta: Decimal
    id_bodega: int


class VinoNuevo(VinoDatos):
    cod_vino: str
    cepas: list[Corte]


def ficha(conn, cod):
    """Vino con sus cepas y maridajes; 404 si no existe."""
    vino = datos.obtener_vino(conn, cod)
    if vino is None:
        raise HTTPException(status_code=404, detail="Vino no encontrado")
    vino["cepas"] = datos.cepas_del_vino(conn, vino["id_vino"])
    vino["maridajes"] = datos.maridajes_del_vino(conn, vino["id_vino"])
    return vino


@router.get("")
def listar(tipo: str | None = None, cepa: str | None = None, bodega: int | None = None,
           anada: int | None = None, pagina: int = Query(1, ge=1),
           tamanio: int = Query(20, ge=1, le=100)):
    with pool.connection() as conn:
        vinos = datos.listar_vinos(conn, tipo, cepa, bodega, anada,
                                   tamanio, (pagina - 1) * tamanio)
    return {"pagina": pagina, "tamanio": tamanio, "vinos": vinos}


@router.get("/{cod}")
def detalle(cod: str):
    with pool.connection() as conn:
        return ficha(conn, cod)


@router.post("", status_code=201)
def crear(vino: VinoNuevo):
    with pool.connection() as conn:
        # BEGIN; vino + composición; COMMIT. Si algo falla (incluida la regla
        # de que las cepas sumen 100, que se controla al COMMIT) -> ROLLBACK.
        with conn.transaction():
            id_vino = datos.insertar_vino(conn, vino.model_dump(exclude={"cepas"}))
            for c in vino.cepas:
                datos.insertar_corte(conn, id_vino, c.id_cepa, c.porcentaje_corte)
        return ficha(conn, vino.cod_vino)


@router.put("/{cod}")
def modificar(cod: str, vino: VinoDatos):
    with pool.connection() as conn:
        if not datos.actualizar_vino(conn, cod, vino.model_dump()):
            raise HTTPException(status_code=404, detail="Vino no encontrado")
        return ficha(conn, cod)


@router.delete("/{cod}")
def eliminar(cod: str):
    # Si el vino tiene movimientos, la FK (ON DELETE RESTRICT) lo impide y
    # el manejador central responde 409.
    with pool.connection() as conn:
        if not datos.eliminar_vino(conn, cod):
            raise HTTPException(status_code=404, detail="Vino no encontrado")
    return {"mensaje": "Vino eliminado", "cod_vino": cod}
