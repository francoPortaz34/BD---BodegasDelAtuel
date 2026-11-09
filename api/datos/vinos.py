# Capa de acceso a datos de vinos: una función por consulta, todas parametrizadas.
# Cada función recibe la conexión; la transacción la maneja la ruta.


def listar_vinos(conn, tipo, cepa, bodega, anada, limite, desde):
    # Cada filtro es opcional: si el parámetro es NULL, la condición no filtra.
    return conn.execute("""
        SELECT v.cod_vino, v.nombre_comercial, v.tipo, v.anada, v.presentacion_ml,
               v.graduacion_alcoholica, v.precio_venta, v.id_bodega, b.razon_social AS bodega
        FROM vino v
        JOIN bodega b ON b.id_bodega = v.id_bodega
        WHERE (%(tipo)s::tipo_vino IS NULL OR v.tipo = %(tipo)s)
          AND (%(bodega)s::integer IS NULL OR v.id_bodega = %(bodega)s)
          AND (%(anada)s::smallint IS NULL OR v.anada = %(anada)s)
          AND (%(cepa)s::text IS NULL OR EXISTS (
                SELECT 1
                FROM vino_cepa vc
                JOIN cepa c ON c.id_cepa = vc.id_cepa
                WHERE vc.id_vino = v.id_vino AND c.nombre = %(cepa)s))
        ORDER BY v.cod_vino
        LIMIT %(limite)s OFFSET %(desde)s
    """, {"tipo": tipo, "cepa": cepa, "bodega": bodega, "anada": anada,
          "limite": limite, "desde": desde}).fetchall()


def obtener_vino(conn, cod_vino):
    # Datos del vino y su bodega (basada en la consulta S9 de la etapa 5)
    return conn.execute("""
        SELECT v.id_vino, v.cod_vino, v.nombre_comercial, v.tipo, v.anada, v.presentacion_ml,
               v.graduacion_alcoholica, v.precio_venta, v.id_bodega, b.razon_social AS bodega
        FROM vino v
        JOIN bodega b ON b.id_bodega = v.id_bodega
        WHERE v.cod_vino = %s
    """, (cod_vino,)).fetchone()


def cepas_del_vino(conn, id_vino):
    return conn.execute("""
        SELECT c.id_cepa, c.nombre, vc.porcentaje_corte
        FROM vino_cepa vc
        JOIN cepa c ON c.id_cepa = vc.id_cepa
        WHERE vc.id_vino = %s
        ORDER BY vc.porcentaje_corte DESC
    """, (id_vino,)).fetchall()


def maridajes_del_vino(conn, id_vino):
    return conn.execute("""
        SELECT m.id_maridaje, m.nombre, m.temperatura_sugerida
        FROM vino_maridaje vm
        JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
        WHERE vm.id_vino = %s
        ORDER BY m.nombre
    """, (id_vino,)).fetchall()


def insertar_vino(conn, vino):
    return conn.execute("""
        INSERT INTO vino (cod_vino, nombre_comercial, tipo, anada, presentacion_ml,
                          graduacion_alcoholica, precio_venta, id_bodega)
        VALUES (%(cod_vino)s, %(nombre_comercial)s, %(tipo)s, %(anada)s, %(presentacion_ml)s,
                %(graduacion_alcoholica)s, %(precio_venta)s, %(id_bodega)s)
        RETURNING id_vino
    """, vino).fetchone()["id_vino"]


def insertar_corte(conn, id_vino, id_cepa, porcentaje_corte):
    conn.execute("""
        INSERT INTO vino_cepa (id_vino, id_cepa, porcentaje_corte)
        VALUES (%s, %s, %s)
    """, (id_vino, id_cepa, porcentaje_corte))


def actualizar_vino(conn, cod_vino, vino):
    """Actualiza la ficha. Devuelve el id_vino, o None si el vino no existe."""
    # Si cambia precio_venta, el trigger trg_vino_auditoria_precio registra la auditoría
    fila = conn.execute("""
        UPDATE vino
        SET nombre_comercial = %(nombre_comercial)s, tipo = %(tipo)s, anada = %(anada)s,
            presentacion_ml = %(presentacion_ml)s, graduacion_alcoholica = %(graduacion_alcoholica)s,
            precio_venta = %(precio_venta)s, id_bodega = %(id_bodega)s
        WHERE cod_vino = %(cod_vino)s
        RETURNING id_vino
    """, {**vino, "cod_vino": cod_vino}).fetchone()
    return fila["id_vino"] if fila is not None else None


def borrar_cortes(conn, id_vino):
    # Quita la composición actual para reemplazarla. La suma 100 (RN-05) la
    # controla el trigger diferido al COMMIT, con la composición final.
    conn.execute("DELETE FROM vino_cepa WHERE id_vino = %s", (id_vino,))


def borrar_maridajes(conn, id_vino):
    conn.execute("DELETE FROM vino_maridaje WHERE id_vino = %s", (id_vino,))


def insertar_maridaje(conn, id_vino, id_maridaje):
    # Maridaje inexistente -> FK (23503); repetido -> PK (23505)
    conn.execute("""
        INSERT INTO vino_maridaje (id_vino, id_maridaje)
        VALUES (%s, %s)
    """, (id_vino, id_maridaje))


def eliminar_vino(conn, cod_vino):
    fila = conn.execute("DELETE FROM vino WHERE cod_vino = %s RETURNING id_vino",
                        (cod_vino,)).fetchone()
    return fila is not None
