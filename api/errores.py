import logging

import psycopg
from fastapi.responses import JSONResponse

# Traducción SQLSTATE -> (código HTTP, mensaje para el cliente)
ERRORES = {
    "23505": (409, "Ya existe un registro con esos datos"),
    "23503": (409, "El dato referenciado no existe o tiene registros relacionados"),
    "23514": (422, "Un valor no cumple una restricción de la base"),
    "23502": (422, "Falta un dato obligatorio"),
    "P0001": (409, None),  # regla de negocio: se usa el mensaje del trigger o procedimiento
    "22P02": (400, "Formato de dato inválido"),
    "40001": (503, "Conflicto entre transacciones, reintente la operación"),
    "40P01": (503, "Conflicto entre transacciones, reintente la operación"),
}


def error_postgres(request, exc: psycopg.Error):
    """Convierte cualquier error de PostgreSQL en una respuesta JSON."""
    codigo, mensaje = ERRORES.get(exc.sqlstate, (500, "Error interno del servidor"))

    if codigo == 500:
        # El detalle queda solo en el log del servidor, nunca en la respuesta
        logging.getLogger("uvicorn.error").error("Error de PostgreSQL no contemplado: %r", exc)
        return JSONResponse(status_code=500, content={"error": mensaje})

    if exc.sqlstate == "P0001":
        # Mensaje escrito en el RAISE EXCEPTION del trigger o procedimiento
        mensaje = exc.diag.message_primary or "La operación viola una regla de negocio"

    return JSONResponse(status_code=codigo, content={"error": mensaje, "sqlstate": exc.sqlstate})
