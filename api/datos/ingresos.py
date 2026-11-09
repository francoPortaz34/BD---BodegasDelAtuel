# Capa de acceso a datos de ingresos: una función por consulta, todas parametrizadas.
# Estados, bloqueo de renglones y stock los controlan los triggers y
# sp_procesar_ingreso: la API no los replica.


def obtener_ingreso(conn, cod_ingreso):
    return conn.execute("""
        SELECT id_ingreso, cod_ingreso, fecha, estado, id_transportista, id_bodega
        FROM ingreso
        WHERE cod_ingreso = %s
    """, (cod_ingreso,)).fetchone()


def renglones_de_ingreso(conn, id_ingreso):
    return conn.execute("""
        SELECT r.id_vino, v.cod_vino, v.nombre_comercial, r.cantidad_botellas
        FROM renglon_ingreso r
        JOIN vino v ON v.id_vino = r.id_vino
        WHERE r.id_ingreso = %s
        ORDER BY v.cod_vino
    """, (id_ingreso,)).fetchall()


def insertar_ingreso(conn, cod_ingreso, id_transportista, id_bodega):
    # fecha (CURRENT_DATE) y estado ('en_confeccion') los pone el DEFAULT
    conn.execute("""
        INSERT INTO ingreso (cod_ingreso, id_transportista, id_bodega)
        VALUES (%s, %s, %s)
    """, (cod_ingreso, id_transportista, id_bodega))


def insertar_renglon(conn, id_ingreso, id_vino, cantidad_botellas):
    # Si el ingreso no está en confección, el trigger lo rechaza (RN-12)
    conn.execute("""
        INSERT INTO renglon_ingreso (id_ingreso, id_vino, cantidad_botellas)
        VALUES (%s, %s, %s)
    """, (id_ingreso, id_vino, cantidad_botellas))


def terminar_ingreso(conn, id_ingreso):
    # El trigger valida la transición en_confeccion -> terminado
    conn.execute("UPDATE ingreso SET estado = 'terminado' WHERE id_ingreso = %s", (id_ingreso,))


def procesar_ingreso(conn, id_ingreso):
    # Suma las botellas al depósito central y pasa a 'procesado' (todo en la base)
    conn.execute("CALL sp_procesar_ingreso(%s)", (id_ingreso,))
