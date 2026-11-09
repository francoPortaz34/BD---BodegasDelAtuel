# Capa de acceso a datos de clientes: una función por consulta, todas parametrizadas.
# Cada función recibe la conexión; la transacción la maneja la ruta.

# Cliente con su tipo (descuento) y los datos de su subtipo. El subtipo se deduce
# de la tabla (socio, distribuidor o exportador) en la que tiene fila.
SELECT_CLIENTE = """
    SELECT c.id_cliente, c.nombre_o_razon_social, c.tipo_documento, c.num_documento,
           c.calle, c.numero, c.fecha_alta, c.id_localidad,
           c.id_tipo_cliente, t.nombre AS tipo_cliente,
           CASE WHEN s.id_cliente IS NOT NULL THEN 'socio'
                WHEN d.id_cliente IS NOT NULL THEN 'distribuidor'
                WHEN e.id_cliente IS NOT NULL THEN 'exportador'
           END AS subtipo,
           d.zona_cobertura, d.numero_habilitacion, e.pais_destino_principal
    FROM cliente c
    JOIN tipo_cliente t       ON t.id_tipo_cliente = c.id_tipo_cliente
    LEFT JOIN socio s         ON s.id_cliente = c.id_cliente
    LEFT JOIN distribuidor d  ON d.id_cliente = c.id_cliente
    LEFT JOIN exportador e    ON e.id_cliente = c.id_cliente
"""


def patron_parcial(texto):
    """Patrón ILIKE de coincidencia parcial. Se escapan los comodines de LIKE
    (%, _ y \\) para que el texto del usuario se busque literalmente."""
    escapado = texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escapado}%"


def listar_clientes(conn, limite, desde, nombre=None, documento=None):
    # Filtros opcionales y combinables (AND). Las condiciones son texto fijo del
    # código; lo que escribe el usuario viaja siempre como parámetro.
    # La paginación (LIMIT/OFFSET) la hace PostgreSQL: nunca se traen todos los clientes.
    condiciones, parametros = [], []
    if nombre:
        condiciones.append("c.nombre_o_razon_social ILIKE %s")
        parametros.append(patron_parcial(nombre))
    if documento:
        condiciones.append("c.num_documento ILIKE %s")
        parametros.append(patron_parcial(documento))
    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    return conn.execute(SELECT_CLIENTE + where + """
        ORDER BY c.id_cliente
        LIMIT %s OFFSET %s
    """, (*parametros, limite, desde)).fetchall()


def obtener_cliente(conn, id_cliente):
    return conn.execute(SELECT_CLIENTE + " WHERE c.id_cliente = %s",
                        (id_cliente,)).fetchone()


def insertar_cliente(conn, cliente):
    # fecha_alta no se envía: la completa el DEFAULT CURRENT_DATE de la base
    return conn.execute("""
        INSERT INTO cliente (nombre_o_razon_social, tipo_documento, num_documento,
                             calle, numero, id_localidad, id_tipo_cliente)
        VALUES (%(nombre_o_razon_social)s, %(tipo_documento)s, %(num_documento)s,
                %(calle)s, %(numero)s, %(id_localidad)s, %(id_tipo_cliente)s)
        RETURNING id_cliente
    """, cliente).fetchone()["id_cliente"]


def insertar_socio(conn, id_cliente):
    conn.execute("INSERT INTO socio (id_cliente) VALUES (%s)", (id_cliente,))


def insertar_distribuidor(conn, id_cliente, zona_cobertura, numero_habilitacion):
    conn.execute("""
        INSERT INTO distribuidor (id_cliente, zona_cobertura, numero_habilitacion)
        VALUES (%s, %s, %s)
    """, (id_cliente, zona_cobertura, numero_habilitacion))


def insertar_exportador(conn, id_cliente, pais_destino_principal):
    conn.execute("""
        INSERT INTO exportador (id_cliente, pais_destino_principal)
        VALUES (%s, %s)
    """, (id_cliente, pais_destino_principal))


def actualizar_cliente(conn, id_cliente, cliente):
    fila = conn.execute("""
        UPDATE cliente
        SET nombre_o_razon_social = %(nombre_o_razon_social)s, tipo_documento = %(tipo_documento)s,
            num_documento = %(num_documento)s, calle = %(calle)s, numero = %(numero)s,
            id_localidad = %(id_localidad)s, id_tipo_cliente = %(id_tipo_cliente)s
        WHERE id_cliente = %(id_cliente)s
        RETURNING id_cliente
    """, {**cliente, "id_cliente": id_cliente}).fetchone()
    return fila is not None


def actualizar_distribuidor(conn, id_cliente, zona_cobertura, numero_habilitacion):
    conn.execute("""
        UPDATE distribuidor
        SET zona_cobertura = %s, numero_habilitacion = %s
        WHERE id_cliente = %s
    """, (zona_cobertura, numero_habilitacion, id_cliente))


def actualizar_exportador(conn, id_cliente, pais_destino_principal):
    conn.execute("""
        UPDATE exportador
        SET pais_destino_principal = %s
        WHERE id_cliente = %s
    """, (pais_destino_principal, id_cliente))


def eliminar_cliente(conn, id_cliente):
    # La fila del subtipo (y los permisos del exportador) se borran por ON DELETE CASCADE
    fila = conn.execute("DELETE FROM cliente WHERE id_cliente = %s RETURNING id_cliente",
                        (id_cliente,)).fetchone()
    return fila is not None
