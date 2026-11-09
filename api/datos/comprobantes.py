# Capa de acceso a datos de comprobantes: una función por consulta, todas parametrizadas.
# Los importes NO se calculan acá: los completan los triggers de la base
# (trg_detalle_validar, trg_detalle_actualizar y trg_comprobante_totales).


def insertar_comprobante(conn, num_comprobante, id_cliente, id_sala):
    # fecha: DEFAULT CURRENT_DATE. subtotal, descuento y total: los calcula el trigger.
    return conn.execute("""
        INSERT INTO comprobante (num_comprobante, id_cliente, id_sala)
        VALUES (%s, %s, %s)
        RETURNING id_comprobante
    """, (num_comprobante, id_cliente, id_sala)).fetchone()["id_comprobante"]


def insertar_renglon(conn, id_comprobante, id_vino, cantidad):
    # El trigger completa precio, descuento y subtotal, controla el stock (RN-09)
    # y lo descuenta de la sala.
    conn.execute("""
        INSERT INTO detalle_comprobante (id_comprobante, id_vino, cantidad)
        VALUES (%s, %s, %s)
    """, (id_comprobante, id_vino, cantidad))


def obtener_comprobante(conn, num_comprobante):
    return conn.execute("""
        SELECT c.id_comprobante, c.num_comprobante, c.fecha, c.id_cliente,
               cl.nombre_o_razon_social AS cliente, c.id_sala,
               c.subtotal, c.descuento, c.total
        FROM comprobante c
        JOIN cliente cl ON cl.id_cliente = c.id_cliente
        WHERE c.num_comprobante = %s
    """, (num_comprobante,)).fetchone()


def renglones_del_comprobante(conn, id_comprobante):
    return conn.execute("""
        SELECT d.id_vino, v.cod_vino, v.nombre_comercial, d.cantidad,
               d.precio_unitario_venta, d.descuento_aplicado, d.subtotal_renglon
        FROM detalle_comprobante d
        JOIN vino v ON v.id_vino = d.id_vino
        WHERE d.id_comprobante = %s
        ORDER BY v.cod_vino
    """, (id_comprobante,)).fetchall()
