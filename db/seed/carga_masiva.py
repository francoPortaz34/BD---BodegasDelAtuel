"""
carga_masiva.py - Etapa 3: carga masiva de datos

Llena el esquema `bodegas` con datos coherentes:
  * Catálogos reales desde db/seed/csv/ (cepas, maridajes, departamentos,
    localidades y tipos de cliente).
  * El resto se genera con Faker y random, con semilla fija: dos ejecuciones
    con la misma semilla producen los mismos datos.
  * El historial se carga mes a mes, en orden: ingresos -> transferencias -> ventas.

Los triggers de la etapa 2 quedan ACTIVOS: calculan precios, descuentos,
totales y stock, y rechazan cualquier venta sin stock. Solo se desactiva
trg_transferencia_fecha mientras dura la carga, porque obliga a que la fecha de
confección sea la de hoy y el historial necesita fechas pasadas.

Todo corre en UNA transacción: si algo falla, no queda nada cargado.

Uso (desde la raíz del repo, con la base creada con las migraciones 001 a 007):
    uv run python db/seed/carga_masiva.py          # carga completa
    uv run python db/seed/carga_masiva.py 2000     # prueba con 2.000 comprobantes
"""
import csv
import os
import random
import sys
import time
from bisect import bisect_right
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

import psycopg
from faker import Faker

# ---------------------------------------------------------------------
# Parámetros
# ---------------------------------------------------------------------
SEMILLA = 2026
FECHA_INICIO = date(2021, 1, 1)   # primer mes con movimientos
FECHA_FIN = date(2026, 11, 6)     # último día con movimientos (fija: reproducible)

CANT_BODEGAS = 20
VINOS_POR_BODEGA = 20             # 400 vinos
CANT_SALAS = 25
VINOS_POR_SALA = 30               # surtido de cada sala
CANT_FINCAS = 60
CANT_TRANSPORTISTAS = 15
CANT_CLIENTES = 20_000
CANT_COMPROBANTES = 150_000       # unos 510.000 renglones
PRECIOS_A_CAMBIAR = 40            # cambios de precio al final (generan la auditoría)

DIR_SEED = Path(__file__).resolve().parent
DIR_CSV = DIR_SEED / "csv"
ARCHIVO_ENV = DIR_SEED.parent.parent / ".env"

rnd = random.Random(SEMILLA)
fake = Faker("es_AR")
fake.seed_instance(SEMILLA)


# ---------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------
def leer_csv(nombre):
    with open(DIR_CSV / nombre, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def fecha_al_azar(desde, hasta):
    return desde + timedelta(days=rnd.randint(0, (hasta - desde).days))


def mes_siguiente(m):
    return date(m.year + m.month // 12, m.month % 12 + 1, 1)


def decimal(valor, decimales=2):
    return Decimal(str(round(valor, decimales)))


def nuevo_unico(generar, usados):
    """Llama a generar() hasta obtener un valor que no esté en usados."""
    while True:
        valor = generar()
        if valor not in usados:
            usados.add(valor)
            return valor


cuits_usados = set()


def nuevo_cuit(prefijo):
    return nuevo_unico(lambda: f"{prefijo}{rnd.randint(10_000_000, 99_999_999)}{rnd.randint(0, 9)}", cuits_usados)


def reparto(n):
    """Porcentajes de corte de n cepas que suman 100, de mayor a menor."""
    if n == 1:
        return [100]
    if n == 2:
        a = rnd.choice([50, 60, 70, 75, 80, 85, 90])
        return [a, 100 - a]
    a = rnd.choice([50, 60, 70])
    b = rnd.choice([x for x in range(15, 100 - a - 5 + 1, 5) if x <= a])
    return sorted([a, b, 100 - a - b], reverse=True)


def leer_env():
    """Configuración de conexión: archivo .env de la raíz, pisado por variables de entorno."""
    datos = {}
    if ARCHIVO_ENV.exists():
        for linea in ARCHIVO_ENV.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if linea and not linea.startswith("#") and "=" in linea:
                clave, valor = linea.split("=", 1)
                datos[clave.strip()] = valor.strip()
    datos.update({k: v for k, v in os.environ.items() if k.startswith("POSTGRES_")})
    return datos


def conectar():
    env = leer_env()
    return psycopg.connect(host=env.get("POSTGRES_HOST", "localhost"),
                           port=env.get("POSTGRES_PORT", "55432"),
                           dbname=env.get("POSTGRES_DB", "bodegas_atuel"),
                           user=env.get("POSTGRES_USER", "bodegas_admin"),
                           password=env.get("POSTGRES_PASSWORD"),
                           options="-c search_path=bodegas")


def copiar(cur, tabla, columnas, filas):
    """Inserta muchas filas de una vez con COPY (carga por lotes)."""
    with cur.copy(f"COPY {tabla} ({', '.join(columnas)}) FROM STDIN") as cp:
        for fila in filas:
            cp.write_row(fila)


# ---------------------------------------------------------------------
# 1. Catálogos (CSV) y localidades
# ---------------------------------------------------------------------
def cargar_catalogos(cur):
    cepas = leer_csv("cepas.csv")
    copiar(cur, "cepa", ["id_cepa", "nombre", "tipo"],
           [(i, c["nombre"], c["tipo"]) for i, c in enumerate(cepas, 1)])

    maridajes = leer_csv("maridajes.csv")
    copiar(cur, "maridaje", ["id_maridaje", "nombre", "temperatura_sugerida"],
           [(i, m["nombre"], m["temperatura_sugerida"]) for i, m in enumerate(maridajes, 1)])

    tipos = leer_csv("tipos_cliente.csv")
    copiar(cur, "tipo_cliente", ["id_tipo_cliente", "nombre", "porcentaje_descuento"],
           [(i, t["nombre"], t["porcentaje_descuento"]) for i, t in enumerate(tipos, 1)])

    deptos = leer_csv("departamentos.csv")
    copiar(cur, "departamento", ["id_departamento", "nombre", "provincia"],
           [(i, d["nombre"], d["provincia"]) for i, d in enumerate(deptos, 1)])

    # Cada localidad tiene su propio encargado regional (RN-02)
    locs = leer_csv("localidades.csv")
    dnis = set()
    copiar(cur, "encargado", ["id_encargado", "nombre", "apellido", "dni"],
           [(i, fake.first_name(), fake.last_name(),
             str(nuevo_unico(lambda: rnd.randint(10_000_000, 45_999_999), dnis)))
            for i in range(1, len(locs) + 1)])
    copiar(cur, "localidad", ["id_localidad", "cod_postal", "nombre", "provincia", "id_encargado"],
           [(i, l["cod_postal"], l["nombre"], l["provincia"], i) for i, l in enumerate(locs, 1)])

    return {
        "tintas": [i for i, c in enumerate(cepas, 1) if c["tipo"] == "tinta"],
        "blancas": [i for i, c in enumerate(cepas, 1) if c["tipo"] == "blanca"],
        "cepa_id": {c["nombre"]: i for i, c in enumerate(cepas, 1)},
        "cepa_nombre": {i: c["nombre"] for i, c in enumerate(cepas, 1)},
        "maridaje_id": {m["nombre"]: i for i, m in enumerate(maridajes, 1)},
        "tipo_id": {t["nombre"]: i for i, t in enumerate(tipos, 1)},
        "n_deptos": len(deptos),
        "loc_id": {l["nombre"]: i for i, l in enumerate(locs, 1)},
        "n_locs": len(locs),
    }


# ---------------------------------------------------------------------
# 2. Salas de venta y empleados
# ---------------------------------------------------------------------
def cargar_salas(cur, cat):
    # Algunas salas fijas en San Rafael y General Alvear (las usan las consultas de la etapa 5)
    locs = ([cat["loc_id"]["Ciudad de San Rafael"]] * 3 + [cat["loc_id"]["Ciudad de General Alvear"]] * 2
            + rnd.sample(range(1, cat["n_locs"] + 1), CANT_SALAS - 5))
    salas = []
    for i, id_loc in enumerate(locs, 1):
        cierre = rnd.choice(["lunes", "lunes", "martes", "miercoles", "miercoles", "domingo"])
        salas.append((i, fake.street_name(), str(rnd.randint(1, 3000)), cierre, id_loc))
    copiar(cur, "sala_de_ventas", ["id_sala", "calle", "numero", "dia_cierre_semanal", "id_localidad"], salas)

    empleados = []
    for id_sala in range(1, CANT_SALAS + 1):
        for _ in range(rnd.randint(4, 6)):
            empleados.append((len(empleados) + 1, nuevo_cuit(rnd.choice([20, 27])), fake.name(),
                              fecha_al_azar(date(2010, 1, 1), date(2026, 6, 30)),
                              Decimal(rnd.randrange(900_000, 2_500_001, 1000)), id_sala))
    copiar(cur, "empleado", ["id_empleado", "cuit", "nombre", "fecha_ingreso", "salario", "id_sala"], empleados)

    dias = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
    return {s[0]: dias.index(s[3]) + 1 for s in salas}   # id_sala -> día de cierre (1 = lunes)


# ---------------------------------------------------------------------
# 3. Bodegas y vinos
# ---------------------------------------------------------------------
LINEAS = ["Reserva", "Gran Reserva", "Roble", "Joven", "Selección", "Clásico", "Premium", "Familia"]
MARIDAJES_POR_TIPO = {
    "tinto": ["Carnes rojas", "Quesos duros", "Pastas con salsa roja"],
    "blanco": ["Carnes blancas", "Pescados y mariscos", "Quesos blandos"],
    "rosado": ["Entradas y fiambres", "Carnes blancas", "Pastas con salsa roja"],
    "espumante": ["Postres", "Entradas y fiambres", "Pescados y mariscos"],
}
GRADUACION_POR_TIPO = {"tinto": (13.0, 15.5), "blanco": (12.0, 14.0), "rosado": (12.0, 13.5), "espumante": (11.0, 12.5)}


def cargar_bodegas_y_vinos(cur, cat):
    nombres = set()
    bodegas = [(i, nuevo_cuit(30), nuevo_unico(lambda: f"Bodega {fake.last_name()}", nombres),
                fake.street_name(), str(rnd.randint(1, 5000))) for i in range(1, CANT_BODEGAS + 1)]
    copiar(cur, "bodega", ["id_bodega", "cuit", "razon_social", "calle", "numero"], bodegas)

    vinos, composicion, maridajes = [], [], []
    datos = {}            # id_vino -> (id_bodega, desde qué fecha se puede vender)
    claves = set()        # (nombre, añada, presentación) no se repite
    for id_vino in range(1, CANT_BODEGAS * VINOS_POR_BODEGA + 1):
        id_bodega = (id_vino - 1) // VINOS_POR_BODEGA + 1
        if id_vino == 1:
            # El ejemplo de la consigna
            tipo, anada, ml, grad, precio = "tinto", 2021, 750, Decimal("14.00"), Decimal(12500)
            cepas = [(cat["cepa_id"]["Malbec"], 85), (cat["cepa_id"]["Cabernet Sauvignon"], 15)]
            nombre, elegidos = "Malbec Reserva", ["Carnes rojas", "Quesos duros"]
        else:
            tipo = rnd.choices(["tinto", "blanco", "rosado", "espumante"], weights=[60, 25, 8, 7])[0]
            if tipo == "blanco":
                opciones, n = cat["blancas"], rnd.choices([1, 2], weights=[80, 20])[0]
            elif tipo == "espumante":
                opciones, n = cat["blancas"] + [cat["cepa_id"]["Pinot Noir"]], rnd.choice([1, 2])
            else:
                opciones, n = cat["tintas"], rnd.choices([1, 2, 3], weights=[60, 30, 10])[0]
            cepas = list(zip(rnd.sample(opciones, n), reparto(n)))
            while True:
                nombre = f"{cat['cepa_nombre'][cepas[0][0]]} {rnd.choice(LINEAS)}"
                anada = rnd.randint(2015, 2025)
                ml = rnd.choices([187, 375, 750, 1500, 3000], weights=[3, 10, 75, 10, 2])[0]
                if (nombre, anada, ml) not in claves:
                    break
            grad = decimal(rnd.uniform(*GRADUACION_POR_TIPO[tipo]), 1)
            precio = Decimal(rnd.randrange(3000, 30001, 100))
            elegidos = rnd.sample(MARIDAJES_POR_TIPO[tipo], rnd.randint(1, 3))
        claves.add((nombre, anada, ml))
        vinos.append((id_vino, f"V{id_vino:04d}", nombre, tipo, anada, ml, grad, precio, id_bodega))
        composicion += [(id_vino, id_cepa, pct) for id_cepa, pct in cepas]
        maridajes += [(id_vino, cat["maridaje_id"][m]) for m in elegidos]
        # Un vino se vende desde marzo del año siguiente a su añada
        datos[id_vino] = (id_bodega, max(FECHA_INICIO, date(anada + 1, 3, 1)))

    copiar(cur, "vino", ["id_vino", "cod_vino", "nombre_comercial", "tipo", "anada", "presentacion_ml",
                         "graduacion_alcoholica", "precio_venta", "id_bodega"], vinos)
    copiar(cur, "vino_cepa", ["id_vino", "id_cepa", "porcentaje_corte"], composicion)
    copiar(cur, "vino_maridaje", ["id_vino", "id_maridaje"], maridajes)
    return datos


# ---------------------------------------------------------------------
# 4. Producción: fincas, parcelas, lotes de uva y análisis
# ---------------------------------------------------------------------
def cargar_produccion(cur, cat):
    fincas, parcelas, lotes, analisis = [], [], [], []
    for id_finca in range(1, CANT_FINCAS + 1):
        sup_finca = rnd.uniform(20, 300)
        fincas.append((id_finca, f"Finca {fake.last_name()}", decimal(sup_finca), rnd.randint(1, cat["n_deptos"])))
        n = rnd.randint(3, 12)
        for num in range(1, n + 1):
            sup = max(sup_finca * 0.9 / n * rnd.uniform(0.7, 1.3), 0.5)
            parcelas.append((id_finca, num, decimal(sup), rnd.randint(1985, 2020),
                             rnd.choice(cat["tintas"] + cat["blancas"])))
            for campania in range(2021, 2027):          # RN-04: una cosecha por campaña
                if rnd.random() < 0.1:
                    continue                            # ese año no se cosechó
                id_lote = len(lotes) + 1
                cosecha = fecha_al_azar(date(campania, 2, 1), date(campania, 4, 30))
                lotes.append((id_lote, f"L{campania}-{id_lote:05d}", id_finca, num, campania, cosecha,
                              decimal(sup * rnd.uniform(6000, 15000)), rnd.randint(1, CANT_BODEGAS)))
                for _ in range(rnd.randint(1, 3)):
                    analisis.append((len(analisis) + 1, id_lote, cosecha + timedelta(days=rnd.randint(0, 10)),
                                     decimal(rnd.uniform(20, 27), 1), decimal(rnd.uniform(3.2, 3.9)),
                                     decimal(rnd.uniform(4.5, 8.0))))
    copiar(cur, "finca", ["id_finca", "nombre", "sup_total_ha", "id_departamento"], fincas)
    copiar(cur, "parcela", ["id_finca", "num_parcela", "superficie", "anio_plantacion", "id_cepa"], parcelas)
    copiar(cur, "lote_de_uva", ["id_lote_uva", "num_lote", "id_finca", "num_parcela", "campania",
                                "fecha_cosecha", "kilos_cosechados", "id_bodega_entrega"], lotes)
    copiar(cur, "analisis_calidad", ["id_analisis", "id_lote_uva", "fecha", "grado_brix", "ph", "acidez_total"],
           analisis)


# ---------------------------------------------------------------------
# 5. Clientes (supertipo + subtipos) y permisos de exportación
# ---------------------------------------------------------------------
def cargar_clientes(cur, cat):
    clientes, socios, distribuidores, exportadores, permisos = [], [], [], [], []
    dnis = set()
    for id_cli in range(1, CANT_CLIENTES + 1):
        tipo = rnd.choices(["Socio", "Distribuidor", "Exportador"], weights=[85, 10, 5])[0]
        alta = fecha_al_azar(date(2015, 1, 1), date(2026, 9, 30))
        if tipo == "Socio":
            nombre, tipo_doc = fake.name(), "DNI"
            doc = str(nuevo_unico(lambda: rnd.randint(10_000_000, 45_999_999), dnis))
            socios.append((id_cli,))
        else:
            nombre, tipo_doc, doc = fake.company(), "CUIT", nuevo_cuit(30)
            if tipo == "Distribuidor":
                distribuidores.append((id_cli, rnd.choice(["Cuyo", "Centro", "Norte", "Litoral", "Patagonia"]),
                                       f"HAB-{id_cli:06d}"))
            else:
                exportadores.append((id_cli, rnd.choice(["Brasil", "Chile", "Estados Unidos", "China", "España"])))
                for _ in range(rnd.randint(1, 5)):      # RN-07: varios permisos por exportador
                    emision = fecha_al_azar(alta, min(alta + timedelta(days=1000), FECHA_FIN))
                    permisos.append((len(permisos) + 1, f"PE-{len(permisos) + 1:06d}", emision,
                                     emision + timedelta(days=rnd.randint(365, 1095)), id_cli))
        clientes.append((id_cli, nombre, tipo_doc, doc, fake.street_name(), str(rnd.randint(1, 5000)), alta,
                         rnd.randint(1, cat["n_locs"]), cat["tipo_id"][tipo]))

    copiar(cur, "cliente", ["id_cliente", "nombre_o_razon_social", "tipo_documento", "num_documento", "calle",
                            "numero", "fecha_alta", "id_localidad", "id_tipo_cliente"], clientes)
    copiar(cur, "socio", ["id_cliente"], socios)
    copiar(cur, "distribuidor", ["id_cliente", "zona_cobertura", "numero_habilitacion"], distribuidores)
    copiar(cur, "exportador", ["id_cliente", "pais_destino_principal"], exportadores)
    copiar(cur, "permiso_exportacion", ["id_permiso", "codigo", "fecha_emision", "fecha_vencimiento",
                                        "id_cliente"], permisos)

    # El 15 % nunca compró. Los compradores se ordenan por fecha de alta para elegir
    # rápido los que ya eran clientes en una fecha dada.
    compradores = sorted((c[6], c[0], c[8] == cat["tipo_id"]["Socio"]) for c in clientes if rnd.random() < 0.85)
    return compradores


# ---------------------------------------------------------------------
# 6. Transportistas
# ---------------------------------------------------------------------
def cargar_transportistas(cur, cat):
    nombres = set()
    transp, emails, telefonos, cobertura = [], [], [], []
    for i in range(1, CANT_TRANSPORTISTAS + 1):
        transp.append((i, f"T{i:03d}", nuevo_unico(lambda: f"Transportes {fake.last_name()}", nombres),
                       nuevo_cuit(30), fake.street_name(), str(rnd.randint(1, 5000))))
        emails += [(i, f"{u}@transportes{i}.com.ar") for u in ["contacto", "ventas"][:rnd.randint(1, 2)]]
        telefonos += [(i, f"261-{rnd.randint(4000000, 4999999)}{j}") for j in range(rnd.randint(1, 2))]
        cobertura += [(i, l) for l in rnd.sample(range(1, cat["n_locs"] + 1), rnd.randint(3, 6))]
    copiar(cur, "transportista", ["id_transportista", "cod_transporte", "razon_social", "cuit", "calle", "numero"],
           transp)
    copiar(cur, "transportista_email", ["id_transportista", "email"], emails)
    copiar(cur, "transportista_telefono", ["id_transportista", "telefono"], telefonos)
    copiar(cur, "transportista_localidad", ["id_transportista", "id_localidad"], cobertura)


# ---------------------------------------------------------------------
# 7. Movimientos mes a mes: ingresos -> transferencias -> ventas
# ---------------------------------------------------------------------
def procesar_documentos(cur, tabla, columna, procedimiento, ids):
    """Pasa los documentos a 'terminado' y los procesa con el procedimiento de la etapa 2."""
    cur.execute(f"UPDATE {tabla} SET estado = 'terminado' WHERE {columna} = ANY(%s)", (ids,))
    for id_doc in ids:
        cur.execute(f"CALL {procedimiento}(%s)", (id_doc,))


def cargar_movimientos(cur, vinos, cierre_sala, compradores, total_comprobantes):
    lista_meses = []
    m = FECHA_INICIO
    while m <= FECHA_FIN:
        lista_meses.append(m)
        m = mes_siguiente(m)
    por_mes = [total_comprobantes // len(lista_meses)] * len(lista_meses)
    for k in range(total_comprobantes % len(lista_meses)):
        por_mes[k] += 1

    surtido = {s: rnd.sample(list(vinos), VINOS_POR_SALA) for s in cierre_sala}
    peso_sala = [rnd.uniform(0.5, 1.5) for _ in cierre_sala]
    altas = [c[0] for c in compradores]
    ids = defaultdict(int)          # último id usado en cada tabla

    for mes, cantidad in zip(lista_meses, por_mes):
        fin = min(mes_siguiente(mes) - timedelta(days=1), FECHA_FIN)
        primer_dia_venta = mes + timedelta(days=3)   # días 1 a 3: llegan los ingresos y las transferencias

        # 7.1 Ventas del mes (primero se generan, para saber cuánto stock hace falta)
        ventas, demanda = [], defaultdict(int)
        habilitados = compradores[:bisect_right(altas, mes)]    # clientes dados de alta antes del mes
        while len(ventas) < cantidad:
            id_sala = rnd.choices(list(cierre_sala), weights=peso_sala)[0]
            fecha = fecha_al_azar(primer_dia_venta, fin)
            if fecha.isoweekday() == cierre_sala[id_sala]:
                continue                                         # ese día la sala está cerrada
            disponibles = [v for v in surtido[id_sala] if vinos[v][1] <= fecha]
            if not disponibles or not habilitados:
                continue
            _, id_cli, es_socio = rnd.choice(habilitados)
            n = min(len(disponibles), rnd.choices([1, 2, 3, 4, 5, 6], weights=[10, 20, 25, 20, 15, 10])[0])
            renglones = [(v, rnd.randint(1, 6) if es_socio else rnd.randint(6, 24))
                         for v in rnd.sample(disponibles, n)]
            for v, q in renglones:
                demanda[(id_sala, v)] += q
            ventas.append((fecha, id_cli, id_sala, renglones))

        # 7.2 Transferencias: cada sala pide lo que va a vender en el mes (más un margen)
        transf, ren_transf, pedido = [], [], defaultdict(int)
        for id_sala in sorted({s for s, _ in demanda}):
            ids["transferencia"] += 1
            id_t = ids["transferencia"]
            transf.append((id_t, f"TR-{id_t:06d}", mes + timedelta(days=1), id_sala))
            for (s, v), q in sorted(demanda.items()):
                if s == id_sala:
                    ids["renglon_transferencia"] += 1
                    total = q + rnd.randint(0, 12)
                    ren_transf.append((ids["renglon_transferencia"], id_t, v, total))
                    pedido[v] += total

        # 7.3 Ingresos: cada bodega manda al depósito lo que las salas van a pedir (más un margen)
        ingresos, ren_ing = [], []
        for id_bodega in sorted({vinos[v][0] for v in pedido}):
            ids["ingreso"] += 1
            id_i = ids["ingreso"]
            ingresos.append((id_i, f"IN-{id_i:06d}", mes, rnd.randint(1, CANT_TRANSPORTISTAS), id_bodega))
            for v in sorted(pedido):
                if vinos[v][0] == id_bodega:
                    ids["renglon_ingreso"] += 1
                    ren_ing.append((ids["renglon_ingreso"], id_i, v, pedido[v] + rnd.randint(0, 24)))

        # Carga en la base, en orden cronológico
        copiar(cur, "ingreso", ["id_ingreso", "cod_ingreso", "fecha", "id_transportista", "id_bodega"], ingresos)
        copiar(cur, "renglon_ingreso", ["id_renglon_ingreso", "id_ingreso", "id_vino", "cantidad_botellas"], ren_ing)
        procesar_documentos(cur, "ingreso", "id_ingreso", "sp_procesar_ingreso", [i[0] for i in ingresos])

        copiar(cur, "transferencia", ["id_transferencia", "num_solicitud", "fecha_confeccion", "id_sala"], transf)
        copiar(cur, "renglon_transferencia", ["id_renglon_transferencia", "id_transferencia", "id_vino",
                                              "cantidad_botellas"], ren_transf)
        procesar_documentos(cur, "transferencia", "id_transferencia", "sp_procesar_transferencia",
                            [t[0] for t in transf])

        # Ventas: precio, descuento y subtotal van en 0 y los completa el trigger de la venta (RN-01, RN-06);
        # otro trigger descuenta el stock y calcula los totales del comprobante (RN-08, RN-09).
        ventas.sort()
        comprobantes, detalle = [], []
        for fecha, id_cli, id_sala, renglones in ventas:
            ids["comprobante"] += 1
            id_c = ids["comprobante"]
            comprobantes.append((id_c, f"C-{id_c:08d}", fecha, id_cli, id_sala))
            detalle += [(id_c, v, q, 0, 0, 0) for v, q in renglones]
        copiar(cur, "comprobante", ["id_comprobante", "num_comprobante", "fecha", "id_cliente", "id_sala"],
               comprobantes)
        copiar(cur, "detalle_comprobante", ["id_comprobante", "id_vino", "cantidad", "precio_unitario_venta",
                                            "descuento_aplicado", "subtotal_renglon"], detalle)
        if mes.month == 12 or mes == lista_meses[-1]:
            print(f"   {mes.year}: {ids['comprobante']:>7} comprobantes cargados")

    # 7.4 Algunos documentos quedan pendientes (para la vista de pendientes y la consulta S5)
    for k in range(10):
        ids["transferencia"] += 1
        id_t, id_sala = ids["transferencia"], rnd.choice(list(cierre_sala))
        copiar(cur, "transferencia", ["id_transferencia", "num_solicitud", "fecha_confeccion", "id_sala"],
               [(id_t, f"TR-{id_t:06d}", FECHA_FIN, id_sala)])
        filas = []
        for v in rnd.sample(surtido[id_sala], 3):
            ids["renglon_transferencia"] += 1
            filas.append((ids["renglon_transferencia"], id_t, v, rnd.randint(6, 48)))
        copiar(cur, "renglon_transferencia", ["id_renglon_transferencia", "id_transferencia", "id_vino",
                                              "cantidad_botellas"], filas)
        if k % 2:
            cur.execute("UPDATE transferencia SET estado = 'terminado' WHERE id_transferencia = %s", (id_t,))
    for _ in range(5):
        ids["ingreso"] += 1
        id_bodega = rnd.randint(1, CANT_BODEGAS)
        copiar(cur, "ingreso", ["id_ingreso", "cod_ingreso", "fecha", "id_transportista", "id_bodega"],
               [(ids["ingreso"], f"IN-{ids['ingreso']:06d}", FECHA_FIN, rnd.randint(1, CANT_TRANSPORTISTAS),
                 id_bodega)])
        ids["renglon_ingreso"] += 1
        v = rnd.choice([v for v in vinos if vinos[v][0] == id_bodega])
        copiar(cur, "renglon_ingreso", ["id_renglon_ingreso", "id_ingreso", "id_vino", "cantidad_botellas"],
               [(ids["renglon_ingreso"], ids["ingreso"], v, rnd.randint(50, 200))])


# ---------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------
def main():
    sys.stdout.reconfigure(encoding="utf-8")
    total_comprobantes = int(sys.argv[1]) if len(sys.argv) > 1 else CANT_COMPROBANTES
    inicio = time.perf_counter()

    with conectar() as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM vino")
        if cur.fetchone()[0] > 0:
            sys.exit("La base ya tiene datos. Recrearla con las migraciones 001 a 007 antes de cargar.")

        # La fecha de confección de las transferencias del historial es pasada (ver encabezado)
        cur.execute("ALTER TABLE transferencia DISABLE TRIGGER trg_transferencia_fecha")

        t = time.perf_counter()
        cat = cargar_catalogos(cur)
        cierre_sala = cargar_salas(cur, cat)
        vinos = cargar_bodegas_y_vinos(cur, cat)
        cargar_produccion(cur, cat)
        compradores = cargar_clientes(cur, cat)
        cargar_transportistas(cur, cat)
        print(f"1. Catálogos y datos base: {time.perf_counter() - t:.1f} s")

        t = time.perf_counter()
        print("2. Movimientos (ingresos, transferencias y ventas):")
        cargar_movimientos(cur, vinos, cierre_sala, compradores, total_comprobantes)
        print(f"   {time.perf_counter() - t:.1f} s")

        # Cambios de precio posteriores a las ventas: el trigger de auditoría los registra (RN-13)
        cur.execute("UPDATE vino SET precio_venta = round(precio_venta * 1.10, -1) WHERE id_vino = ANY(%s)",
                    (rnd.sample(sorted(vinos), PRECIOS_A_CAMBIAR),))

        cur.execute("ALTER TABLE transferencia ENABLE TRIGGER trg_transferencia_fecha")

        # Los id se cargaron a mano: cada secuencia sigue desde el máximo usado
        cur.execute("""SELECT table_name, column_name FROM information_schema.columns
                       WHERE table_schema = 'bodegas' AND column_default LIKE 'nextval%'""")
        for tabla, columna in cur.fetchall():
            cur.execute(f"SELECT setval(pg_get_serial_sequence('bodegas.{tabla}', '{columna}'), "
                        f"COALESCE((SELECT max({columna}) FROM {tabla}), 0) + 1, false)")
        cur.execute("REFRESH MATERIALIZED VIEW mv_ventas_mensuales_sala")
    # al salir del "with" se hace COMMIT (acá se controla también la suma 100 de las cepas)

    print(f"Carga terminada en {time.perf_counter() - inicio:.1f} s\n")

    with conectar() as conn, conn.cursor() as cur:
        cur.execute("ANALYZE")
        cur.execute((DIR_SEED / "validaciones.sql").read_text(encoding="utf-8"))
        fallas = 0
        for orden, control, valor, resultado in cur.fetchall():
            print(f"{resultado:<5} {control}: {valor}")
            fallas += resultado == "FALLA"
    if fallas:
        sys.exit(f"\n{fallas} controles con FALLA")
    print("\nTodos los controles dieron OK")


if __name__ == "__main__":
    main()
