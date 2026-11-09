# Pruebas automáticas de la API (Etapa 6). Se ejecutan con:  python -m pytest
# No necesitan PostgreSQL: ver conftest.py.
import pytest
from psycopg_pool import PoolTimeout

from db import pool
from errores import error_postgres
from tests.conftest import error_pg

VINO = {"nombre_comercial": "Vino Prueba", "tipo": "tinto", "anada": 2022, "presentacion_ml": 750,
        "graduacion_alcoholica": 13.5, "precio_venta": 9500, "id_bodega": 1}
CLIENTE = {"nombre_o_razon_social": "Cliente Prueba", "tipo_documento": "DNI", "num_documento": "99000001",
           "calle": "San Martín", "numero": "100", "id_localidad": 1, "id_tipo_cliente": 2}


# ---------------------------------------------------------------- generales

def test_docs_muestra_todos_los_endpoints(client):
    rutas = client.get("/openapi.json").json()["paths"]
    for ruta in ["/salud", "/vinos", "/vinos/{cod}", "/clientes", "/clientes/{id_cliente}",
                 "/comprobantes", "/comprobantes/{nro}", "/transferencias",
                 "/transferencias/{nro}/renglones", "/transferencias/{nro}/terminar",
                 "/transferencias/{nro}/procesar", "/ingresos", "/ingresos/{cod}/renglones",
                 "/ingresos/{cod}/procesar", "/reportes/top-vinos", "/reportes/ventas-por-sala",
                 "/reportes/vinos-sin-stock", "/reportes/transportista-activo",
                 "/reportes/trazabilidad/{cod}"]:
        assert ruta in rutas
    assert client.get("/docs").status_code == 200


def test_salud_sin_base_responde_503_sin_detalles(client, monkeypatch):
    def sin_conexion(*args, **kwargs):
        raise PoolTimeout("couldn't get a connection after 3.00 sec")
    monkeypatch.setattr(pool, "connection", sin_conexion)

    r = client.get("/salud")
    assert r.status_code == 503
    assert r.json() == {"api": "ok", "base_de_datos": "no disponible"}


@pytest.mark.parametrize("sqlstate, http", [
    ("23505", 409), ("23503", 409), ("23514", 422), ("23502", 422),
    ("P0001", 409), ("22P02", 400), ("40001", 503), ("40P01", 503),
    ("42501", 500),  # no contemplado en la tabla -> 500 genérico
])
def test_tabla_sqlstate_a_http(sqlstate, http):
    respuesta = error_postgres(None, error_pg(sqlstate, "detalle interno"))
    assert respuesta.status_code == http


def test_error_no_contemplado_no_expone_detalles(client, conn):
    conn.falla_si = ("SELECT", error_pg("42501", "permission denied for table stock_sala"))
    r = client.get("/reportes/top-vinos")
    assert r.status_code == 500
    assert r.json() == {"error": "Error interno del servidor"}


# ---------------------------------------------------------------- vinos

def test_listar_vinos_pagina_y_filtra_con_parametros(client, conn):
    r = client.get("/vinos", params={"tipo": "tinto", "cepa": "Malbec", "bodega": 3,
                                     "anada": 2020, "pagina": 3, "tamanio": 10})
    assert r.status_code == 200
    assert r.json() == {"pagina": 3, "tamanio": 10, "vinos": []}
    assert conn.parametros[0] == {"tipo": "tinto", "cepa": "Malbec", "bodega": 3, "anada": 2020,
                                  "limite": 10, "desde": 20}


def test_inyeccion_sql_en_filtro_se_trata_como_texto(client, conn):
    malicioso = "Malbec' OR '1'='1'; DROP TABLE vino; --"
    r = client.get("/vinos", params={"cepa": malicioso})
    assert r.status_code == 200
    assert conn.parametros[0]["cepa"] == malicioso   # viaja como parámetro...
    assert malicioso not in conn.eventos[0]           # ...y nunca dentro del SQL
    assert "DROP" not in conn.eventos[0]


def test_vino_inexistente_responde_404(client, conn):
    conn.fila = None
    assert client.get("/vinos/NOEXISTE").status_code == 404
    assert client.put("/vinos/NOEXISTE", json=VINO).status_code == 404
    assert client.delete("/vinos/NOEXISTE").status_code == 404


def test_crear_vino_y_cepas_en_una_transaccion(client, conn):
    conn.fila = {"id_vino": 500, "cod_vino": "TEST-1"}
    cepas = [{"id_cepa": 1, "porcentaje_corte": 60}, {"id_cepa": 2, "porcentaje_corte": 40}]
    r = client.post("/vinos", json={**VINO, "cod_vino": "TEST-1", "cepas": cepas})
    assert r.status_code == 201
    inicio, fin = conn.eventos.index("BEGIN"), conn.eventos.index("COMMIT")
    inserts = [e.split()[2] for e in conn.eventos[inicio:fin] if e.startswith("INSERT")]
    assert inserts == ["vino", "vino_cepa", "vino_cepa"]


def test_regla_base_precio_negativo_responde_422(client, conn):
    # dom_dinero (CHECK VALUE >= 0) rechaza el precio: SQLSTATE 23514
    conn.fila = {"id_vino": 1}
    conn.falla_si = ("UPDATE vino", error_pg("23514", 'value for domain dom_dinero violates check constraint "dom_dinero_check"'))
    r = client.put("/vinos/V0001", json={**VINO, "precio_venta": -100})
    assert r.status_code == 422
    assert r.json()["sqlstate"] == "23514"
    assert "dom_dinero" not in r.text   # no expone nombres internos


def test_regla_base_cepas_que_no_suman_100_responde_409(client, conn):
    # El trigger diferido de RN-05 rechaza al hacer COMMIT -> la transacción se revierte
    mensaje = "Los porcentajes de corte del vino 500 suman 60 y deben sumar 100 (RN-05)"
    conn.fila = {"id_vino": 500}
    conn.falla_si = ("INSERT INTO vino_cepa", error_pg("P0001", mensaje))
    r = client.post("/vinos", json={**VINO, "cod_vino": "TEST-2",
                                    "cepas": [{"id_cepa": 1, "porcentaje_corte": 60}]})
    assert r.status_code == 409
    assert r.json()["error"] == mensaje
    assert conn.eventos[-1] == "ROLLBACK"


# ---------------------------------------------------------------- clientes

def test_crear_distribuidor_inserta_cliente_y_subtipo(client, conn):
    conn.fila = {"id_cliente": 20001}
    r = client.post("/clientes", json={**CLIENTE, "subtipo": "distribuidor",
                                       "zona_cobertura": "Cuyo", "numero_habilitacion": "HAB-1"})
    assert r.status_code == 201
    assert conn.eventos[0] == "BEGIN"
    assert "INSERT INTO cliente" in conn.eventos[1]
    assert "INSERT INTO distribuidor" in conn.eventos[2]
    assert conn.eventos[3] == "COMMIT"
    assert (20001, "Cuyo", "HAB-1") in conn.parametros


def test_listar_clientes_pagina_con_parametros(client, conn):
    r = client.get("/clientes", params={"pagina": 4, "tamanio": 25})
    assert r.status_code == 200
    assert conn.parametros[0] == (25, 75)   # LIMIT 25 OFFSET 75


def test_cliente_inexistente_responde_404(client, conn):
    conn.fila = None
    assert client.get("/clientes/999999").status_code == 404
    assert client.delete("/clientes/999999").status_code == 404


def test_regla_base_borrar_cliente_con_comprobantes_responde_409(client, conn):
    # FK de comprobante con ON DELETE RESTRICT: SQLSTATE 23503
    conn.falla_si = ("DELETE FROM cliente", error_pg("23503", "update or delete on table cliente violates foreign key"))
    r = client.delete("/clientes/1")
    assert r.status_code == 409
    assert r.json()["sqlstate"] == "23503"


# ---------------------------------------------------------------- comprobantes

def test_regla_base_venta_sin_stock_responde_409_sin_datos_a_medias(client, conn):
    mensaje = "Stock insuficiente del vino 155 en la sala 1: disponible 0, solicitado 5 (RN-09)"
    conn.fila = {"id_comprobante": 150001}
    conn.falla_si = ("INSERT INTO detalle_comprobante", error_pg("P0001", mensaje))
    venta = {"num_comprobante": "C-TEST-1", "id_cliente": 1, "id_sala": 1,
             "renglones": [{"id_vino": 155, "cantidad": 5}]}
    r = client.post("/comprobantes", json=venta)
    assert r.status_code == 409
    assert r.json() == {"error": mensaje, "sqlstate": "P0001"}
    assert conn.eventos[-1] == "ROLLBACK" and "COMMIT" not in conn.eventos


def test_comprobante_inexistente_responde_404(client, conn):
    conn.fila = None
    assert client.get("/comprobantes/C-NOEXISTE").status_code == 404


# ---------------------------------------------------------------- transferencias e ingresos

def test_regla_base_cambio_de_estado_invalido_responde_409(client, conn):
    mensaje = "Cambio de estado no permitido en transferencia: procesado -> terminado (RN-10/RN-11)"
    conn.falla_si = ("UPDATE transferencia", error_pg("P0001", mensaje))
    r = client.post("/transferencias/TR-000001/terminar")
    assert r.status_code == 409
    assert r.json()["error"] == mensaje


def test_procesar_transferencia_llama_al_procedimiento(client, conn):
    conn.fila = {"id_transferencia": 7, "num_solicitud": "TR-000007"}
    r = client.post("/transferencias/TR-000007/procesar")
    assert r.status_code == 200
    assert "CALL sp_procesar_transferencia(%s)" in conn.eventos
    assert (7,) in conn.parametros


def test_procesar_ingreso_termina_y_procesa_en_una_transaccion(client, conn):
    conn.fila = {"id_ingreso": 9, "cod_ingreso": "IN-000009"}
    r = client.post("/ingresos/IN-000009/procesar")
    assert r.status_code == 200
    inicio, fin = conn.eventos.index("BEGIN"), conn.eventos.index("COMMIT")
    dentro = conn.eventos[inicio:fin]
    assert any(e.startswith("UPDATE ingreso SET estado = 'terminado'") for e in dentro)
    assert "CALL sp_procesar_ingreso(%s)" in dentro


def test_transferencia_e_ingreso_inexistentes_responden_404(client, conn):
    conn.fila = None
    assert client.post("/transferencias/TR-NO/procesar").status_code == 404
    assert client.post("/ingresos/IN-NO/renglones", json={"id_vino": 1, "cantidad_botellas": 1}).status_code == 404


# ---------------------------------------------------------------- reportes

@pytest.mark.parametrize("url", ["/reportes/top-vinos", "/reportes/ventas-por-sala",
                                 "/reportes/transportista-activo", "/reportes/vinos-sin-stock?sala=1"])
def test_reportes_responden(client, conn, url):
    assert client.get(url).status_code == 200


def test_trazabilidad_de_vino_inexistente_responde_404(client, conn):
    conn.fila = None
    malicioso = "V0001' OR '1'='1"
    r = client.get(f"/reportes/trazabilidad/{malicioso}")
    assert r.status_code == 404
    assert conn.parametros == [(malicioso,)]   # el código viajó como parámetro
