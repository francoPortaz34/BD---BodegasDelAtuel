from typing import Literal

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from datos import clientes as datos
from db import pool

router = APIRouter(prefix="/clientes", tags=["Clientes"])


# Cuerpos de los pedidos. No se validan reglas de negocio acá: las controla PostgreSQL
# (documento repetido, localidad o tipo inexistente, datos del subtipo obligatorios, etc.).
class ClienteDatos(BaseModel):
    nombre_o_razon_social: str
    tipo_documento: str
    num_documento: str
    calle: str
    numero: str
    id_localidad: int
    id_tipo_cliente: int  # tipo de cliente: define el descuento
    zona_cobertura: str | None = None          # solo distribuidor
    numero_habilitacion: str | None = None     # solo distribuidor
    pais_destino_principal: str | None = None  # solo exportador


class ClienteNuevo(ClienteDatos):
    subtipo: Literal["socio", "distribuidor", "exportador"]  # tabla en la que se registra


def buscar(conn, id_cliente):
    cliente = datos.obtener_cliente(conn, id_cliente)
    if cliente is None:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")
    return cliente


@router.get("")
def listar(pagina: int = Query(1, ge=1), tamanio: int = Query(20, ge=1, le=100)):
    with pool.connection() as conn:
        clientes = datos.listar_clientes(conn, tamanio, (pagina - 1) * tamanio)
    return {"pagina": pagina, "tamanio": tamanio, "clientes": clientes}


@router.get("/{id_cliente}")
def detalle(id_cliente: int):
    with pool.connection() as conn:
        return buscar(conn, id_cliente)


@router.post("", status_code=201)
def crear(cliente: ClienteNuevo):
    with pool.connection() as conn:
        # BEGIN; cliente + fila del subtipo; COMMIT (o ROLLBACK si algo falla)
        with conn.transaction():
            id_cliente = datos.insertar_cliente(conn, cliente.model_dump())
            if cliente.subtipo == "socio":
                datos.insertar_socio(conn, id_cliente)
            elif cliente.subtipo == "distribuidor":
                datos.insertar_distribuidor(conn, id_cliente, cliente.zona_cobertura,
                                            cliente.numero_habilitacion)
            else:
                datos.insertar_exportador(conn, id_cliente, cliente.pais_destino_principal)
        return buscar(conn, id_cliente)


@router.put("/{id_cliente}")
def modificar(id_cliente: int, cliente: ClienteDatos):
    # El subtipo no se cambia: se actualizan los datos comunes y los del subtipo actual
    with pool.connection() as conn:
        with conn.transaction():
            if not datos.actualizar_cliente(conn, id_cliente, cliente.model_dump()):
                raise HTTPException(status_code=404, detail="Cliente no encontrado")
            subtipo = datos.obtener_cliente(conn, id_cliente)["subtipo"]
            if subtipo == "distribuidor":
                datos.actualizar_distribuidor(conn, id_cliente, cliente.zona_cobertura,
                                              cliente.numero_habilitacion)
            elif subtipo == "exportador":
                datos.actualizar_exportador(conn, id_cliente, cliente.pais_destino_principal)
        return buscar(conn, id_cliente)


@router.delete("/{id_cliente}")
def eliminar(id_cliente: int):
    # Si el cliente tiene comprobantes, la FK (ON DELETE RESTRICT) lo impide y
    # el manejador central responde 409.
    with pool.connection() as conn:
        if not datos.eliminar_cliente(conn, id_cliente):
            raise HTTPException(status_code=404, detail="Cliente no encontrado")
    return {"mensaje": "Cliente eliminado", "id_cliente": id_cliente}
