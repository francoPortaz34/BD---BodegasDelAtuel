# Capa de acceso a datos de reportes: una función por consulta.
# Las cuatro primeras son las consultas S1, S8, S6 y S7 de consultas/select.sql (etapa 5).


def top_vinos(conn):
    # S1: los 10 vinos con más botellas vendidas en toda la red
    return conn.execute("""
        SELECT v.cod_vino, v.nombre_comercial, v.anada, v.presentacion_ml,
               SUM(d.cantidad) AS botellas_vendidas
        FROM detalle_comprobante d
        JOIN vino v ON v.id_vino = d.id_vino
        GROUP BY v.id_vino, v.cod_vino, v.nombre_comercial, v.anada, v.presentacion_ml
        ORDER BY botellas_vendidas DESC
        LIMIT 10
    """).fetchall()


def ventas_por_sala(conn):
    # S8: monto vendido por sala en el último trimestre (comprobante.total ya
    # tiene el descuento, lo calcularon los triggers)
    return conn.execute("""
        SELECT s.id_sala, l.nombre AS localidad, SUM(c.total) AS monto_total
        FROM comprobante c
        JOIN sala_de_ventas s ON s.id_sala = c.id_sala
        JOIN localidad l      ON l.id_localidad = s.id_localidad
        WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
        GROUP BY s.id_sala, l.nombre
        ORDER BY monto_total DESC
    """).fetchall()


def vinos_sin_stock(conn, id_sala):
    # S6: vinos sin stock en la sala pero con stock en el depósito central
    return conn.execute("""
        SELECT v.cod_vino, v.nombre_comercial, d.cantidad AS stock_deposito
        FROM stock_deposito d
        JOIN vino v ON v.id_vino = d.id_vino
        WHERE d.cantidad > 0
          AND NOT EXISTS (
              SELECT 1
              FROM stock_sala ss
              WHERE ss.id_sala = %s
                AND ss.id_vino = d.id_vino
                AND ss.cantidad > 0
          )
        ORDER BY v.nombre_comercial
    """, (id_sala,)).fetchall()


def transportista_activo(conn):
    # S7: transportista(s) con más ingresos en el último mes (si hay empate, todos)
    return conn.execute("""
        SELECT tr.cod_transporte, tr.razon_social, COUNT(i.id_ingreso) AS ingresos
        FROM transportista tr
        JOIN ingreso i ON i.id_transportista = tr.id_transportista
        WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
        GROUP BY tr.id_transportista, tr.cod_transporte, tr.razon_social
        HAVING COUNT(i.id_ingreso) = (
            SELECT MAX(cantidad)
            FROM (SELECT COUNT(*) AS cantidad
                  FROM ingreso
                  WHERE fecha >= CURRENT_DATE - INTERVAL '1 month'
                  GROUP BY id_transportista) AS por_transportista
        )
    """).fetchall()


# Trazabilidad de un vino: su recorrido por la red (depósito -> salas -> ventas)

def ingresos_del_vino(conn, id_vino):
    return conn.execute("""
        SELECT i.cod_ingreso, i.fecha, i.estado, tr.razon_social AS transportista,
               r.cantidad_botellas AS botellas
        FROM renglon_ingreso r
        JOIN ingreso i        ON i.id_ingreso = r.id_ingreso
        JOIN transportista tr ON tr.id_transportista = i.id_transportista
        WHERE r.id_vino = %s
        ORDER BY i.fecha, i.cod_ingreso
    """, (id_vino,)).fetchall()


def transferencias_del_vino(conn, id_vino):
    return conn.execute("""
        SELECT t.num_solicitud, t.fecha_confeccion, t.estado, t.id_sala,
               l.nombre AS localidad, r.cantidad_botellas AS botellas
        FROM renglon_transferencia r
        JOIN transferencia t  ON t.id_transferencia = r.id_transferencia
        JOIN sala_de_ventas s ON s.id_sala = t.id_sala
        JOIN localidad l      ON l.id_localidad = s.id_localidad
        WHERE r.id_vino = %s
        ORDER BY t.fecha_confeccion, t.num_solicitud
    """, (id_vino,)).fetchall()


def ventas_del_vino_por_sala(conn, id_vino):
    # Un vino aparece a lo sumo una vez por comprobante (PK), así que
    # COUNT(*) es la cantidad de comprobantes
    return conn.execute("""
        SELECT c.id_sala, l.nombre AS localidad, COUNT(*) AS comprobantes,
               SUM(d.cantidad) AS botellas
        FROM detalle_comprobante d
        JOIN comprobante c    ON c.id_comprobante = d.id_comprobante
        JOIN sala_de_ventas s ON s.id_sala = c.id_sala
        JOIN localidad l      ON l.id_localidad = s.id_localidad
        WHERE d.id_vino = %s
        GROUP BY c.id_sala, l.nombre
        ORDER BY c.id_sala
    """, (id_vino,)).fetchall()
