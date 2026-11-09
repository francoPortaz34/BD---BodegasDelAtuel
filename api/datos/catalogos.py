# Capa de acceso a datos de los catálogos de consulta (Etapa 7: los usa el front
# para armar sus listas de selección). Una función por consulta, sin parámetros
# de usuario. Son tablas chicas (decenas de filas): se devuelven completas.


def listar_salas(conn):
    # Todas las salas, tengan o no ventas, con su localidad
    return conn.execute("""
        SELECT s.id_sala, s.calle, s.numero, s.dia_cierre_semanal,
               s.id_localidad, l.nombre AS localidad, l.provincia
        FROM sala_de_ventas s
        JOIN localidad l ON l.id_localidad = s.id_localidad
        ORDER BY s.id_sala
    """).fetchall()


def listar_bodegas(conn):
    return conn.execute("""
        SELECT id_bodega, cuit, razon_social, calle, numero
        FROM bodega
        ORDER BY razon_social
    """).fetchall()


def listar_cepas(conn):
    return conn.execute("""
        SELECT id_cepa, nombre, tipo
        FROM cepa
        ORDER BY nombre
    """).fetchall()


def listar_maridajes(conn):
    return conn.execute("""
        SELECT id_maridaje, nombre, temperatura_sugerida
        FROM maridaje
        ORDER BY nombre
    """).fetchall()
