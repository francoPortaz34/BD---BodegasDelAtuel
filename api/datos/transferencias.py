# Capa de acceso a datos de transferencias: una función por consulta, todas parametrizadas.
# Estados, fecha, bloqueo de renglones y stock los controlan los triggers y
# sp_procesar_transferencia: la API no los replica.


def obtener_transferencia(conn, num_solicitud):
    return conn.execute("""
        SELECT id_transferencia, num_solicitud, fecha_confeccion, estado, id_sala
        FROM transferencia
        WHERE num_solicitud = %s
    """, (num_solicitud,)).fetchone()


def renglones_de_transferencia(conn, id_transferencia):
    return conn.execute("""
        SELECT r.id_vino, v.cod_vino, v.nombre_comercial, r.cantidad_botellas
        FROM renglon_transferencia r
        JOIN vino v ON v.id_vino = r.id_vino
        WHERE r.id_transferencia = %s
        ORDER BY v.cod_vino
    """, (id_transferencia,)).fetchall()


def insertar_transferencia(conn, num_solicitud, id_sala):
    # fecha_confeccion la fija el trigger (fecha actual) y estado nace 'en_confeccion'
    conn.execute("""
        INSERT INTO transferencia (num_solicitud, id_sala)
        VALUES (%s, %s)
    """, (num_solicitud, id_sala))


def insertar_renglon(conn, id_transferencia, id_vino, cantidad_botellas):
    # Si la transferencia no está en confección, el trigger lo rechaza (RN-12)
    conn.execute("""
        INSERT INTO renglon_transferencia (id_transferencia, id_vino, cantidad_botellas)
        VALUES (%s, %s, %s)
    """, (id_transferencia, id_vino, cantidad_botellas))


def terminar_transferencia(conn, num_solicitud):
    # El trigger valida la transición en_confeccion -> terminado
    fila = conn.execute("""
        UPDATE transferencia
        SET estado = 'terminado'
        WHERE num_solicitud = %s
        RETURNING id_transferencia
    """, (num_solicitud,)).fetchone()
    return fila is not None


def procesar_transferencia(conn, id_transferencia):
    # Mueve el stock del depósito a la sala y pasa a 'procesado' (todo en la base)
    conn.execute("CALL sp_procesar_transferencia(%s)", (id_transferencia,))
