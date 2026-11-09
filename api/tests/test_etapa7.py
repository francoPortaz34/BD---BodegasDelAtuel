# Pruebas de los endpoints agregados para el front (Etapa 7). Se ejecutan con:
#   python -m pytest
# Igual que test_api.py, no necesitan PostgreSQL: usan la conexión falsa de conftest.py.
import pytest

from tests.conftest import error_pg

VINO = {"nombre_comercial": "Vino Prueba", "tipo": "tinto", "anada": 2022, "presentacion_ml": 750,
        "graduacion_alcoholica": 13.5, "precio_venta": 9500, "id_bodega": 1}


def sentencias(conn, inicio="BEGIN", fin="COMMIT"):
    """SQL ejecutado entre BEGIN y COMMIT (o ROLLBACK)."""
    desde = conn.eventos.index(inicio)
    hasta = conn.eventos.index(fin, desde)
    return conn.eventos[desde + 1:hasta]


# ---------------------------------------------------------------- catálogos

def test_docs_incluye_los_endpoints_nuevos(client):
    rutas = client.get("/openapi.json").json()["paths"]
    for ruta in ["/salas", "/bodegas", "/cepas", "/maridajes"]:
        assert "get" in rutas[ruta]
    assert "get" in rutas["/transferencias/{nro}"]


@pytest.mark.parametrize("url, tabla, fila", [
    ("/salas", "sala_de_ventas",
     {"id_sala": 1, "calle": "San Martín", "numero": "100", "dia_cierre_semanal": "lunes",
      "id_localidad": 4, "localidad": "San Rafael", "provincia": "Mendoza"}),
    ("/bodegas", "bodega",
     {"id_bodega": 1, "cuit": "30712345678", "razon_social": "Bodega Uno", "calle": "Ruta 143", "numero": "5"}),
    ("/cepas", "cepa", {"id_cepa": 1, "nombre": "Malbec", "tipo": "tinta"}),
    ("/maridajes", "maridaje", {"id_maridaje": 1, "nombre": "Carnes rojas", "temperatura_sugerida": 17.0}),
])
def test_catalogo_devuelve_las_filas_de_la_base(client, conn, url, tabla, fila):
    conn.filas = [fila]
    r = client.get(url)
    assert r.status_code == 200
    assert r.json() == [fila]
    assert f"FROM {tabla}" in conn.eventos[0]


def test_salas_no_se_limita_a_las_que_tienen_ventas(client, conn):
    client.get("/salas")
    sql = conn.eventos[0]
    assert "comprobante" not in sql          # no depende de las ventas
    assert "JOIN localidad" in sql            # trae la localidad de cada sala


# ---------------------------------------------------------------- transferencias

def test_detalle_de_transferencia_existente(client, conn):
    conn.fila = {"id_transferencia": 7, "num_solicitud": "TR-000007",
                 "fecha_confeccion": "2026-11-01", "estado": "terminado", "id_sala": 3}
    conn.filas = [{"id_vino": 12, "cod_vino": "V0012", "nombre_comercial": "Malbec Reserva",
                   "cantidad_botellas": 24}]
    r = client.get("/transferencias/TR-000007")
    assert r.status_code == 200
    assert r.json() == {**conn.fila, "renglones": conn.filas}
    assert conn.parametros[0] == ("TR-000007",)   # número como parámetro
    assert conn.parametros[1] == (7,)             # renglones por id_transferencia


def test_detalle_de_transferencia_inexistente_responde_404(client, conn):
    conn.fila = None
    r = client.get("/transferencias/TR-NOEXISTE")
    assert r.status_code == 404
    assert r.json() == {"detail": "Transferencia no encontrada"}


# ---------------------------------------------------------------- clientes

def test_clientes_sin_filtros_mantiene_la_consulta_original(client, conn):
    r = client.get("/clientes")
    assert r.status_code == 200
    assert r.json() == {"pagina": 1, "tamanio": 20, "clientes": []}
    assert "WHERE" not in conn.eventos[0]
    assert conn.parametros[0] == (20, 0)


def test_clientes_busca_por_nombre_parcial(client, conn):
    conn.filas = [{"id_cliente": 5, "nombre_o_razon_social": "Pérez, Ana"}]
    r = client.get("/clientes", params={"nombre": "pérez"})
    assert r.status_code == 200
    assert r.json()["clientes"] == conn.filas
    assert "c.nombre_o_razon_social ILIKE %s" in conn.eventos[0]
    assert conn.parametros[0] == ("%pérez%", 20, 0)


def test_clientes_busca_por_documento_parcial(client, conn):
    r = client.get("/clientes", params={"documento": "2034"})
    assert r.status_code == 200
    assert "c.num_documento ILIKE %s" in conn.eventos[0]
    assert "nombre_o_razon_social ILIKE" not in conn.eventos[0]
    assert conn.parametros[0] == ("%2034%", 20, 0)


def test_clientes_combina_filtros_y_pagina(client, conn):
    r = client.get("/clientes", params={"nombre": "ana", "documento": "20", "pagina": 3, "tamanio": 10})
    assert r.status_code == 200
    assert r.json()["pagina"] == 3 and r.json()["tamanio"] == 10
    assert "ILIKE %s AND c.num_documento ILIKE %s" in conn.eventos[0]
    assert conn.parametros[0] == ("%ana%", "%20%", 10, 20)   # LIMIT 10 OFFSET 20


def test_clientes_tamanio_maximo_sigue_siendo_100(client, conn):
    assert client.get("/clientes", params={"nombre": "a", "tamanio": 101}).status_code == 422


def test_clientes_filtro_vacio_no_filtra(client, conn):
    client.get("/clientes", params={"nombre": "  ", "documento": ""})
    assert "WHERE" not in conn.eventos[0]


def test_clientes_busqueda_escapa_comodines_e_inyeccion(client, conn):
    malicioso = "50%_' OR '1'='1"
    client.get("/clientes", params={"nombre": malicioso})
    assert conn.parametros[0][0] == "%50\\%\\_' OR '1'='1%"   # comodines literales
    assert malicioso not in conn.eventos[0]                    # nunca dentro del SQL


# ---------------------------------------------------------------- edición de vinos

def test_put_sin_campos_nuevos_solo_actualiza_la_ficha(client, conn):
    conn.fila = {"id_vino": 40}
    r = client.put("/vinos/V0040", json=VINO)
    assert r.status_code == 200
    dentro = sentencias(conn)
    assert len(dentro) == 1 and dentro[0].startswith("UPDATE vino")
    assert not any("vino_cepa" in e or "vino_maridaje" in e for e in dentro)


def test_put_actualiza_ficha_y_composicion_en_una_transaccion(client, conn):
    conn.fila = {"id_vino": 40}
    cepas = [{"id_cepa": 1, "porcentaje_corte": 70}, {"id_cepa": 3, "porcentaje_corte": 30}]
    r = client.put("/vinos/V0040", json={**VINO, "cepas": cepas})
    assert r.status_code == 200
    dentro = sentencias(conn)
    assert dentro[0].startswith("UPDATE vino")
    assert dentro[1] == "DELETE FROM vino_cepa WHERE id_vino = %s"
    assert [e.split()[2] for e in dentro[2:]] == ["vino_cepa", "vino_cepa"]
    assert (40, 1, 70) in conn.parametros and (40, 3, 30) in conn.parametros


def test_put_actualiza_maridajes(client, conn):
    conn.fila = {"id_vino": 40}
    r = client.put("/vinos/V0040", json={**VINO, "maridajes": [2, 5]})
    assert r.status_code == 200
    dentro = sentencias(conn)
    assert dentro[1] == "DELETE FROM vino_maridaje WHERE id_vino = %s"
    assert [e.split()[2] for e in dentro[2:]] == ["vino_maridaje", "vino_maridaje"]
    assert (40, 2) in conn.parametros and (40, 5) in conn.parametros
    assert not any("vino_cepa" in e for e in dentro)   # la composición no se tocó


def test_put_con_lista_de_maridajes_vacia_los_quita(client, conn):
    conn.fila = {"id_vino": 40}
    r = client.put("/vinos/V0040", json={**VINO, "maridajes": []})
    assert r.status_code == 200
    assert sentencias(conn)[1:] == ["DELETE FROM vino_maridaje WHERE id_vino = %s"]


def test_put_composicion_que_no_suma_100_la_rechaza_la_base(client, conn):
    # La API no valida la suma: el error es el del trigger diferido RN-05 (P0001)
    mensaje = "Los porcentajes de corte del vino 40 suman 90 y deben sumar 100 (RN-05)"
    conn.fila = {"id_vino": 40}
    conn.falla_si = ("INSERT INTO vino_cepa", error_pg("P0001", mensaje))
    r = client.put("/vinos/V0040", json={**VINO, "cepas": [{"id_cepa": 1, "porcentaje_corte": 90}]})
    assert r.status_code == 409
    assert r.json() == {"error": mensaje, "sqlstate": "P0001"}
    assert conn.eventos[-1] == "ROLLBACK" and "COMMIT" not in conn.eventos


def test_put_composicion_vacia_la_decide_la_base(client, conn):
    # Lista vacía = quitar la composición. La API no la rechaza por su cuenta:
    # borra los cortes y la regla RN-05 de la base decide al COMMIT.
    conn.fila = {"id_vino": 40}
    mensaje = "Los porcentajes de corte del vino 40 suman 0 y deben sumar 100 (RN-05)"
    conn.falla_si = ("DELETE FROM vino_cepa", error_pg("P0001", mensaje))
    r = client.put("/vinos/V0040", json={**VINO, "cepas": []})
    assert r.status_code == 409
    assert r.json()["error"] == mensaje


def test_put_si_falla_una_parte_no_quedan_cambios_parciales(client, conn):
    # Ficha y composición ya enviadas; el maridaje 999 no existe (FK 23503):
    # toda la edición se revierte
    conn.fila = {"id_vino": 40}
    conn.falla_si = ("INSERT INTO vino_maridaje", error_pg("23503", "violates foreign key constraint"))
    r = client.put("/vinos/V0040", json={**VINO, "cepas": [{"id_cepa": 1, "porcentaje_corte": 100}],
                                         "maridajes": [999]})
    assert r.status_code == 409
    assert r.json()["sqlstate"] == "23503"
    dentro = sentencias(conn, fin="ROLLBACK")
    assert dentro[0].startswith("UPDATE vino") and "INSERT INTO vino_cepa" in dentro[2]
    assert conn.eventos[-1] == "ROLLBACK" and "COMMIT" not in conn.eventos


def test_put_vino_inexistente_no_toca_composicion(client, conn):
    conn.fila = None
    r = client.put("/vinos/NOEXISTE", json={**VINO, "cepas": [{"id_cepa": 1, "porcentaje_corte": 100}]})
    assert r.status_code == 404
    assert not any("vino_cepa" in e for e in conn.eventos)
