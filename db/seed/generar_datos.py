"""
generar_datos.py  -  Etapa 3, pasos 3 y 4
Genera datos coherentes para todas las tablas del esquema `bodegas` y los
guarda como un CSV por tabla en db/seed/generados/ (en orden de carga).
Reproducible: semilla y fecha de corte fijas. Los id se asignan acá, así
que después de cargar hay que actualizar las secuencias con setval.
"""

import csv
import random
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

from faker import Faker

# ---------------------------------------------------------------------
# Parámetros
# ---------------------------------------------------------------------
SEMILLA = 42
FECHA_CORTE = date(2026, 11, 5)    # "hoy" de los datos (fija para que sea reproducible)
INICIO_VENTAS = date(2020, 11, 1)  # 6 años de historia de ventas

CANT_FINCAS = 60
CANT_BODEGAS = 20
VINOS_POR_BODEGA = 20              # 400 vinos
CANT_SALAS = 25
VINOS_POR_SALA = 28                # surtido de cada sala
CANT_TRANSPORTISTAS = 15
CANT_CLIENTES = 20_000
CANT_COMPROBANTES = 150_000        # ~510.000 renglones
DOCUMENTOS_PENDIENTES = 40         # ingresos y transferencias sin procesar

BASE = Path(__file__).resolve().parent
DIR_CATALOGOS = BASE / "csv"
DIR_SALIDA = BASE / "generados"

rnd = random.Random(SEMILLA)
Faker.seed(SEMILLA)
fake = Faker("es_AR")

tablas = {}   # nombre de tabla -> (columnas, filas)


def tabla(nombre, columnas):
    tablas[nombre] = (columnas, [])
    return tablas[nombre][1]


# ---------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------
def fecha_entre(desde, hasta):
    return desde + timedelta(days=rnd.randint(0, (hasta - desde).days))


def sumar_meses(f, meses):
    m = f.month - 1 + meses
    return date(f.year + m // 12, m % 12 + 1, 1)


def dinero(x):
    return Decimal(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def cuit(prefijo, usados):
    while True:
        valor = f"{prefijo}{rnd.randint(10_000_000, 99_999_999)}{rnd.randint(0, 9)}"
        if valor not in usados:
            usados.add(valor)
            return valor


def leer_catalogo(archivo):
    with open(DIR_CATALOGOS / archivo, encoding="utf-8") as f:
        return list(csv.DictReader(f))


# =====================================================================
# 1. CATÁLOGOS (CSV de db/seed/csv/)
# =====================================================================
def generar_catalogos():
    cepas = tabla("cepa", ["id_cepa", "nombre", "tipo"])
    for i, fila in enumerate(leer_catalogo("cepas.csv"), start=1):
        cepas.append((i, fila["nombre"], fila["tipo"]))

    maridajes = tabla("maridaje", ["id_maridaje", "nombre", "temperatura_sugerida"])
    for i, fila in enumerate(leer_catalogo("maridajes.csv"), start=1):
        maridajes.append((i, fila["nombre"], fila["temperatura_sugerida"]))

    departamentos = tabla("departamento", ["id_departamento", "nombre", "provincia"])
    for i, fila in enumerate(leer_catalogo("departamentos.csv"), start=1):
        departamentos.append((i, fila["nombre"], fila["provincia"]))

    # Socio 10 %, Distribuidor 20 %, Exportador 30 % (RN-06), en ese orden
    tipos = tabla("tipo_cliente", ["id_tipo_cliente", "nombre", "porcentaje_descuento"])
    for i, fila in enumerate(leer_catalogo("tipos_cliente.csv"), start=1):
        tipos.append((i, fila["nombre"], Decimal(fila["porcentaje_descuento"])))


# =====================================================================
# 2. RED COMERCIAL: encargados, localidades, salas, empleados
# =====================================================================
def generar_red_comercial():
    filas_loc = leer_catalogo("localidades.csv")

    encargados = tabla("encargado", ["id_encargado", "nombre", "apellido", "dni"])
    localidades = tabla("localidad", ["id_localidad", "cod_postal", "nombre", "provincia", "id_encargado"])
    dnis = rnd.sample(range(20_000_000, 45_000_000), len(filas_loc))
    for i, fila in enumerate(filas_loc, start=1):
        # Una localidad tiene un único encargado y viceversa (1:1)
        encargados.append((i, fake.first_name(), fake.last_name(), str(dnis[i - 1])))
        localidades.append((i, fila["cod_postal"], fila["nombre"], fila["provincia"], i))

    dias = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
    salas = tabla("sala_de_ventas", ["id_sala", "calle", "numero", "dia_cierre_semanal", "id_localidad"])
    for i in range(1, CANT_SALAS + 1):
        salas.append((i, fake.street_name(), str(rnd.randint(10, 3000)), rnd.choice(dias),
                      rnd.randint(1, len(localidades))))

    empleados = tabla("empleado", ["id_empleado", "cuit", "nombre", "fecha_ingreso", "salario", "id_sala"])
    cuits = set()
    for id_sala in range(1, CANT_SALAS + 1):
        for _ in range(rnd.randint(3, 8)):
            empleados.append((
                len(empleados) + 1,
                cuit(rnd.choice(["20", "23", "27"]), cuits),
                f"{fake.last_name()}, {fake.first_name()}",
                fecha_entre(date(2010, 1, 1), FECHA_CORTE - timedelta(days=30)),
                dinero(rnd.randint(650, 1_600) * 1000),
                id_sala,
            ))


# =====================================================================
# 3. PRODUCCIÓN: fincas, parcelas, lotes de uva, análisis de calidad
# =====================================================================
def generar_produccion():
    cant_deptos = len(tablas["departamento"][1])
    cant_cepas = len(tablas["cepa"][1])

    fincas = tabla("finca", ["id_finca", "nombre", "sup_total_ha", "id_departamento"])
    parcelas = tabla("parcela", ["id_finca", "num_parcela", "superficie", "anio_plantacion", "id_cepa"])
    for id_finca in range(1, CANT_FINCAS + 1):
        superficies = [dinero(rnd.uniform(1.5, 12)) for _ in range(rnd.randint(6, 18))]
        # La superficie total de la finca incluye sus parcelas y algo más
        total = dinero(sum(superficies) * Decimal("1.2"))
        fincas.append((id_finca, f"Finca {fake.last_name()}", total, rnd.randint(1, cant_deptos)))
        for num, sup in enumerate(superficies, start=1):
            parcelas.append((id_finca, num, sup, rnd.randint(1985, 2020), rnd.randint(1, cant_cepas)))

    lotes = tabla("lote_de_uva", ["id_lote_uva", "num_lote", "id_finca", "num_parcela", "campania",
                                  "fecha_cosecha", "kilos_cosechados", "id_bodega_entrega"])
    analisis = tabla("analisis_calidad", ["id_analisis", "id_lote_uva", "fecha", "grado_brix", "ph", "acidez_total"])
    for campania in range(2016, FECHA_CORTE.year + 1):
        for (id_finca, num, sup, anio_plant, _cepa) in parcelas:
            # Se cosecha desde el 3er año de plantada, a lo sumo una vez por campaña (RN-04)
            if campania < anio_plant + 3 or rnd.random() < 0.10:
                continue
            id_lote = len(lotes) + 1
            cosecha = fecha_entre(date(campania, 2, 1), date(campania, 4, 30))   # Anexo B.4
            kilos = dinero(sup * rnd.randint(5_000, 14_000))                      # rendimiento kg/ha
            lotes.append((id_lote, f"L{campania}-{id_lote:06d}", id_finca, num, campania,
                          cosecha, kilos, rnd.randint(1, CANT_BODEGAS)))
            for _ in range(rnd.randint(1, 3)):
                analisis.append((len(analisis) + 1, id_lote, cosecha + timedelta(days=rnd.randint(0, 10)),
                                 round(rnd.uniform(20, 27), 1), round(rnd.uniform(3.2, 3.9), 2),
                                 round(rnd.uniform(4.5, 7.5), 2)))


# =====================================================================
# 4. BODEGAS Y VINOS: bodegas, vinos, composición, maridajes, auditoría
# =====================================================================
def generar_bodegas_y_vinos():
    cuits = set()
    bodegas = tabla("bodega", ["id_bodega", "cuit", "razon_social", "calle", "numero"])
    for i in range(1, CANT_BODEGAS + 1):
        bodegas.append((i, cuit("30", cuits), f"Bodega {fake.last_name()} S.A.",
                        fake.street_name(), str(rnd.randint(10, 9000))))

    cepas = tablas["cepa"][1]
    tintas = [c[0] for c in cepas if c[2] == "tinta"]
    blancas = [c[0] for c in cepas if c[2] == "blanca"]
    nombre_cepa = {c[0]: c[1] for c in cepas}
    id_maridajes = [m[0] for m in tablas["maridaje"][1]]
    lineas = ["Joven", "Roble", "Reserva", "Gran Reserva", "Premium", "Familia"]
    cortes = [[100], [100], [85, 15], [60, 40], [50, 30, 20]]   # porcentajes que suman 100

    vinos = tabla("vino", ["id_vino", "cod_vino", "nombre_comercial", "tipo", "anada", "presentacion_ml",
                           "graduacion_alcoholica", "precio_venta", "id_bodega"])
    composicion = tabla("vino_cepa", ["id_vino", "id_cepa", "porcentaje_corte"])
    vino_maridaje = tabla("vino_maridaje", ["id_vino", "id_maridaje"])
    claves = set()

    for id_bodega in range(1, CANT_BODEGAS + 1):
        cant = 0
        while cant < VINOS_POR_BODEGA:
            tipo = rnd.choices(["tinto", "blanco", "rosado", "espumante"], weights=[60, 25, 8, 7])[0]
            base = tintas if tipo in ("tinto", "rosado") else blancas if tipo == "blanco" else tintas + blancas
            pcts = rnd.choice(cortes)
            elegidas = rnd.sample(base, len(pcts))
            principal = nombre_cepa[elegidas[0]]
            nombre = f"{rnd.choice(lineas)} {principal}" if len(pcts) == 1 else f"{rnd.choice(lineas)} Blend {principal}"
            # Añada: cerca de la mitad de los vinos ya se vendían en 2020
            anada = rnd.choice([2014, 2015, 2016, 2017, 2018, 2019] * 2 + list(range(2020, 2026)))
            ml = rnd.choices([750, 375, 1500, 187, 3000], weights=[70, 10, 12, 5, 3])[0]
            if (nombre, anada, ml) in claves:                     # UNIQUE (nombre, añada, presentación)
                continue
            claves.add((nombre, anada, ml))
            cant += 1
            id_vino = len(vinos) + 1
            precio = round(rnd.randint(8_000, 60_000) * ml / 750, -2)
            vinos.append((id_vino, f"V{id_vino:05d}", nombre, tipo, anada, ml,
                          round(rnd.uniform(11.0, 15.5), 2), dinero(precio), id_bodega))
            for id_cepa, pct in zip(elegidas, pcts):
                composicion.append((id_vino, id_cepa, pct))       # RN-05: suman 100
            for id_mar in rnd.sample(id_maridajes, rnd.randint(1, 3)):
                vino_maridaje.append((id_vino, id_mar))

    # Auditoría (RN-13): algunos vinos cambiaron de precio ANTES de salir a la
    # venta, así todas las ventas usan el precio actual y siguen siendo coherentes
    auditoria = tabla("auditoria_precio", ["id_auditoria", "id_vino", "precio_anterior", "precio_nuevo",
                                           "fecha_hora", "usuario"])
    for v in rnd.sample(vinos, 40):
        cambio = fecha_entre(date(v[4], 6, 1), date(v[4] + 1, 2, 28))
        auditoria.append((len(auditoria) + 1, v[0], dinero(round(float(v[7]) * 0.85, -2)), v[7],
                          datetime.combine(cambio, time(10, 0)), "bodegas_owner"))


# =====================================================================
# 5. CLIENTES: clientes, subtipos y permisos de exportación
# =====================================================================
def generar_clientes():
    cant_loc = len(tablas["localidad"][1])
    clientes = tabla("cliente", ["id_cliente", "nombre_o_razon_social", "tipo_documento", "num_documento",
                                 "calle", "numero", "fecha_alta", "id_localidad", "id_tipo_cliente"])
    socios = tabla("socio", ["id_cliente"])
    distribuidores = tabla("distribuidor", ["id_cliente", "zona_cobertura", "numero_habilitacion"])
    exportadores = tabla("exportador", ["id_cliente", "pais_destino_principal"])
    permisos = tabla("permiso_exportacion", ["id_permiso", "codigo", "fecha_emision", "fecha_vencimiento", "id_cliente"])

    zonas = ["Gran Mendoza", "Valle de Uco", "Sur mendocino", "Este mendocino", "San Juan", "Córdoba"]
    paises = ["Estados Unidos", "Brasil", "Reino Unido", "Canadá", "China", "México", "Alemania"]
    documentos = set()
    for id_cli in range(1, CANT_CLIENTES + 1):
        id_tipo = rnd.choices([1, 2, 3], weights=[75, 17, 8])[0]
        if id_tipo == 1:
            nombre, tipo_doc = f"{fake.last_name()}, {fake.first_name()}", "DNI"
            doc = str(rnd.randint(10_000_000, 46_000_000))
        else:
            nombre, tipo_doc = fake.company(), "CUIT"
            doc = f"30{rnd.randint(10_000_000, 99_999_999)}{rnd.randint(0, 9)}"
        while (tipo_doc, doc) in documentos:                  # UNIQUE (tipo, número)
            doc = str(int(doc) + 1)
        documentos.add((tipo_doc, doc))

        clientes.append((id_cli, nombre, tipo_doc, doc, fake.street_name(), str(rnd.randint(1, 5000)),
                         fecha_entre(date(2016, 1, 1), FECHA_CORTE - timedelta(days=5)),
                         rnd.randint(1, cant_loc), id_tipo))
        # Jerarquía total y exclusiva: cada cliente está en un solo subtipo
        if id_tipo == 1:
            socios.append((id_cli,))
        elif id_tipo == 2:
            distribuidores.append((id_cli, rnd.choice(zonas), f"HAB-{id_cli:06d}"))
        else:
            exportadores.append((id_cli, rnd.choice(paises)))
            for _ in range(rnd.randint(1, 6)):                # al menos un permiso; algunos más de 3 (U6)
                emision = fecha_entre(date(2018, 1, 1), FECHA_CORTE)
                vence = emision + timedelta(days=rnd.randint(365, 3 * 365))   # RN-07
                id_perm = len(permisos) + 1
                permisos.append((id_perm, f"PE-{emision.year}-{id_perm:06d}", emision, vence, id_cli))


# =====================================================================
# 6. VENTAS: comprobantes y renglones
# =====================================================================
def periodos():
    """Trimestres desde INICIO_VENTAS hasta FECHA_CORTE."""
    lista, ini = [], INICIO_VENTAS
    while ini <= FECHA_CORTE:
        fin = sumar_meses(ini, 3) - timedelta(days=1)
        lista.append((ini, min(fin, FECHA_CORTE)))
        ini = fin + timedelta(days=1)
    return lista


def generar_ventas():
    vinos = {v[0]: v for v in tablas["vino"][1]}
    disponible = {i: date(v[4] + 1, 3, 1) for i, v in vinos.items()}   # se vende desde el año siguiente a la añada
    descuento = {t[0]: t[2] for t in tablas["tipo_cliente"][1]}

    # Surtido de cada sala: 10 vinos "viejos" (para vender desde 2020) + el resto al azar
    viejos = [i for i in vinos if disponible[i] <= INICIO_VENTAS]
    surtido = {}
    for id_sala in range(1, CANT_SALAS + 1):
        base = rnd.sample(viejos, 10)
        resto = [i for i in vinos if i not in base]
        surtido[id_sala] = base + rnd.sample(resto, VINOS_POR_SALA - 10)

    compradores = [c for c in tablas["cliente"][1] if rnd.random() < 0.85]   # el 15% nunca compró
    lista_periodos = periodos()

    comprobantes = tabla("comprobante", ["id_comprobante", "num_comprobante", "fecha", "subtotal",
                                         "descuento", "total", "id_cliente", "id_sala"])
    detalle = tabla("detalle_comprobante", ["id_comprobante", "id_vino", "cantidad", "precio_unitario_venta",
                                            "descuento_aplicado", "subtotal_renglon"])
    demanda = defaultdict(int)     # (id_sala, id_vino, n° de trimestre) -> botellas vendidas

    while len(comprobantes) < CANT_COMPROBANTES:
        cli = rnd.choice(compradores)
        fecha = fecha_entre(max(cli[6], INICIO_VENTAS), FECHA_CORTE)
        id_sala = rnd.randint(1, CANT_SALAS)
        a_la_venta = [i for i in surtido[id_sala] if disponible[i] <= fecha]
        if not a_la_venta:
            continue
        id_comp = len(comprobantes) + 1
        n_per = next(k for k, (ini, fin) in enumerate(lista_periodos) if ini <= fecha <= fin)
        pct = descuento[cli[8]]
        n_renglones = min(len(a_la_venta), rnd.choices([1, 2, 3, 4, 5, 6], weights=[10, 20, 25, 20, 15, 10])[0])
        bruto = neto = Decimal(0)
        for id_vino in rnd.sample(a_la_venta, n_renglones):
            cant = rnd.randint(1, 6) if cli[8] == 1 else rnd.randint(6, 24)
            precio = vinos[id_vino][7]
            sub = dinero(cant * precio * (1 - pct / 100))     # igual que el trigger de venta (RN-06)
            detalle.append((id_comp, id_vino, cant, precio, pct, sub))
            bruto += cant * precio
            neto += sub
            demanda[(id_sala, id_vino, n_per)] += cant
        # RN-08: subtotal = bruto, total = suma de renglones, descuento = subtotal - total
        comprobantes.append((id_comp, f"A-{id_sala:04d}-{id_comp:08d}", fecha,
                             dinero(bruto), dinero(bruto - neto), dinero(neto), cli[0], id_sala))
    return demanda, lista_periodos


# =====================================================================
# 7. STOCK Y LOGÍSTICA: transportistas, ingresos, transferencias, stock
# =====================================================================
def generar_logistica(demanda, lista_periodos):
    cant_loc = len(tablas["localidad"][1])
    cuits = {b[1] for b in tablas["bodega"][1]}
    transportistas = tabla("transportista", ["id_transportista", "cod_transporte", "razon_social", "cuit", "calle", "numero"])
    emails = tabla("transportista_email", ["id_transportista", "email"])
    telefonos = tabla("transportista_telefono", ["id_transportista", "telefono"])
    cobertura = tabla("transportista_localidad", ["id_transportista", "id_localidad"])
    for i in range(1, CANT_TRANSPORTISTAS + 1):
        transportistas.append((i, f"TR-{i:03d}", f"Transportes {fake.last_name()}", cuit("30", cuits),
                               fake.street_name(), str(rnd.randint(1, 5000))))
        emails.append((i, f"logistica{i:02d}@transportes.com.ar"))
        telefonos.append((i, f"+54 260 4{rnd.randint(100000, 999999)}"))
        for id_loc in sorted(rnd.sample(range(1, cant_loc + 1), rnd.randint(3, 10))):
            cobertura.append((i, id_loc))

    vino_bodega = {v[0]: v[8] for v in tablas["vino"][1]}
    ingresos = tabla("ingreso", ["id_ingreso", "cod_ingreso", "fecha", "estado", "id_transportista", "id_bodega"])
    r_ingreso = tabla("renglon_ingreso", ["id_renglon_ingreso", "id_ingreso", "id_vino", "cantidad_botellas"])
    transferencias = tabla("transferencia", ["id_transferencia", "num_solicitud", "fecha_confeccion", "estado", "id_sala"])
    r_transf = tabla("renglon_transferencia", ["id_renglon_transferencia", "id_transferencia", "id_vino", "cantidad_botellas"])

    stock_sala = defaultdict(int)
    stock_dep = defaultdict(int)

    for n_per, (ini, _fin) in enumerate(lista_periodos):
        # 7.a Transferencias: una por sala, unos días ANTES del trimestre, con lo
        #     que la sala va a vender + un sobrante -> el stock de la sala nunca es negativo
        pedidos_por_vino = defaultdict(int)
        por_sala = defaultdict(list)
        for (id_sala, id_vino, p), cant in demanda.items():
            if p == n_per:
                por_sala[id_sala].append((id_vino, cant + rnd.randint(0, 12)))
        fecha_transf = ini - timedelta(days=rnd.randint(1, 7))
        for id_sala in sorted(por_sala):
            id_t = len(transferencias) + 1
            transferencias.append((id_t, f"T-{id_t:06d}", fecha_transf, "procesado", id_sala))
            for id_vino, cant in sorted(por_sala[id_sala]):
                r_transf.append((len(r_transf) + 1, id_t, id_vino, cant))
                stock_sala[(id_sala, id_vino)] += cant
                pedidos_por_vino[id_vino] += cant

        # 7.b Ingresos: dos por bodega, ANTES de las transferencias, con lo que
        #     se va a transferir + un sobrante -> el depósito nunca queda negativo
        por_bodega = defaultdict(list)
        for id_vino in sorted(pedidos_por_vino):
            por_bodega[vino_bodega[id_vino]].append((id_vino, pedidos_por_vino[id_vino] + rnd.randint(0, 24)))
        for id_bodega in sorted(por_bodega):
            renglones = por_bodega[id_bodega]
            mitad = (len(renglones) + 1) // 2
            for parte in (renglones[:mitad], renglones[mitad:]):
                if not parte:
                    continue
                id_i = len(ingresos) + 1
                ingresos.append((id_i, f"I-{id_i:06d}", fecha_transf - timedelta(days=rnd.randint(5, 20)),
                                 "procesado", rnd.randint(1, CANT_TRANSPORTISTAS), id_bodega))
                for id_vino, cant in parte:
                    r_ingreso.append((len(r_ingreso) + 1, id_i, id_vino, cant))
                    stock_dep[id_vino] += cant
        for id_vino, cant in pedidos_por_vino.items():
            stock_dep[id_vino] -= cant

    # 7.c Las ventas consumen el stock de cada sala
    for (id_sala, id_vino, _p), cant in demanda.items():
        stock_sala[(id_sala, id_vino)] -= cant

    # 7.d Documentos pendientes de las últimas dos semanas (no mueven stock)
    vinos_con_stock = sorted(v for v, c in stock_dep.items() if c > 0)
    for k in range(DOCUMENTOS_PENDIENTES):
        estado = "en_confeccion" if k % 2 == 0 else "terminado"
        fecha = FECHA_CORTE - timedelta(days=rnd.randint(0, 14))
        id_bod = rnd.randint(1, CANT_BODEGAS)
        id_i = len(ingresos) + 1
        ingresos.append((id_i, f"I-{id_i:06d}", fecha, estado, rnd.randint(1, CANT_TRANSPORTISTAS), id_bod))
        vinos_bod = [v[0] for v in tablas["vino"][1] if v[8] == id_bod]
        for id_vino in rnd.sample(vinos_bod, 3):
            r_ingreso.append((len(r_ingreso) + 1, id_i, id_vino, rnd.randint(12, 120)))
        id_t = len(transferencias) + 1
        transferencias.append((id_t, f"T-{id_t:06d}", fecha, estado, rnd.randint(1, CANT_SALAS)))
        for id_vino in rnd.sample(vinos_con_stock, 3):        # cantidades que el depósito puede cubrir
            r_transf.append((len(r_transf) + 1, id_t, id_vino, rnd.randint(1, max(1, stock_dep[id_vino] // 4))))

    # 7.e Stock final: depósito (una fila por vino) y salas
    st_dep = tabla("stock_deposito", ["id_vino", "cantidad"])
    for v in tablas["vino"][1]:
        st_dep.append((v[0], stock_dep.get(v[0], 0)))
    st_sala = tabla("stock_sala", ["id_sala", "id_vino", "cantidad"])
    for (id_sala, id_vino), cant in sorted(stock_sala.items()):
        st_sala.append((id_sala, id_vino, cant))


# =====================================================================
# 8. ORDEN DE CARGA Y GUARDADO
# =====================================================================
ORDEN_CARGA = [
    # Sin dependencias
    "encargado", "departamento", "cepa", "bodega", "maridaje", "tipo_cliente", "transportista",
    # Dependen de las anteriores
    "localidad", "finca", "vino", "sala_de_ventas", "cliente", "parcela",
    "vino_cepa", "vino_maridaje", "auditoria_precio", "stock_deposito",
    "transportista_email", "transportista_telefono", "transportista_localidad",
    "ingreso", "empleado", "stock_sala", "transferencia",
    "socio", "distribuidor", "exportador", "lote_de_uva", "comprobante",
    "renglon_ingreso", "permiso_exportacion", "analisis_calidad",
    "detalle_comprobante", "renglon_transferencia",
]


def guardar_csv():
    DIR_SALIDA.mkdir(exist_ok=True)
    for orden, nombre in enumerate(ORDEN_CARGA, start=1):
        columnas, filas = tablas[nombre]
        with open(DIR_SALIDA / f"{orden:02d}_{nombre}.csv", "w", newline="", encoding="utf-8") as f:
            escritor = csv.writer(f)
            escritor.writerow(columnas)
            escritor.writerows(filas)
        print(f"{orden:02d}_{nombre:<25} {len(filas):>9,} filas")


def main():
    generar_catalogos()
    generar_red_comercial()
    generar_bodegas_y_vinos()
    generar_produccion()
    generar_clientes()
    demanda, lista_periodos = generar_ventas()
    generar_logistica(demanda, lista_periodos)
    guardar_csv()


if __name__ == "__main__":
    main()