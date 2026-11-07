#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
carga_masiva.py - Etapa 3: carga masiva de datos de Bodegas del Atuel.

Genera un plan de datos sintéticos DETERMINÍSTICO (misma semilla => mismos
datos) a partir de los CSV de catálogo de db/seed/csv/ y lo carga en el
esquema `bodegas` respetando TODAS las restricciones y triggers (no se
desactiva ninguno).

Modos de uso (ver db/seed/README.md):

    python carga_masiva.py --solo-plan [--fecha-carga AAAA-MM-DD]
                                                # genera el plan y muestra cantidades; NO se conecta
    python carga_masiva.py                      # se conecta, revisa el estado y NO escribe nada
    python carga_masiva.py --confirmar          # ejecuta (o reanuda) la carga
    python carga_masiva.py --verificar          # sólo ejecuta las consultas de control (lectura)

Perfiles (--perfil): 'definitivo' (por defecto; volúmenes del TPI) o 'prueba'
(volúmenes reducidos; exige --env con un .env de prueba que declare
BODEGAS_ENTORNO=prueba y apunte a una base distinta de la principal).

Cronología: datos históricos hasta FIN_HISTORIAL; transferencias y
comprobantes con fecha = día de carga (CURRENT_DATE del servidor), las
ventas siempre después de procesar las transferencias.

Códigos de salida: 0 OK, 1 controles con FALLA, 2 error controlado del
script, 3 error de PostgreSQL (la transacción en curso se revierte).

Conexión: variables de entorno (o el archivo .env de la raíz del repositorio):
    POSTGRES_HOST / PGHOST       (por defecto 127.0.0.1)
    POSTGRES_PORT / PGPORT       (por defecto 55432)
    POSTGRES_DB   / PGDATABASE
    POSTGRES_USER / PGUSER
    POSTGRES_PASSWORD / PGPASSWORD
El script nunca imprime ni guarda la contraseña.

Repetición controlada: la carga se divide en fases. Antes de escribir, el
script detecta qué fases ya están completas comparando la base con el plan
(claves naturales y cantidades). Una fase completa se saltea; una fase a
medio cargar (sólo posible en las fases por lotes) se reanuda; cualquier
dato que no coincida con el plan detiene la carga SIN borrar ni modificar
nada.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import random
import re
import sys
import time
import zlib
from collections import Counter, defaultdict
from dataclasses import dataclass, field, replace
from datetime import date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path
from typing import Callable, Iterable, Sequence

DIR_SEED = Path(__file__).resolve().parent
DIR_CSV = DIR_SEED / "csv"
DIR_REPO = DIR_SEED.parent.parent
ARCHIVO_VALIDACIONES = DIR_SEED / "validaciones.sql"
ESQUEMA = "bodegas"

# =====================================================================
# Parámetros de la generación
# =====================================================================
# Los datos históricos usan rangos fijos (no dependen de la fecha del día).
#
# Cronología (opción A aprobada, docs/etapa3_carga_masiva.md §3.2):
#   historial (<= FIN_HISTORIAL)  ->  día de carga D = CURRENT_DATE del servidor
#   * Cosechas, análisis, ingresos, altas de clientes, empleados y permisos
#     tienen fechas históricas, todas <= FIN_HISTORIAL < D.
#   * Las transferencias quedan con fecha_confeccion = D (la impone
#     trg_transferencia_fecha; no se toca).
#   * Los comprobantes quedan con fecha = CURRENT_DATE (DEFAULT de la columna),
#     y se cargan DESPUÉS de procesar todas las transferencias.
#   * El plan de ventas sólo usa salas que NO cierran el día de la semana de D.
# Por eso el plan depende de la semilla y del DÍA DE LA SEMANA de D.
SEMILLA_POR_DEFECTO = 20261106

FIN_HISTORIAL = date(2026, 6, 30)              # ninguna fecha histórica la supera
CAMPANIAS = tuple(range(2022, 2027))           # últimos 5 años (Anexo B.4)
ANADA_MIN, ANADA_MAX = 2016, 2023              # todas anteriores a los ingresos
INGRESOS_DESDE, INGRESOS_HASTA = date(2024, 7, 1), date(2024, 12, 31)
ALTA_CLIENTES_DESDE, ALTA_CLIENTES_HASTA = date(2012, 1, 1), date(2024, 12, 31)
INGRESO_EMPLEADOS_DESDE, INGRESO_EMPLEADOS_HASTA = date(2008, 1, 1), FIN_HISTORIAL
PERMISOS_DESDE, PERMISOS_HASTA = date(2021, 1, 1), FIN_HISTORIAL

# Volúmenes y tamaños de lote: TODO está en un Perfil (configuración única).
# El generador y el cargador reciben el perfil; no leen constantes sueltas.
TIPOS_CLIENTE = ("Socio", "Distribuidor", "Exportador")   # deben coincidir con tipos_cliente.csv


@dataclass(frozen=True)
class Perfil:
    nombre: str
    n_bodegas: int
    n_transportistas: int
    localidades_por_transportista: int
    n_salas: int
    n_empleados: int
    n_fincas: int
    parcelas_por_finca: tuple[int, int]
    n_vinos: int
    vinos_por_sala: int                 # stock_sala = n_salas x vinos_por_sala
    rondas_transferencia: int           # cada (sala, vino) se abastece en tantas transferencias
    vinos_por_transferencia: int
    ingresos_objetivo: int
    renglones_por_ingreso: int
    n_clientes: int
    mix_clientes: tuple                 # ((tipo, proporción), ...) en el orden de TIPOS_CLIENTE
    n_comprobantes: int
    renglones_por_comprobante: tuple    # ((renglones, % de comprobantes), ...): suma 100
    mix_compradores: tuple
    botellas_por_renglon: dict
    margen_transferencia: Decimal       # se transfiere este factor de lo que se vende...
    extra_transferencia: int            # ...más estas botellas por (sala, vino)
    margen_ingreso: Decimal             # ingresa este factor de lo que se transfiere...
    extra_ingreso: int                  # ...más estas botellas por vino
    precios_a_ajustar: int              # cambios de precio => filas de auditoría
    lote_documentos: int                # ingresos o transferencias por transacción
    lote_comprobantes: int              # comprobantes (con sus renglones) por transacción
    exigir_volumen_tpi: bool            # mínimos de la Etapa 3 (sólo el perfil definitivo)
    exige_entorno_prueba: bool          # sólo conecta con un .env de prueba explícito


# Perfil DEFINITIVO: tabla "Volúmenes recomendados" de la Etapa 3 del TPI.
# NO modificar: de estos valores dependen las cantidades y el determinismo del plan
# (150.000 comprobantes, 525.000 renglones).
PERFIL_DEFINITIVO = Perfil(
    nombre="definitivo",
    n_bodegas=30, n_transportistas=20, localidades_por_transportista=3,
    n_salas=100, n_empleados=150, n_fincas=120, parcelas_por_finca=(4, 9),
    n_vinos=400, vinos_por_sala=40, rondas_transferencia=3, vinos_por_transferencia=4,
    ingresos_objetivo=1500, renglones_por_ingreso=6,
    n_clientes=20000, mix_clientes=(("Socio", 0.85), ("Distribuidor", 0.10), ("Exportador", 0.05)),
    n_comprobantes=150000,
    renglones_por_comprobante=((1, 10), (2, 15), (3, 25), (4, 25), (5, 15), (6, 10)),
    mix_compradores=(("Socio", 0.80), ("Distribuidor", 0.15), ("Exportador", 0.05)),
    botellas_por_renglon={"Socio": (1, 6), "Distribuidor": (6, 24), "Exportador": (12, 48)},
    margen_transferencia=Decimal("1.10"), extra_transferencia=6,
    margen_ingreso=Decimal("1.05"), extra_ingreso=24,
    precios_a_ajustar=40,
    lote_documentos=250, lote_comprobantes=5000,
    exigir_volumen_tpi=True, exige_entorno_prueba=False,
)

# Perfil PRUEBA: misma lógica y proporciones, volúmenes chicos y lotes chicos
# (para ejercitar varios lotes, la reanudación y los controles por lote).
PERFIL_PRUEBA = replace(
    PERFIL_DEFINITIVO,
    nombre="prueba",
    n_bodegas=3, n_transportistas=2, localidades_por_transportista=2,
    n_salas=6, n_empleados=8, n_fincas=3,
    n_vinos=24, vinos_por_sala=8, ingresos_objetivo=12,
    n_clientes=200, n_comprobantes=300, precios_a_ajustar=3,
    lote_documentos=5, lote_comprobantes=50,
    exigir_volumen_tpi=False, exige_entorno_prueba=True,
)

PERFILES = {p.nombre: p for p in (PERFIL_DEFINITIVO, PERFIL_PRUEBA)}

CLAVE_BLOQUEO = 2026030001               # pg_try_advisory_lock: evita dos cargas a la vez

# Códigos de salida (documentados en db/seed/README.md)
SALIDA_OK = 0                  # plan, revisión o carga sin controles fallidos
SALIDA_CONTROLES_FALLIDOS = 1  # las consultas de control encontraron FALLAS
SALIDA_ERROR_CONTROLADO = 2    # el script detuvo la carga (datos inconsistentes, esquema, CSV...)
SALIDA_ERROR_POSTGRES = 3      # PostgreSQL rechazó una operación (se revirtió esa transacción)

DIAS_SEMANA = ("lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo")
DIAS_CIERRE = (("lunes", 40), ("domingo", 30), ("martes", 10), ("miercoles", 8),
               ("jueves", 5), ("viernes", 4), ("sabado", 3))
ZONAS = {
    "Gran Mendoza": ("Capital", "Godoy Cruz", "Guaymallén", "Las Heras", "Luján de Cuyo", "Maipú"),
    "Zona Este": ("San Martín", "Junín", "Rivadavia", "Santa Rosa", "La Paz"),
    "Valle de Uco": ("Tunuyán", "Tupungato", "San Carlos"),
    "Zona Sur": ("San Rafael", "General Alvear", "Malargüe"),
    "Zona Norte": ("Lavalle",),
}
PAISES = ("Estados Unidos", "Brasil", "Reino Unido", "China", "Canadá", "Países Bajos",
          "México", "Japón", "Alemania", "Paraguay", "Uruguay", "Suiza")
PESO_DEPTO_FINCA = {"Luján de Cuyo": 8, "Maipú": 6, "Tupungato": 6, "Tunuyán": 6, "San Carlos": 5,
                    "San Rafael": 6, "General Alvear": 3, "San Martín": 4, "Rivadavia": 3,
                    "Junín": 3, "Lavalle": 2, "Santa Rosa": 2}
PESO_CEPA = {"Malbec": 30, "Cabernet Sauvignon": 12, "Bonarda": 8, "Syrah": 6, "Merlot": 6,
             "Tempranillo": 4, "Pinot Noir": 4, "Chardonnay": 10, "Sauvignon Blanc": 5,
             "Torrontés": 5, "Chenin Blanc": 3, "Semillón": 3}
TIPOS_VINO = (("tinto", 62), ("blanco", 22), ("rosado", 8), ("espumante", 8))
PRESENTACIONES = ((750, 78), (375, 7), (187, 4), (1500, 9), (3000, 2))
FACTOR_PRESENTACION = {187: Decimal("0.32"), 375: Decimal("0.55"), 750: Decimal("1"),
                       1500: Decimal("2.20"), 3000: Decimal("4.80")}
LINEAS = (("Joven", Decimal("0.8")), ("Clásico", Decimal("1.0")), ("Roble", Decimal("1.2")),
          ("Selección", Decimal("1.3")), ("Reserva", Decimal("1.5")), ("Origen", Decimal("1.6")),
          ("Single Vineyard", Decimal("1.9")), ("Gran Reserva", Decimal("2.2")))
LINEAS_ESPUMANTE = ("Brut", "Extra Brut", "Brut Nature", "Dulce Natural")
PRECIO_BASE_750 = {"tinto": (6000, 45000), "blanco": (5000, 25000),
                   "rosado": (5000, 18000), "espumante": (7000, 35000)}
GRADUACION = {"tinto": (13.0, 15.5), "blanco": (11.5, 13.5),
              "rosado": (11.5, 13.0), "espumante": (11.0, 12.5)}
MARIDAJES_POR_TIPO = {
    "tinto": ("Carnes rojas", "Quesos duros", "Pastas con salsa roja"),
    "blanco": ("Pescados y mariscos", "Carnes blancas", "Quesos blandos"),
    "rosado": ("Entradas y fiambres", "Carnes blancas", "Pastas con salsa roja"),
    "espumante": ("Entradas y fiambres", "Postres", "Pescados y mariscos"),
}

# Orden de las 34 tablas del esquema, por fase (ver docs/etapa3_carga_masiva.md)
TABLAS_POR_FASE = {
    "catalogos": ("encargado", "departamento", "cepa", "maridaje", "tipo_cliente", "localidad"),
    "maestros": ("bodega", "transportista", "transportista_email", "transportista_telefono",
                 "sala_de_ventas", "transportista_localidad", "empleado", "finca", "parcela",
                 "lote_de_uva", "analisis_calidad"),
    "vinos": ("vino", "vino_cepa", "vino_maridaje"),
    "clientes": ("cliente", "socio", "distribuidor", "exportador", "permiso_exportacion"),
    "ingresos": ("ingreso", "renglon_ingreso", "stock_deposito"),
    "transferencias": ("transferencia", "renglon_transferencia", "stock_sala"),
    "comprobantes": ("comprobante", "detalle_comprobante"),
    "precios": ("auditoria_precio",),
}
TODAS_LAS_TABLAS = tuple(t for ts in TABLAS_POR_FASE.values() for t in ts)

TRIGGERS_REQUERIDOS = (
    "trg_vino_auditoria_precio", "trg_transferencia_fecha",
    "trg_ingreso_estado", "trg_transferencia_estado", "trg_renglon_ingreso_bloqueo",
    "trg_renglon_transferencia_bloqueo", "trg_vino_cepa_suma_100",
    "trg_detalle_validar", "trg_detalle_actualizar", "trg_comprobante_totales",
)


class ErrorCarga(Exception):
    """Error controlado: se informa sin traza y la carga se detiene."""


# =====================================================================
# Utilidades
# =====================================================================
def dinero(valor) -> Decimal:
    return Decimal(valor).quantize(Decimal("0.01"), ROUND_HALF_UP)


def redondear_a_10(valor: Decimal) -> Decimal:
    return dinero((Decimal(valor) / 10).quantize(Decimal("1"), ROUND_HALF_UP) * 10)


def num(valor, decimales: int = 0) -> str:
    """Formato de presentación es-AR: miles con punto y decimales con coma (1.234.567,8).
    Sólo formatea el número; no se aplica sobre textos que contengan otras comas."""
    return f"{valor:,.{decimales}f}".replace(",", "_").replace(".", ",").replace("_", ".")


def fecha_al_azar(rng: random.Random, desde: date, hasta: date) -> date:
    return desde + timedelta(days=rng.randint(0, (hasta - desde).days))


def trozos(secuencia: Sequence, tamanio: int) -> Iterable[Sequence]:
    for i in range(0, len(secuencia), tamanio):
        yield secuencia[i:i + tamanio]


def cuit_valido(prefijo: int, numero: int) -> str | None:
    """CUIT de 11 dígitos con dígito verificador (módulo 11). None si el DV sería 10."""
    base = f"{prefijo:02d}{numero:08d}"
    suma = sum(int(d) * m for d, m in zip(base, (5, 4, 3, 2, 7, 6, 5, 4, 3, 2)))
    dv = 11 - suma % 11
    if dv == 11:
        dv = 0
    if dv == 10:
        return None
    return base + str(dv)


class GeneradorCuit:
    """Genera CUIT únicos (dentro de un rango de números) con DV correcto."""

    def __init__(self, rng: random.Random, prefijos: tuple[int, ...], desde: int, hasta: int):
        self.rng, self.prefijos, self.desde, self.hasta = rng, prefijos, desde, hasta
        self.usados: set[str] = set()

    def nuevo(self) -> str:
        while True:
            c = cuit_valido(self.rng.choice(self.prefijos), self.rng.randint(self.desde, self.hasta))
            if c and c not in self.usados:
                self.usados.add(c)
                return c


def semilla_seccion(semilla: int, seccion: str) -> int:
    return zlib.crc32(f"{semilla}:{seccion}".encode("utf-8"))


def crear_faker(semilla: int):
    """Faker con locale argentino si la versión instalada lo trae; si no, es_ES."""
    try:
        from faker import Faker
    except ImportError as exc:  # pragma: no cover
        raise ErrorCarga("Falta el paquete Faker: ejecutar 'uv sync' en la raíz del repositorio") from exc
    for locale in ("es_AR", "es_ES"):
        try:
            fk = Faker(locale)
        except Exception:  # locale inexistente en esta versión de Faker
            continue
        fk.seed_instance(semilla)
        return fk, locale
    raise ErrorCarga("Faker no tiene los locales es_AR ni es_ES")


# =====================================================================
# Catálogos (CSV)
# =====================================================================
def leer_csv(nombre: str, columnas: Sequence[str]) -> list[dict]:
    ruta = DIR_CSV / nombre
    if not ruta.exists():
        raise ErrorCarga(f"No existe {ruta}")
    with ruta.open(encoding="utf-8-sig", newline="") as f:
        lector = csv.reader(f)
        encabezado = next(lector, None)
        if encabezado != list(columnas):
            raise ErrorCarga(f"{nombre}: encabezado {encabezado}, se esperaba {list(columnas)}")
        filas = []
        for n, fila in enumerate(lector, start=2):
            if len(fila) != len(columnas):
                raise ErrorCarga(f"{nombre}, línea {n}: {len(fila)} columnas, se esperaban {len(columnas)}")
            filas.append(dict(zip(columnas, fila)))
    if not filas:
        raise ErrorCarga(f"{nombre} no tiene registros")
    return filas


@dataclass
class Catalogos:
    departamentos: list[tuple[str, str]]                 # (nombre, provincia)
    localidades: list[tuple[str, str, str, str]]         # (cod_postal, nombre, provincia, departamento)
    encargados: list[tuple[str, str, str]]               # (dni, nombre, apellido)
    encargado_de_localidad: dict[tuple[str, str], str]   # (nombre, cod_postal) -> dni
    cepas: list[tuple[str, str]]                         # (nombre, tipo)
    maridajes: list[tuple[str, Decimal]]                 # (nombre, temperatura)
    tipos_cliente: list[tuple[str, Decimal]]             # (nombre, porcentaje)


def leer_catalogos() -> Catalogos:
    deps = leer_csv("departamentos.csv", ("nombre", "provincia"))
    locs = leer_csv("localidades.csv", ("cod_postal", "nombre", "provincia", "departamento"))
    encs = leer_csv("encargados_auxiliares.csv", ("dni", "nombre", "apellido", "localidad", "cod_postal"))
    cepas = leer_csv("cepas.csv", ("nombre", "tipo"))
    mars = leer_csv("maridajes.csv", ("nombre", "temperatura_sugerida"))
    tipos = leer_csv("tipos_cliente.csv", ("nombre", "porcentaje_descuento"))

    departamentos = [(d["nombre"], d["provincia"]) for d in deps]
    if len(set(departamentos)) != len(departamentos):
        raise ErrorCarga("departamentos.csv tiene departamentos repetidos")
    nombres_dep = {d[0] for d in departamentos}

    localidades, claves_loc = [], set()
    for r in locs:
        if not re.fullmatch(r"\d{4}", r["cod_postal"]):
            raise ErrorCarga(f"localidades.csv: código postal inválido {r['cod_postal']!r}")
        if not r["nombre"] or len(r["nombre"]) > 80 or not r["provincia"] or len(r["provincia"]) > 50:
            raise ErrorCarga(f"localidades.csv: nombre o provincia inválidos en {r}")
        if r["departamento"] not in nombres_dep:
            raise ErrorCarga(f"localidades.csv: departamento desconocido {r['departamento']!r}")
        clave = (r["nombre"], r["cod_postal"])
        if clave in claves_loc:
            raise ErrorCarga(f"localidades.csv: localidad repetida {clave}")
        claves_loc.add(clave)
        localidades.append((r["cod_postal"], r["nombre"], r["provincia"], r["departamento"]))

    encargados, encargado_de_localidad, dnis = [], {}, set()
    for r in encs:
        if not r["dni"] or len(r["dni"]) > 50 or len(r["nombre"]) > 50 or len(r["apellido"]) > 50:
            raise ErrorCarga(f"encargados_auxiliares.csv: fila inválida {r}")
        if r["dni"] in dnis:
            raise ErrorCarga(f"encargados_auxiliares.csv: dni repetido {r['dni']}")
        dnis.add(r["dni"])
        clave = (r["localidad"], r["cod_postal"])          # columnas AUXILIARES: sólo relacionan
        if clave in encargado_de_localidad:
            raise ErrorCarga(f"encargados_auxiliares.csv: dos encargados para {clave}")
        encargado_de_localidad[clave] = r["dni"]
        encargados.append((r["dni"], r["nombre"], r["apellido"]))   # lo único que se inserta
    if set(encargado_de_localidad) != claves_loc:
        faltan = sorted(claves_loc - set(encargado_de_localidad))[:5]
        sobran = sorted(set(encargado_de_localidad) - claves_loc)[:5]
        raise ErrorCarga(f"La relación encargado-localidad no es 1 a 1. Sin encargado: {faltan}; "
                         f"encargados sin localidad: {sobran}")

    cepas_l = [(c["nombre"], c["tipo"]) for c in cepas]
    if any(t not in ("tinta", "blanca") for _, t in cepas_l) or len({n for n, _ in cepas_l}) != len(cepas_l):
        raise ErrorCarga("cepas.csv: tipo inválido o cepa repetida")
    if not any(t == "tinta" for _, t in cepas_l) or not any(t == "blanca" for _, t in cepas_l):
        raise ErrorCarga("cepas.csv debe tener al menos una cepa tinta y una blanca")
    maridajes = [(m["nombre"], Decimal(m["temperatura_sugerida"])) for m in mars]
    if len({n for n, _ in maridajes}) != len(maridajes):
        raise ErrorCarga("maridajes.csv: maridaje repetido")
    tipos_cliente = [(t["nombre"], Decimal(t["porcentaje_descuento"])) for t in tipos]
    if sorted(n for n, _ in tipos_cliente) != sorted(TIPOS_CLIENTE):
        raise ErrorCarga(f"tipos_cliente.csv debe tener exactamente {list(TIPOS_CLIENTE)}")
    return Catalogos(departamentos, localidades, encargados, encargado_de_localidad,
                     cepas_l, maridajes, tipos_cliente)


# =====================================================================
# Validación del perfil (antes de generar)
# =====================================================================
def _clientes_por_tipo(perfil: Perfil) -> dict[str, int]:
    """Misma cuenta que GeneradorPlan._clientes (redondeo incluido)."""
    n_socio = round(perfil.n_clientes * perfil.mix_clientes[0][1])
    n_dist = round(perfil.n_clientes * perfil.mix_clientes[1][1])
    return {"Socio": n_socio, "Distribuidor": n_dist, "Exportador": perfil.n_clientes - n_socio - n_dist}


def validar_perfil(perfil: Perfil, cat: Catalogos):
    """Detecta configuraciones que romperían la generación o la carga. Informa TODOS
    los problemas juntos, con el parámetro y cómo corregirlo."""
    p, errores = perfil, []

    def exigir(condicion: bool, mensaje: str):
        if not condicion:
            errores.append(mensaje)

    enteros = ("n_bodegas", "n_transportistas", "localidades_por_transportista", "n_salas", "n_empleados",
               "n_fincas", "n_vinos", "vinos_por_sala", "rondas_transferencia", "vinos_por_transferencia",
               "ingresos_objetivo", "renglones_por_ingreso", "n_clientes", "n_comprobantes",
               "precios_a_ajustar", "lote_documentos", "lote_comprobantes")
    for nombre in enteros:
        exigir(getattr(p, nombre) >= 1, f"{nombre}={getattr(p, nombre)}: debe ser un entero >= 1")
    max_renglones = max(k for k, _ in p.renglones_por_comprobante)
    n_localidades = len(cat.localidades)
    exigir(p.n_vinos >= p.n_bodegas,
           f"n_vinos={p.n_vinos} < n_bodegas={p.n_bodegas}: cada bodega necesita al menos un vino "
           f"(subir n_vinos o bajar n_bodegas)")
    exigir(max_renglones <= p.vinos_por_sala <= p.n_vinos,
           f"vinos_por_sala={p.vinos_por_sala}: debe estar entre {max_renglones} (máximo de renglones por "
           f"comprobante, sin repetir vino) y n_vinos={p.n_vinos}")
    exigir(p.n_salas <= n_localidades,
           f"n_salas={p.n_salas} > {n_localidades} localidades del catálogo: hay una sala por localidad")
    exigir(p.localidades_por_transportista <= p.n_salas,
           f"localidades_por_transportista={p.localidades_por_transportista} > n_salas={p.n_salas}: cada "
           f"transportista cubre localidades con sala (bajar el valor o subir n_salas)")
    exigir(p.precios_a_ajustar <= p.n_vinos,
           f"precios_a_ajustar={p.precios_a_ajustar} > n_vinos={p.n_vinos}: se ajusta a lo sumo un precio por vino")
    exigir(p.n_empleados >= p.n_salas,
           f"n_empleados={p.n_empleados} < n_salas={p.n_salas}: cada sala necesita al menos un empleado")
    exigir(tuple(t for t, _ in p.mix_clientes) == TIPOS_CLIENTE,
           f"mix_clientes debe listar {TIPOS_CLIENTE} en ese orden")
    for tipo, n in _clientes_por_tipo(p).items():
        exigir(n >= 1, f"n_clientes={p.n_clientes} con mix_clientes deja {n} clientes '{tipo}': debe haber al "
                       f"menos uno de cada tipo (subir n_clientes)")
    exigir(sum(pct for _, pct in p.renglones_por_comprobante) == 100,
           "renglones_por_comprobante: los porcentajes deben sumar 100")
    exigir({t for t, _ in p.mix_compradores} <= set(TIPOS_CLIENTE) and set(p.botellas_por_renglon) >= set(TIPOS_CLIENTE),
           "mix_compradores y botellas_por_renglon deben usar los tipos de cliente del catálogo")
    exigir(all(1 <= lo <= hi for lo, hi in p.botellas_por_renglon.values()),
           "botellas_por_renglon: cada rango debe ser (mínimo >= 1, máximo >= mínimo)")
    exigir(1 <= p.parcelas_por_finca[0] <= p.parcelas_por_finca[1],
           f"parcelas_por_finca={p.parcelas_por_finca}: debe ser (mínimo >= 1, máximo >= mínimo)")
    # Stock: cada (sala, vino) recibe ceil(vendido x margen) + extra, repartido en las rondas.
    # Con extra >= rondas ningún renglón de transferencia queda en 0 (CHECK cantidad > 0).
    exigir(p.margen_transferencia >= 1 and p.margen_ingreso >= 1,
           "margen_transferencia y margen_ingreso deben ser >= 1 (si no, el stock no cubre las ventas)")
    exigir(p.extra_transferencia >= p.rondas_transferencia,
           f"extra_transferencia={p.extra_transferencia} < rondas_transferencia={p.rondas_transferencia}: "
           "habría renglones de transferencia con 0 botellas")
    exigir(p.extra_ingreso >= 1, "extra_ingreso debe ser >= 1")
    if errores:
        raise ErrorCarga(f"Perfil '{p.nombre}' inválido:\n  - " + "\n  - ".join(errores))


def controlar_stock_plan(plan) -> None:
    """Verifica sobre el plan generado que el stock alcanza: por (sala, vino) lo transferido
    cubre lo vendido y por vino lo ingresado cubre lo transferido."""
    vendido, transferido, transf_vino, ingresado = Counter(), Counter(), Counter(), Counter()
    for _num, _cli, s, renglones in plan.comprobantes:
        for v, q in renglones:
            vendido[(s, v)] += q
    for t in plan.transferencias:
        for v, q in t["renglones"]:
            transferido[(t["sala"], v)] += q
            transf_vino[v] += q
    for i in plan.ingresos:
        for v, q in i["renglones"]:
            ingresado[v] += q
    cortos_sala = [k for k, q in vendido.items() if transferido[k] < q]
    cortos_vino = [v for v, q in transf_vino.items() if ingresado[v] < q]
    if cortos_sala or cortos_vino:
        raise ErrorCarga(f"Stock planificado insuficiente: {len(cortos_sala)} pares (sala, vino) y "
                         f"{len(cortos_vino)} vinos (revisar margen_* y extra_* del perfil)")


# =====================================================================
# Plan de datos (generación determinística, sin base de datos)
# =====================================================================
@dataclass
class Plan:
    semilla: int
    cat: Catalogos
    fecha_carga: date            # D: define qué salas pueden vender (día de cierre)
    perfil: Perfil = None        # configuración de volúmenes y lotes (definitivo o prueba)
    locale_faker: str = ""
    bodegas: list = field(default_factory=list)
    transportistas: list = field(default_factory=list)
    salas: list = field(default_factory=list)
    empleados: list = field(default_factory=list)
    fincas: list = field(default_factory=list)
    parcelas: list = field(default_factory=list)
    lotes: list = field(default_factory=list)
    analisis: list = field(default_factory=list)
    vinos: list = field(default_factory=list)
    clientes: list = field(default_factory=list)
    permisos: list = field(default_factory=list)
    catalogo_sala: list = field(default_factory=list)
    ingresos: list = field(default_factory=list)
    transferencias: list = field(default_factory=list)
    # (num, cliente, sala, ((vino, cant), ...)). Sin fecha: la pone la base (CURRENT_DATE).
    comprobantes: list = field(default_factory=list)
    ajustes_precio: list = field(default_factory=list)  # (vino, precio_anterior, precio_nuevo)

    def conteos(self) -> dict[str, int]:
        c = Counter(cl["tipo"] for cl in self.clientes)
        return {
            "encargado": len(self.cat.encargados),
            "departamento": len(self.cat.departamentos),
            "cepa": len(self.cat.cepas),
            "maridaje": len(self.cat.maridajes),
            "tipo_cliente": len(self.cat.tipos_cliente),
            "localidad": len(self.cat.localidades),
            "bodega": len(self.bodegas),
            "transportista": len(self.transportistas),
            "transportista_email": sum(len(t["emails"]) for t in self.transportistas),
            "transportista_telefono": sum(len(t["telefonos"]) for t in self.transportistas),
            "sala_de_ventas": len(self.salas),
            "transportista_localidad": sum(len(t["localidades"]) for t in self.transportistas),
            "empleado": len(self.empleados),
            "finca": len(self.fincas),
            "parcela": len(self.parcelas),
            "lote_de_uva": len(self.lotes),
            "analisis_calidad": len(self.analisis),
            "vino": len(self.vinos),
            "vino_cepa": sum(len(v["cepas"]) for v in self.vinos),
            "vino_maridaje": sum(len(v["maridajes"]) for v in self.vinos),
            "cliente": len(self.clientes),
            "socio": c["Socio"],
            "distribuidor": c["Distribuidor"],
            "exportador": c["Exportador"],
            "permiso_exportacion": len(self.permisos),
            "ingreso": len(self.ingresos),
            "renglon_ingreso": sum(len(i["renglones"]) for i in self.ingresos),
            "stock_deposito": len({v for i in self.ingresos for v, _ in i["renglones"]}),
            "transferencia": len(self.transferencias),
            "renglon_transferencia": sum(len(t["renglones"]) for t in self.transferencias),
            "stock_sala": len({(t["sala"], v) for t in self.transferencias for v, _ in t["renglones"]}),
            "comprobante": len(self.comprobantes),
            "detalle_comprobante": sum(len(c[3]) for c in self.comprobantes),
            "auditoria_precio": len(self.ajustes_precio),
        }


class GeneradorPlan:
    """Construye el Plan. Cada sección usa su propio generador aleatorio
    derivado de la semilla, así cambiar una sección no altera las demás."""

    def __init__(self, semilla: int, cat: Catalogos, fecha_carga: date, perfil: Perfil = PERFIL_DEFINITIVO):
        if fecha_carga <= FIN_HISTORIAL:
            raise ErrorCarga(f"La fecha de carga {fecha_carga} debe ser posterior a {FIN_HISTORIAL} "
                             "(fin de los datos históricos)")
        validar_perfil(perfil, cat)                     # antes de generar nada
        self.semilla = semilla
        self.cfg = perfil
        self.plan = Plan(semilla, cat, fecha_carga, perfil)

    def _rng(self, seccion: str) -> random.Random:
        return random.Random(semilla_seccion(self.semilla, seccion))

    def _faker(self, seccion: str):
        fk, locale = crear_faker(semilla_seccion(self.semilla, "faker:" + seccion))
        self.plan.locale_faker = locale
        return fk

    @staticmethod
    def _calle(fk) -> str:
        return fk.street_name()[:80]

    def generar(self) -> Plan:
        self._bodegas()
        self._salas()
        self._transportistas()
        self._empleados()
        self._fincas_parcelas_lotes()
        self._vinos()
        self._clientes()
        self._catalogo_salas()
        demanda = self._ventas()
        demanda_deposito = self._transferencias(demanda)
        self._ingresos(demanda_deposito)
        self._ajustes_precio()
        return self.plan

    # -- maestros ------------------------------------------------------
    def _bodegas(self):
        rng, fk = self._rng("bodegas"), self._faker("bodegas")
        cuits = GeneradorCuit(rng, (30, 33), 50_000_000, 54_999_999)
        formas = ("Bodega {m} S.A.", "Bodegas y Viñedos {m} S.A.", "Viñas {m} S.R.L.", "Familia {m} Wines S.A.")
        marcas, usadas = [], set()
        while len(marcas) < self.cfg.n_bodegas:
            m = fk.last_name()
            if m not in usadas and len(m) <= 30:
                usadas.add(m)
                marcas.append(m)
        for m in marcas:
            self.plan.bodegas.append(dict(cuit=cuits.nuevo(), razon_social=rng.choice(formas).format(m=m),
                                          calle=self._calle(fk), numero=str(rng.randint(1, 9999)), marca=m))

    def _salas(self):
        rng, fk = self._rng("salas"), self._faker("salas")
        claves = [(nombre, cp) for cp, nombre, _p, _d in self.plan.cat.localidades]
        if self.cfg.n_salas > len(claves):
            raise ErrorCarga("Hay menos localidades que salas a generar")
        dias, pesos = zip(*DIAS_CIERRE)
        for loc in rng.sample(claves, self.cfg.n_salas):           # una sala por localidad elegida
            self.plan.salas.append(dict(loc=loc, calle=self._calle(fk), numero=str(rng.randint(1, 4999)),
                                        dia_cierre=rng.choices(dias, weights=pesos)[0]))

    def _transportistas(self):
        rng, fk = self._rng("transportistas"), self._faker("transportistas")
        cuits = GeneradorCuit(rng, (30, 33), 55_000_000, 59_999_999)
        formas = ("Transportes {a} S.R.L.", "Logística {a} S.A.", "Expreso {a} S.A.", "Fletes {a} S.R.L.")
        locs_salas = [s["loc"] for s in self.plan.salas]
        for i in range(1, self.cfg.n_transportistas + 1):
            emails = [f"contacto.st{i:03d}@example.com"]
            if rng.random() < 0.5:
                emails.append(f"operaciones.st{i:03d}@example.com")
            telefonos = []
            for _ in range(rng.randint(1, 2)):
                tel = f"261 4{rng.randint(10, 99)}-{rng.randint(1000, 9999)}"
                if tel not in telefonos:
                    telefonos.append(tel)
            self.plan.transportistas.append(dict(
                cod=f"ST-{i:03d}", razon_social=rng.choice(formas).format(a=fk.last_name())[:100],
                cuit=cuits.nuevo(), calle=self._calle(fk), numero=str(rng.randint(1, 9999)),
                emails=emails, telefonos=telefonos,
                localidades=rng.sample(locs_salas, self.cfg.localidades_por_transportista)))

    def _empleados(self):
        rng, fk = self._rng("empleados"), self._faker("empleados")
        cuits = GeneradorCuit(rng, (20, 27), 20_000_000, 45_999_999)
        salas = list(range(self.cfg.n_salas)) + [rng.randrange(self.cfg.n_salas) for _ in range(self.cfg.n_empleados - self.cfg.n_salas)]
        for s in salas:                                    # toda sala tiene al menos un empleado
            self.plan.empleados.append(dict(
                cuit=cuits.nuevo(), nombre=f"{fk.first_name()} {fk.last_name()}"[:100],
                fecha_ingreso=fecha_al_azar(rng, INGRESO_EMPLEADOS_DESDE, INGRESO_EMPLEADOS_HASTA),
                salario=dinero(rng.randrange(650_000, 1_900_000, 1000)), sala=s))

    def _fincas_parcelas_lotes(self):
        rng, fk = self._rng("fincas"), self._faker("fincas")
        deps = [d for d, _ in self.plan.cat.departamentos]
        pesos_dep = [PESO_DEPTO_FINCA.get(d, 0.5) for d in deps]
        cepas = [c for c, _ in self.plan.cat.cepas]
        pesos_cepa = [PESO_CEPA.get(c, 3) for c in cepas]
        formas = ("Finca {a}", "Finca Los {a}", "Viñedo {a}", "Finca La {a}", "Estancia {a}")
        nombres = set()
        while len(self.plan.fincas) < self.cfg.n_fincas:
            nombre = rng.choice(formas).format(a=fk.last_name())[:100]
            if nombre in nombres:
                continue
            nombres.add(nombre)
            self.plan.fincas.append(dict(nombre=nombre, sup=dinero(rng.uniform(15, 400)),
                                         departamento=rng.choices(deps, weights=pesos_dep)[0]))
        n_lote = 0
        for f_idx, finca in enumerate(self.plan.fincas):
            n = rng.randint(*self.cfg.parcelas_por_finca)
            partes = [rng.uniform(1, 3) for _ in range(n)]
            total = sum(partes)
            for num in range(1, n + 1):
                sup = max(dinero(finca["sup"] * Decimal(partes[num - 1] / total) * Decimal("0.85")), Decimal("0.50"))
                anio = rng.randint(1985, 2021)
                self.plan.parcelas.append(dict(finca=f_idx, num=num, superficie=sup, anio=anio,
                                               cepa=rng.choices(cepas, weights=pesos_cepa)[0]))
                for campania in CAMPANIAS:                 # RN-04: una cosecha por campaña
                    if campania < anio + 3 or rng.random() >= 0.95:
                        continue
                    n_lote += 1
                    cosecha = fecha_al_azar(rng, date(campania, 2, 1), date(campania, 4, 30))
                    kilos = dinero(sup * Decimal(rng.uniform(6000, 12000)))
                    lote = len(self.plan.lotes)
                    self.plan.lotes.append(dict(num_lote=f"SL-{campania}-{n_lote:05d}", finca=f_idx,
                                                num_parcela=num, campania=campania, fecha=cosecha,
                                                kilos=kilos, bodega=rng.randrange(self.cfg.n_bodegas)))
                    for dias in sorted(rng.sample(range(0, 6), rng.choices((1, 2, 3), weights=(30, 45, 25))[0])):
                        self.plan.analisis.append(dict(
                            lote=lote, fecha=cosecha + timedelta(days=dias),
                            brix=Decimal(str(round(rng.uniform(20.0, 27.0), 1))),
                            ph=Decimal(str(round(rng.uniform(3.2, 3.9), 2))),
                            acidez=Decimal(str(round(rng.uniform(4.5, 8.0), 2)))))

    # -- vinos -----------------------------------------------------------
    def _composicion(self, rng, tipo, tintas, blancas):
        def reparto(n):
            if n == 1:
                return [100]
            if n == 2:
                a = rng.choice((50, 55, 60, 65, 70, 75, 80, 85))
                return [a, 100 - a]
            a = rng.choice((40, 45, 50, 55, 60, 65, 70))
            b = rng.choice([x for x in range(15, 100 - a - 10 + 1, 5)])
            return [a, b, 100 - a - b]

        if tipo == "tinto":
            n = 1 if rng.random() < 0.65 else rng.choice((2, 3))
            elegidas = rng.sample(tintas, min(n, len(tintas)))
        elif tipo == "blanco":
            n = 1 if rng.random() < 0.75 else 2
            elegidas = rng.sample(blancas, min(n, len(blancas)))
        elif tipo == "rosado":
            n = 1 if rng.random() < 0.6 else 2
            elegidas = rng.sample(tintas, min(n, len(tintas)))
        else:  # espumante: método tradicional con Chardonnay y Pinot Noir si están en el catálogo
            clasicas = [c for c in ("Chardonnay", "Pinot Noir") if c in tintas + blancas]
            if len(clasicas) == 2 and rng.random() < 0.6:
                elegidas = clasicas
            else:
                elegidas = rng.sample(blancas, min(rng.choice((1, 2)), len(blancas)))
        return list(zip(elegidas, (Decimal(p) for p in reparto(len(elegidas)))))

    def _vinos(self):
        rng = self._rng("vinos")
        tintas = [c for c, t in self.plan.cat.cepas if t == "tinta"]
        blancas = [c for c, t in self.plan.cat.cepas if t == "blanca"]
        maridajes_cat = [m for m, _ in self.plan.cat.maridajes]
        pesos_bodega = [rng.randint(1, 5) for _ in range(self.cfg.n_bodegas)]
        bodega_de = list(range(self.cfg.n_bodegas)) + rng.choices(range(self.cfg.n_bodegas), weights=pesos_bodega,
                                                        k=self.cfg.n_vinos - self.cfg.n_bodegas)
        rng.shuffle(bodega_de)
        tipos, pesos_tipo = zip(*TIPOS_VINO)
        usados = set()
        for i in range(self.cfg.n_vinos):
            b = bodega_de[i]
            marca = self.plan.bodegas[b]["marca"]
            for _intento in range(200):
                tipo = rng.choices(tipos, weights=pesos_tipo)[0]
                presentaciones = [p for p in PRESENTACIONES if tipo != "espumante" or p[0] != 3000]
                ml = rng.choices([p for p, _ in presentaciones], weights=[w for _, w in presentaciones])[0]
                cepas = self._composicion(rng, tipo, tintas, blancas)
                principal = cepas[0][0]
                if tipo == "espumante":
                    linea, factor = rng.choice(LINEAS_ESPUMANTE), Decimal("1.2")
                    nombre = f"{marca} {linea}"
                else:
                    linea, factor = rng.choice(LINEAS)
                    if tipo == "rosado":
                        etiqueta = f"Rosé de {principal}"
                    elif len(cepas) == 1:
                        etiqueta = principal
                    else:
                        etiqueta = "Blend de Tintas" if tipo == "tinto" else "Blend de Blancas"
                    nombre = f"{marca} {linea} {etiqueta}"
                anada = rng.randint(ANADA_MIN, ANADA_MAX)
                if (nombre, anada, ml) not in usados:      # UNIQUE (nombre_comercial, anada, presentacion_ml)
                    break
            else:
                raise ErrorCarga(f"No se pudo generar un nombre único para el vino {i + 1}")
            usados.add((nombre, anada, ml))
            g_min, g_max = GRADUACION[tipo]
            p_min, p_max = PRECIO_BASE_750[tipo]
            precio = redondear_a_10(Decimal(rng.randint(p_min, p_max)) * factor * FACTOR_PRESENTACION[ml])
            opciones = [m for m in MARIDAJES_POR_TIPO[tipo] if m in maridajes_cat] or maridajes_cat
            maridajes = rng.sample(opciones, rng.randint(1, min(3, len(opciones))))
            self.plan.vinos.append(dict(
                cod=f"SV-{i + 1:04d}", nombre=nombre[:100], tipo=tipo, anada=anada, ml=ml,
                graduacion=Decimal(str(round(rng.uniform(g_min, g_max), 1))), precio=precio,
                bodega=b, cepas=cepas, maridajes=maridajes))

    # -- clientes --------------------------------------------------------
    def _clientes(self):
        rng, fk = self._rng("clientes"), self._faker("clientes")
        n_socio = round(self.cfg.n_clientes * self.cfg.mix_clientes[0][1])
        n_dist = round(self.cfg.n_clientes * self.cfg.mix_clientes[1][1])
        tipos = (["Socio"] * n_socio + ["Distribuidor"] * n_dist
                 + ["Exportador"] * (self.cfg.n_clientes - n_socio - n_dist))
        rng.shuffle(tipos)
        dnis = iter(rng.sample(range(20_000_000, 46_000_000), n_socio))
        cuits = GeneradorCuit(rng, (30, 33), 65_000_000, 99_999_999)
        zona_de = {d: z for z, ds in ZONAS.items() for d in ds}
        depto_de = {(nombre, cp): dep for cp, nombre, _p, dep in self.plan.cat.localidades}
        claves_loc = [(nombre, cp) for cp, nombre, _p, _d in self.plan.cat.localidades]
        n_hab = n_perm = 0
        for i, tipo in enumerate(tipos):
            loc = rng.choice(claves_loc)
            alta = fecha_al_azar(rng, ALTA_CLIENTES_DESDE, ALTA_CLIENTES_HASTA)
            cliente = dict(tipo=tipo, loc=loc, calle=self._calle(fk), numero=str(rng.randint(1, 9999)),
                           fecha_alta=alta)
            if tipo == "Socio":
                cliente.update(tipo_doc="DNI", num_doc=str(next(dnis)),
                               nombre=f"{fk.first_name()} {fk.last_name()}"[:100])
            elif tipo == "Distribuidor":
                n_hab += 1
                forma = rng.choice(("Distribuidora {a} S.R.L.", "{a} Distribuciones S.A.", "Vinoteca {a}"))
                zona = zona_de.get(depto_de[loc], "Mendoza")
                cliente.update(tipo_doc="CUIT", num_doc=cuits.nuevo(), nombre=forma.format(a=fk.last_name())[:100],
                               zona=f"{zona} - Mendoza", habilitacion=f"HAB-{n_hab:06d}")
            else:
                forma = rng.choice(("{a} Export S.A.", "{a} Wines Trading S.A.", "Comercio Exterior {a} S.R.L."))
                cliente.update(tipo_doc="CUIT", num_doc=cuits.nuevo(), nombre=forma.format(a=fk.last_name())[:100],
                               pais=rng.choice(PAISES))
                for _ in range(rng.randint(1, 3)):          # RN-07: varios permisos por exportador
                    n_perm += 1
                    emision = fecha_al_azar(rng, max(alta, PERMISOS_DESDE), PERMISOS_HASTA)
                    self.plan.permisos.append(dict(codigo=f"PEX-{n_perm:06d}", emision=emision,
                                                   vencimiento=emision + timedelta(days=365 * rng.randint(1, 2)),
                                                   cliente=i))
            self.plan.clientes.append(cliente)

    # -- movimientos -----------------------------------------------------
    def _catalogo_salas(self):
        """Cada sala vende self.cfg.vinos_por_sala vinos; reparto circular => cada vino en la misma cantidad de salas."""
        if self.cfg.vinos_por_sala > self.cfg.n_vinos:
            raise ErrorCarga("self.cfg.vinos_por_sala no puede superar self.cfg.n_vinos")
        rng = self._rng("catalogo_salas")
        orden = list(range(self.cfg.n_vinos))
        rng.shuffle(orden)
        self.plan.catalogo_sala = [[orden[(s * self.cfg.vinos_por_sala + j) % self.cfg.n_vinos] for j in range(self.cfg.vinos_por_sala)]
                                   for s in range(self.cfg.n_salas)]

    def _ventas(self) -> dict[tuple[int, int], int]:
        """Ventas del día de carga D. Sólo venden las salas que no cierran ese día de la semana.
        La fecha NO forma parte del plan: la asigna la base (DEFAULT CURRENT_DATE)."""
        rng = self._rng("ventas")
        dia_carga = DIAS_SEMANA[self.plan.fecha_carga.isoweekday() - 1]
        abiertas = [s for s, sala in enumerate(self.plan.salas) if sala["dia_cierre"] != dia_carga]
        if not abiertas:
            raise ErrorCarga(f"Ninguna sala abre el {dia_carga}: no se pueden generar ventas")
        cantidades = []
        for k, pct in self.cfg.renglones_por_comprobante:
            cantidades += [k] * round(self.cfg.n_comprobantes * pct / 100)
        cantidades = (cantidades + [3] * self.cfg.n_comprobantes)[:self.cfg.n_comprobantes]
        rng.shuffle(cantidades)
        por_tipo = defaultdict(list)
        for idx, c in enumerate(self.plan.clientes):
            por_tipo[c["tipo"]].append(idx)
        pesos_sala = [rng.randint(1, 4) for _ in range(self.cfg.n_salas)]     # se sortean siempre las 100 (determinismo)
        salas = rng.choices(abiertas, weights=[pesos_sala[s] for s in abiertas], k=self.cfg.n_comprobantes)
        tipos_c, pesos_c = zip(*self.cfg.mix_compradores)
        compradores = rng.choices(tipos_c, weights=pesos_c, k=self.cfg.n_comprobantes)
        demanda: dict[tuple[int, int], int] = defaultdict(int)
        comprobantes = []
        for i in range(self.cfg.n_comprobantes):
            s = salas[i]
            tipo = compradores[i]
            cliente = rng.choice(por_tipo[tipo])            # fecha_alta <= 2024-12-31 < D
            lo, hi = self.cfg.botellas_por_renglon[tipo]
            renglones = tuple((v, rng.randint(lo, hi)) for v in rng.sample(self.plan.catalogo_sala[s], cantidades[i]))
            for v, q in renglones:
                demanda[(s, v)] += q
            comprobantes.append((f"SC-{i + 1:07d}", cliente, s, renglones))
        self.plan.comprobantes = comprobantes
        return demanda

    def _transferencias(self, demanda) -> dict[int, int]:
        """Abastece cada (sala, vino) con lo vendido + margen, en self.cfg.rondas_transferencia transferencias."""
        rng = self._rng("transferencias")
        demanda_deposito: dict[int, int] = defaultdict(int)
        n = 0
        for s in range(self.cfg.n_salas):
            partes = {}
            for v in self.plan.catalogo_sala[s]:
                total = math.ceil(Decimal(demanda.get((s, v), 0)) * self.cfg.margen_transferencia) + self.cfg.extra_transferencia
                base, resto = divmod(total, self.cfg.rondas_transferencia)
                partes[v] = [base + (1 if r < resto else 0) for r in range(self.cfg.rondas_transferencia)]
                demanda_deposito[v] += total
            for r in range(self.cfg.rondas_transferencia):
                orden = self.plan.catalogo_sala[s][:]
                rng.shuffle(orden)
                for grupo in trozos(orden, self.cfg.vinos_por_transferencia):
                    n += 1
                    self.plan.transferencias.append(dict(num=f"STR-{n:06d}", sala=s,
                                                         renglones=tuple((v, partes[v][r]) for v in grupo)))
        return demanda_deposito

    def _ingresos(self, demanda_deposito):
        """Cada ingreso trae vinos de UNA bodega (la que elabora esos vinos)."""
        rng = self._rng("ingresos")
        vinos_de = defaultdict(list)
        for idx, v in enumerate(self.plan.vinos):
            vinos_de[v["bodega"]].append(idx)
        borradores = []
        for b in range(self.cfg.n_bodegas):
            lista = vinos_de[b][:]
            rng.shuffle(lista)
            n, m = len(lista), min(self.cfg.renglones_por_ingreso, len(lista))
            cantidad = max(math.ceil(n / m), round(n * self.cfg.ingresos_objetivo / self.cfg.n_vinos))
            for j in range(cantidad):                       # reparto circular: vinos distintos por ingreso
                borradores.append((b, [lista[(j * m + t) % n] for t in range(m)]))
        apariciones = Counter(v for _b, vs in borradores for v in vs)
        total_vino = {v: max(apariciones[v],
                             math.ceil(Decimal(demanda_deposito.get(v, 0)) * self.cfg.margen_ingreso) + self.cfg.extra_ingreso)
                      for v in apariciones}
        repartidas = Counter()
        temporal = []
        for k, (b, vs) in enumerate(borradores):
            renglones = []
            for v in vs:
                base, resto = divmod(total_vino[v], apariciones[v])
                renglones.append((v, base + (1 if repartidas[v] < resto else 0)))
                repartidas[v] += 1
            temporal.append((fecha_al_azar(rng, INGRESOS_DESDE, INGRESOS_HASTA), b, k,
                             rng.randrange(self.cfg.n_transportistas), tuple(renglones)))
        temporal.sort(key=lambda t: (t[0], t[1], t[2]))
        self.plan.ingresos = [dict(cod=f"SI-{n:06d}", fecha=f, transportista=tr, bodega=b, renglones=r)
                              for n, (f, b, _k, tr, r) in enumerate(temporal, 1)]

    def _ajustes_precio(self):
        rng = self._rng("precios")
        for v in sorted(rng.sample(range(self.cfg.n_vinos), self.cfg.precios_a_ajustar)):
            anterior = self.plan.vinos[v]["precio"]
            nuevo = redondear_a_10(anterior * Decimal(str(round(1 + rng.uniform(0.05, 0.15), 4))))
            if nuevo == anterior:
                nuevo += 10
            self.plan.ajustes_precio.append((v, anterior, dinero(nuevo)))


def resumen_plan(plan: Plan) -> list[str]:
    conteos = plan.conteos()
    lineas = [f"Perfil: {plan.perfil.nombre}", f"{'Tabla':<26}{'Filas':>10}"]
    for t in TODAS_LAS_TABLAS:
        lineas.append(f"{t:<26}{num(conteos[t]):>10}")
    mas_10k = [t for t, n in conteos.items() if n > 10_000]
    mas_100k = [t for t, n in conteos.items() if n > 100_000]
    vacias = [t for t, n in conteos.items() if n == 0]
    lineas.append("")
    lineas.append(f"Tablas con más de 10.000 filas: {len(mas_10k)} {mas_10k}")
    lineas.append(f"Tablas con más de 100.000 filas: {len(mas_100k)} {mas_100k}")
    lineas.append(f"Tablas vacías: {vacias or 'ninguna'}")
    botellas_venta = sum(q for c in plan.comprobantes for _v, q in c[3])
    botellas_transf = sum(q for t in plan.transferencias for _v, q in t["renglones"])
    botellas_ing = sum(q for i in plan.ingresos for _v, q in i["renglones"])
    lineas.append(f"Botellas: ingresadas {num(botellas_ing)}, transferidas {num(botellas_transf)}, "
                  f"vendidas {num(botellas_venta)}")
    dia = DIAS_SEMANA[plan.fecha_carga.isoweekday() - 1]
    abiertas = sum(s["dia_cierre"] != dia for s in plan.salas)
    lineas.append(f"Fecha de carga (D): {plan.fecha_carga} ({dia}); salas que venden ese día: {abiertas}/{len(plan.salas)}")
    lineas.append(f"Locale de Faker: {plan.locale_faker}; Python {sys.version.split()[0]}")
    return lineas


def controlar_requisitos_volumen(plan: Plan):
    """Todas las tablas con filas (cualquier perfil) y mínimos de la Etapa 3 del TPI
    (sólo perfiles con exigir_volumen_tpi, es decir el definitivo)."""
    conteos = plan.conteos()
    if any(n == 0 for n in conteos.values()):
        raise ErrorCarga(f"El plan deja tablas vacías: {[t for t, n in conteos.items() if n == 0]}")
    if not plan.perfil.exigir_volumen_tpi:
        return
    if sum(n > 10_000 for n in conteos.values()) < 3 or not any(n > 100_000 for n in conteos.values()):
        raise ErrorCarga("El plan no alcanza los mínimos de volumen de la Etapa 3")


# =====================================================================
# Conexión
# =====================================================================
def leer_env_archivo(ruta: Path) -> dict[str, str]:
    """Lee KEY=VALUE de un .env sin ejecutar nada. Las variables ya definidas tienen prioridad."""
    valores = {}
    if ruta.exists():
        for linea in ruta.read_text(encoding="utf-8-sig").splitlines():
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            clave, valor = linea.split("=", 1)
            valores[clave.strip()] = valor.strip().strip('"').strip("'")
    return valores


def parametros_conexion(archivo_env: Path, usar_entorno: bool = True) -> dict:
    """Arma host/port/dbname/user/password. Con usar_entorno=True las variables del
    proceso tienen prioridad sobre el archivo; con False SÓLO se usa el archivo
    (perfil prueba: nunca se toma un destino heredado del entorno)."""
    archivo = leer_env_archivo(archivo_env)

    def var(*nombres, defecto=None):
        for n in nombres:
            if usar_entorno and os.environ.get(n):
                return os.environ[n]
        for n in nombres:
            if archivo.get(n):
                return archivo[n]
        return defecto

    params = dict(host=var("POSTGRES_HOST", "PGHOST", defecto="127.0.0.1"),
                  port=int(var("POSTGRES_PORT", "PGPORT", defecto="55432")),
                  dbname=var("POSTGRES_DB", "PGDATABASE"),
                  user=var("POSTGRES_USER", "PGUSER"),
                  password=var("POSTGRES_PASSWORD", "PGPASSWORD"))
    faltan = [k for k in ("dbname", "user") if not params[k]]
    if faltan:
        raise ErrorCarga(f"Faltan variables de conexión: {faltan} (ver .env.example)")
    return params


ARCHIVO_ENV_PRINCIPAL = DIR_REPO / ".env"
MARCA_ENTORNO_PRUEBA = ("BODEGAS_ENTORNO", "prueba")   # debe figurar en el .env de prueba


def destino_texto(params: dict) -> str:
    """Destino legible SIN contraseña."""
    return f"{params['user']}@{params['host']}:{params['port']}/{params['dbname']}"


def parametros_destino(perfil: Perfil, archivo_env: Path | None) -> dict:
    """Parámetros de conexión según el perfil, con las protecciones del perfil prueba:
      * exige --env explícito (nunca el .env principal por defecto);
      * el archivo debe declarar BODEGAS_ENTORNO=prueba;
      * sólo se leen las variables del archivo (no las del proceso);
      * el destino no puede usar el PUERTO ni el NOMBRE DE BASE de la principal,
        con CUALQUIER host (127.0.0.1, IP de la red, host.docker.internal... pueden
        ser la misma instancia). La principal se toma del .env de la raíz, de las
        variables del proceso (lo que usaría el perfil definitivo) y de los valores
        por defecto de docker-compose.yml (55432 / bodegas_atuel);
      * después de conectar, main() verifica current_database()."""
    if not perfil.exige_entorno_prueba:
        return parametros_conexion(archivo_env or ARCHIVO_ENV_PRINCIPAL)
    if archivo_env is None:
        raise ErrorCarga(f"El perfil '{perfil.nombre}' exige --env con un archivo de conexión de PRUEBA "
                         "(p. ej. --env .env.prueba). No se usa el .env principal.")
    archivo_env = archivo_env.resolve()
    if not archivo_env.exists():
        raise ErrorCarga(f"No existe el archivo de conexión de prueba {archivo_env}")
    if archivo_env == ARCHIVO_ENV_PRINCIPAL.resolve():
        raise ErrorCarga("El perfil prueba no puede usar el .env principal: indicar un .env de prueba")
    clave, valor = MARCA_ENTORNO_PRUEBA
    if leer_env_archivo(archivo_env).get(clave) != valor:
        raise ErrorCarga(f"{archivo_env.name} no declara {clave}={valor}: no se reconoce como entorno de prueba")
    prueba = parametros_conexion(archivo_env, usar_entorno=False)
    puertos_principal, bases_principal = {55432}, {"bodegas_atuel"}      # docker-compose.yml / .env.example
    archivo_principal = leer_env_archivo(ARCHIVO_ENV_PRINCIPAL)
    if archivo_principal.get("POSTGRES_PORT"):
        puertos_principal.add(int(archivo_principal["POSTGRES_PORT"]))
    if archivo_principal.get("POSTGRES_DB"):
        bases_principal.add(archivo_principal["POSTGRES_DB"])
    try:                                    # destino efectivo del perfil definitivo (entorno + .env)
        efectivo = parametros_conexion(ARCHIVO_ENV_PRINCIPAL)
        puertos_principal.add(efectivo["port"])
        bases_principal.add(efectivo["dbname"])
    except ErrorCarga:
        pass                                # sin destino definitivo configurado: quedan los de arriba
    if prueba["port"] in puertos_principal:
        raise ErrorCarga(f"El destino de prueba usa el puerto {prueba['port']}, que es el de la base principal "
                         f"(con cualquier host puede ser la misma instancia): elegir otro puerto")
    if prueba["dbname"] in bases_principal:
        raise ErrorCarga(f"El destino de prueba usa el nombre de base '{prueba['dbname']}', igual al de la "
                         "base principal: elegir otro nombre")
    return prueba


def conectar(params: dict):
    try:
        import psycopg
    except ImportError as exc:  # pragma: no cover
        raise ErrorCarga("Falta el paquete psycopg: ejecutar 'uv sync' en la raíz del repositorio") from exc
    conn = psycopg.connect(**params, autocommit=True, application_name="bodegas_carga_masiva")
    # Las funciones de 003 y varias de 005 nombran las tablas sin esquema:
    # la sesión DEBE tener search_path = bodegas (también al hacer COMMIT,
    # cuando corren los triggers diferidos de RN-05).
    conn.execute(f"SET search_path TO {ESQUEMA}")
    conn.execute("SET client_min_messages TO warning")
    return conn


# =====================================================================
# Carga
# =====================================================================
@dataclass
class Fase:
    clave: str
    titulo: str
    ejecutar: Callable[[], None]
    reanudable: bool = False


class Cargador:
    def __init__(self, conn):
        self.conn = conn
        self.plan: Plan | None = None
        self.esperados: dict[str, int] = {}
        self.tiempos: list[tuple[str, float]] = []
        self.interrumpir_en_lote: int | None = None   # sólo pruebas (ver --interrumpir-en-lote)
        self.fases = [
            Fase("catalogos", "Catálogos CSV: encargado, departamento, cepa, maridaje, tipo_cliente, localidad",
                 self.fase_catalogos),
            Fase("maestros", "Maestros: bodega, transportista (+email, teléfono, cobertura), sala, empleado, "
                             "finca, parcela, lote, análisis", self.fase_maestros),
            Fase("vinos", "Vinos con su composición (RN-05) y maridajes", self.fase_vinos),
            Fase("clientes", "Clientes, subtipos y permisos de exportación", self.fase_clientes),
            Fase("ingresos", "Ingresos -> terminado -> sp_procesar_ingreso", self.fase_ingresos, True),
            Fase("transferencias", "Transferencias -> terminado -> sp_procesar_transferencia",
                 self.fase_transferencias, True),
            Fase("comprobantes", "Comprobantes y renglones (triggers de venta)", self.fase_comprobantes, True),
            Fase("precios", "Cambios de precio (auditoría por trigger RN-13)", self.fase_precios),
        ]

    def usar_plan(self, plan: Plan):
        self.plan = plan
        self.esperados = plan.conteos()

    # -- consultas auxiliares --------------------------------------------
    def escalar(self, sql: str, params=None):
        with self.conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()[0]

    def filas(self, sql: str, params=None) -> list[tuple]:
        with self.conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()

    def conteo(self, tabla: str) -> int:
        return self.escalar(f"SELECT count(*) FROM {ESQUEMA}.{tabla}")

    def mapa(self, sql: str, params=None) -> dict:
        """Filas (id, clave...) -> {clave: id}. Falla si una clave aparece dos veces."""
        resultado = {}
        for fila in self.filas(sql, params):
            clave = fila[1] if len(fila) == 2 else tuple(fila[1:])
            if clave in resultado:
                raise ErrorCarga(f"Clave duplicada en la base: {clave} ({sql.split('FROM')[1].split()[0]})")
            resultado[clave] = fila[0]
        return resultado

    @staticmethod
    def copiar(cur, tabla: str, columnas: Sequence[str], filas: Iterable[Sequence]) -> int:
        n = 0
        with cur.copy(f"COPY {ESQUEMA}.{tabla} ({', '.join(columnas)}) FROM STDIN") as cp:
            for fila in filas:
                cp.write_row(fila)
                n += 1
        return n

    # mapas de claves naturales -> id (nunca por posición)
    def mapa_localidades(self):
        return self.mapa(f"SELECT id_localidad, nombre, cod_postal FROM {ESQUEMA}.localidad")

    def mapa_departamentos(self):
        return self.mapa(f"SELECT id_departamento, nombre, provincia FROM {ESQUEMA}.departamento")

    def mapa_por_nombre(self, tabla: str, id_col: str):
        return self.mapa(f"SELECT {id_col}, nombre FROM {ESQUEMA}.{tabla}")

    def mapa_bodegas(self):
        return self.mapa(f"SELECT id_bodega, cuit FROM {ESQUEMA}.bodega")

    def mapa_transportistas(self):
        return self.mapa(f"SELECT id_transportista, cod_transporte FROM {ESQUEMA}.transportista")

    def mapa_salas(self):
        locs = self.mapa_localidades()
        por_dir = self.mapa(f"SELECT id_sala, id_localidad, calle, numero FROM {ESQUEMA}.sala_de_ventas")
        return [por_dir[(locs[s["loc"]], s["calle"], s["numero"])] for s in self.plan.salas]

    def mapa_vinos(self):
        cods = self.mapa(f"SELECT id_vino, cod_vino FROM {ESQUEMA}.vino")
        return [cods[v["cod"]] for v in self.plan.vinos]

    def mapa_clientes(self):
        docs = self.mapa(f"SELECT id_cliente, tipo_documento::text, num_documento FROM {ESQUEMA}.cliente")
        return [docs[(c["tipo_doc"], c["num_doc"])] for c in self.plan.clientes]

    # -- verificaciones previas --------------------------------------------
    def verificar_esquema(self):
        if not self.escalar("SELECT count(*) FROM pg_namespace WHERE nspname = %s", (ESQUEMA,)):
            raise ErrorCarga(f"No existe el esquema {ESQUEMA}: aplicar las migraciones 001 a 007")
        existentes = {r[0] for r in self.filas(
            "SELECT tablename FROM pg_tables WHERE schemaname = %s", (ESQUEMA,))}
        faltan = [t for t in TODAS_LAS_TABLAS if t not in existentes]
        if faltan:
            raise ErrorCarga(f"Faltan tablas del esquema: {faltan}")
        procs = {r[0] for r in self.filas(
            "SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
            "WHERE n.nspname = %s AND p.prokind = 'p'", (ESQUEMA,))}
        if not {"sp_procesar_ingreso", "sp_procesar_transferencia"} <= procs:
            raise ErrorCarga("Faltan los procedimientos de 004_procedimientos.sql")
        triggers = dict(self.filas(
            "SELECT t.tgname, t.tgenabled::text FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid "
            "JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = %s AND NOT t.tgisinternal",
            (ESQUEMA,)))
        faltan = [t for t in TRIGGERS_REQUERIDOS if t not in triggers]
        # tgenabled: 'O' = se dispara con session_replication_role 'origin' (normal);
        # 'A' = siempre; 'R' = sólo en modo réplica; 'D' = deshabilitado.
        # Sólo 'O' y 'A' garantizan que el trigger corra en una sesión normal.
        no_activos = {t: triggers[t] for t in TRIGGERS_REQUERIDOS if t in triggers and triggers[t] not in ("O", "A")}
        if faltan or no_activos:
            raise ErrorCarga(f"Triggers faltantes {faltan} o no activos {no_activos} (tgenabled): "
                             "la carga necesita todos los triggers de 005 activos")
        # Con session_replication_role = 'replica' los triggers 'O' NO se disparan,
        # aunque figuren habilitados (puede venir de ALTER ROLE/DATABASE ... SET).
        rol_replicacion = self.escalar("SELECT current_setting('session_replication_role')")
        if rol_replicacion != "origin":
            raise ErrorCarga(f"session_replication_role = '{rol_replicacion}': los triggers no se dispararían. "
                             "La carga exige 'origin' (el script no cambia este valor).")
        if "jueves" not in {r[0] for r in self.filas(
                f"SELECT unnest(enum_range(NULL::{ESQUEMA}.dia_semana))::text")}:
            raise ErrorCarga("dia_semana no tiene 'jueves': falta aplicar 002_constraints.sql")

    def presentes(self, sql: str, claves: list) -> list:
        return [r[0] for r in self.filas(sql, (claves,))]

    def estado_fase(self, fase: Fase) -> tuple[str, str]:
        """Devuelve (estado, detalle). Estados:
        pendiente       la fase no tiene filas;
        completa        están todas las claves del plan y las cantidades exactas;
        completa_extra  están todas las claves del plan y hay filas DE MÁS (actividad
                        posterior a la carga, p. ej. la API). Sólo se acepta si TODAS las
                        fases están completas (ver revisar());
        en_curso        fase por lotes con lotes completos del plan y nada ajeno;
        inconsistente   cualquier otra situación (no se escribe nada)."""
        tablas = TABLAS_POR_FASE[fase.clave]
        conteos = {t: self.conteo(t) for t in tablas}
        esperado = {t: self.esperados[t] for t in tablas}
        detalle = ", ".join(f"{t}={conteos[t]}/{esperado[t]}" for t in tablas)
        if fase.clave == "precios":
            return self._estado_precios(conteos, detalle)
        if all(n == 0 for n in conteos.values()):
            return "pendiente", detalle
        claves_ok = self._claves_completas(fase.clave)
        if claves_ok and conteos == esperado:
            estado = "completa"
        elif claves_ok and all(conteos[t] >= esperado[t] for t in tablas):
            estado = "completa_extra"
        elif fase.reanudable and self._reanudacion_valida(fase.clave, conteos):
            estado = "en_curso"
        else:
            return "inconsistente", detalle
        if fase.reanudable and not self._muestra_coincide(fase.clave):
            return "inconsistente", (detalle + " (el contenido de una muestra no coincide con el plan: "
                                     "otra semilla, otra versión de Python u otro día de la semana de carga)")
        return estado, detalle

    # Muestra de contenido (I2): los códigos SI-/STR-/SC- son correlativos y no
    # dependen de la semilla, así que además de las claves se compara el
    # contenido de hasta TAMANIO_MUESTRA documentos repartidos en todo el rango.
    TAMANIO_MUESTRA = 300

    @classmethod
    def _muestra(cls, codigos: list) -> list:
        codigos = sorted(codigos)
        paso = max(1, len(codigos) // cls.TAMANIO_MUESTRA)
        return codigos[::paso][:cls.TAMANIO_MUESTRA]

    def _muestra_coincide(self, clave: str) -> bool:
        p = self.plan
        if clave == "ingresos":
            plan = {i["cod"]: i for i in p.ingresos}
            muestra = self._muestra(self.presentes(
                f"SELECT cod_ingreso FROM {ESQUEMA}.ingreso WHERE cod_ingreso = ANY(%s::text[])", list(plan)))
            esperado = {c: (plan[c]["fecha"], p.transportistas[plan[c]["transportista"]]["cod"],
                            p.bodegas[plan[c]["bodega"]]["cuit"],
                            frozenset((p.vinos[v]["cod"], q) for v, q in plan[c]["renglones"])) for c in muestra}
            filas = self.filas(
                f"SELECT i.cod_ingreso, i.fecha, t.cod_transporte, b.cuit, v.cod_vino, r.cantidad_botellas "
                f"FROM {ESQUEMA}.ingreso i JOIN {ESQUEMA}.transportista t ON t.id_transportista = i.id_transportista "
                f"JOIN {ESQUEMA}.bodega b ON b.id_bodega = i.id_bodega "
                f"JOIN {ESQUEMA}.renglon_ingreso r ON r.id_ingreso = i.id_ingreso "
                f"JOIN {ESQUEMA}.vino v ON v.id_vino = r.id_vino WHERE i.cod_ingreso = ANY(%s::text[])", (muestra,))
            cab, ren = {}, defaultdict(set)
            for cod, fecha, tr, cuit, cod_vino, cant in filas:
                cab[cod] = (fecha, tr, cuit)
                ren[cod].add((cod_vino, cant))
            obtenido = {c: (*cab[c], frozenset(ren[c])) for c in cab}
            return obtenido == esperado
        if clave == "transferencias":
            plan = {t["num"]: t for t in p.transferencias}
            salas = self.mapa_salas()
            muestra = self._muestra(self.presentes(
                f"SELECT num_solicitud FROM {ESQUEMA}.transferencia WHERE num_solicitud = ANY(%s::text[])",
                list(plan)))
            esperado = {n: (salas[plan[n]["sala"]],
                            frozenset((p.vinos[v]["cod"], q) for v, q in plan[n]["renglones"])) for n in muestra}
            obtenido_cab, ren = {}, defaultdict(set)
            for num, id_sala, cod_vino, cant in self.filas(
                    f"SELECT t.num_solicitud, t.id_sala, v.cod_vino, r.cantidad_botellas "
                    f"FROM {ESQUEMA}.transferencia t "
                    f"JOIN {ESQUEMA}.renglon_transferencia r ON r.id_transferencia = t.id_transferencia "
                    f"JOIN {ESQUEMA}.vino v ON v.id_vino = r.id_vino WHERE t.num_solicitud = ANY(%s::text[])",
                    (muestra,)):
                obtenido_cab[num] = id_sala
                ren[num].add((cod_vino, cant))
            return {n: (obtenido_cab[n], frozenset(ren[n])) for n in obtenido_cab} == esperado
        if clave == "comprobantes":
            plan = {c[0]: c for c in p.comprobantes}
            salas = self.mapa_salas()
            muestra = self._muestra(self.presentes(
                f"SELECT num_comprobante FROM {ESQUEMA}.comprobante WHERE num_comprobante = ANY(%s::text[])",
                list(plan)))
            esperado = {n: ((p.clientes[plan[n][1]]["tipo_doc"], p.clientes[plan[n][1]]["num_doc"]),
                            salas[plan[n][2]],
                            frozenset((p.vinos[v]["cod"], q) for v, q in plan[n][3])) for n in muestra}
            obtenido_cab, ren = {}, defaultdict(set)
            for num, tipo_doc, num_doc, id_sala, cod_vino, cant in self.filas(
                    f"SELECT c.num_comprobante, cl.tipo_documento::text, cl.num_documento, c.id_sala, "
                    f"v.cod_vino, d.cantidad FROM {ESQUEMA}.comprobante c "
                    f"JOIN {ESQUEMA}.cliente cl ON cl.id_cliente = c.id_cliente "
                    f"JOIN {ESQUEMA}.detalle_comprobante d ON d.id_comprobante = c.id_comprobante "
                    f"JOIN {ESQUEMA}.vino v ON v.id_vino = d.id_vino WHERE c.num_comprobante = ANY(%s::text[])",
                    (muestra,)):
                obtenido_cab[num] = ((tipo_doc, num_doc), id_sala)
                ren[num].add((cod_vino, cant))
            return {n: (*obtenido_cab[n], frozenset(ren[n])) for n in obtenido_cab} == esperado
        return True

    def _claves_completas(self, clave: str) -> bool:
        p = self.plan
        consultas = {
            "catalogos": [(f"SELECT count(*) FROM {ESQUEMA}.encargado WHERE dni = ANY(%s::text[])",
                           [e[0] for e in p.cat.encargados])],
            "maestros": [(f"SELECT count(*) FROM {ESQUEMA}.bodega WHERE cuit = ANY(%s::text[])",
                          [b["cuit"] for b in p.bodegas]),
                         (f"SELECT count(*) FROM {ESQUEMA}.transportista WHERE cod_transporte = ANY(%s::text[])",
                          [t["cod"] for t in p.transportistas]),
                         (f"SELECT count(*) FROM {ESQUEMA}.empleado WHERE cuit = ANY(%s::text[])",
                          [e["cuit"] for e in p.empleados]),
                         (f"SELECT count(*) FROM {ESQUEMA}.lote_de_uva WHERE num_lote = ANY(%s::text[])",
                          [lt["num_lote"] for lt in p.lotes])],
            "vinos": [(f"SELECT count(*) FROM {ESQUEMA}.vino WHERE cod_vino = ANY(%s::text[])",
                       [v["cod"] for v in p.vinos])],
            "clientes": [(f"SELECT count(*) FROM {ESQUEMA}.cliente WHERE num_documento = ANY(%s::text[])",
                          [c["num_doc"] for c in p.clientes])],
            "ingresos": [(f"SELECT count(*) FROM {ESQUEMA}.ingreso WHERE cod_ingreso = ANY(%s::text[])",
                          [i["cod"] for i in p.ingresos])],
            "transferencias": [(f"SELECT count(*) FROM {ESQUEMA}.transferencia WHERE num_solicitud = ANY(%s::text[])",
                                [t["num"] for t in p.transferencias])],
            "comprobantes": [(f"SELECT count(*) FROM {ESQUEMA}.comprobante WHERE num_comprobante = ANY(%s::text[])",
                              [c[0] for c in p.comprobantes])],
        }
        return all(self.escalar(sql, (claves,)) == len(claves) for sql, claves in consultas[clave])

    def _reanudacion_valida(self, clave: str, conteos: dict) -> bool:
        """Una fase por lotes se puede reanudar si sólo contiene lotes completos del plan."""
        if clave == "ingresos":
            plan = {i["cod"]: i for i in self.plan.ingresos}
            hechos = self.presentes(f"SELECT cod_ingreso FROM {ESQUEMA}.ingreso WHERE cod_ingreso = ANY(%s::text[])",
                                    list(plan))
            return (conteos["ingreso"] == len(hechos)
                    and self.escalar(f"SELECT count(*) FROM {ESQUEMA}.ingreso WHERE estado <> 'procesado'") == 0
                    and conteos["renglon_ingreso"] == sum(len(plan[c]["renglones"]) for c in hechos)
                    and conteos["stock_deposito"] <= self.esperados["stock_deposito"])
        if clave == "transferencias":
            plan = {t["num"]: t for t in self.plan.transferencias}
            hechos = self.presentes(f"SELECT num_solicitud FROM {ESQUEMA}.transferencia "
                                    "WHERE num_solicitud = ANY(%s::text[])", list(plan))
            return (conteos["transferencia"] == len(hechos)
                    and self.escalar(f"SELECT count(*) FROM {ESQUEMA}.transferencia WHERE estado <> 'procesado'") == 0
                    and conteos["renglon_transferencia"] == sum(len(plan[n]["renglones"]) for n in hechos)
                    and conteos["stock_sala"] <= self.esperados["stock_sala"])
        if clave == "comprobantes":
            plan = {c[0]: c for c in self.plan.comprobantes}
            hechos = self.presentes(f"SELECT num_comprobante FROM {ESQUEMA}.comprobante "
                                    "WHERE num_comprobante = ANY(%s::text[])", list(plan))
            sin_renglones = self.escalar(
                f"SELECT count(*) FROM {ESQUEMA}.comprobante c WHERE NOT EXISTS "
                f"(SELECT 1 FROM {ESQUEMA}.detalle_comprobante d WHERE d.id_comprobante = c.id_comprobante)")
            return (conteos["comprobante"] == len(hechos) and sin_renglones == 0
                    and conteos["detalle_comprobante"] == sum(len(plan[n][3]) for n in hechos))
        return False

    def _estado_precios(self, conteos: dict, detalle: str) -> tuple[str, str]:
        """Completa si están las auditorías de los cambios planificados (precio anterior -> nuevo).
        Auditorías adicionales (cambios posteriores hechos por la API) dan 'completa_extra'."""
        p = self.plan
        cods = [p.vinos[v]["cod"] for v, _a, _n in p.ajustes_precio]
        planificadas = {(p.vinos[v]["cod"], a, n) for v, a, n in p.ajustes_precio}
        encontradas = set(self.filas(
            f"SELECT v.cod_vino, a.precio_anterior, a.precio_nuevo FROM {ESQUEMA}.auditoria_precio a "
            f"JOIN {ESQUEMA}.vino v ON v.id_vino = a.id_vino WHERE v.cod_vino = ANY(%s::text[])", (cods,)))
        actuales = dict(self.filas(f"SELECT cod_vino, precio_venta FROM {ESQUEMA}.vino "
                                   "WHERE cod_vino = ANY(%s::text[])", (cods,)))
        con_anterior = sum(actuales.get(p.vinos[v]["cod"]) == a for v, a, _n in p.ajustes_precio)
        hechas = len(planificadas & encontradas)
        if conteos["auditoria_precio"] == 0 and (con_anterior == len(planificadas) or not actuales):
            return "pendiente", detalle                     # sin vinos todavía, o precios originales
        if hechas == len(planificadas):
            if conteos["auditoria_precio"] == len(planificadas):
                return "completa", detalle
            return "completa_extra", detalle
        return "inconsistente", detalle + f" (cambios planificados auditados {hechas}/{len(planificadas)})"

    # -- fases ---------------------------------------------------------------
    def fase_catalogos(self):
        cat = self.plan.cat
        with self.conn.transaction(), self.conn.cursor() as cur:
            self.copiar(cur, "encargado", ("dni", "nombre", "apellido"), cat.encargados)
            self.copiar(cur, "departamento", ("nombre", "provincia"), cat.departamentos)
            self.copiar(cur, "cepa", ("nombre", "tipo"), cat.cepas)
            self.copiar(cur, "maridaje", ("nombre", "temperatura_sugerida"), cat.maridajes)
            self.copiar(cur, "tipo_cliente", ("nombre", "porcentaje_descuento"), cat.tipos_cliente)
            id_enc = self.mapa(f"SELECT id_encargado, dni FROM {ESQUEMA}.encargado")
            # La localidad se relaciona con su encargado por la clave (nombre, cod_postal) -> dni
            filas = [(cp, nombre, prov, id_enc[cat.encargado_de_localidad[(nombre, cp)]])
                     for cp, nombre, prov, _dep in cat.localidades]
            self.copiar(cur, "localidad", ("cod_postal", "nombre", "provincia", "id_encargado"), filas)
            obtenido = {(n, cp): dni for n, cp, dni in self.filas(
                f"SELECT l.nombre, l.cod_postal, e.dni FROM {ESQUEMA}.localidad l "
                f"JOIN {ESQUEMA}.encargado e USING (id_encargado)")}
            if obtenido != cat.encargado_de_localidad:
                raise ErrorCarga("La relación localidad-encargado cargada no coincide con el CSV")

    def fase_maestros(self):
        p = self.plan
        with self.conn.transaction(), self.conn.cursor() as cur:
            locs = self.mapa_localidades()
            deps = self.mapa_departamentos()
            cepas = self.mapa_por_nombre("cepa", "id_cepa")
            self.copiar(cur, "bodega", ("cuit", "razon_social", "calle", "numero"),
                        ((b["cuit"], b["razon_social"], b["calle"], b["numero"]) for b in p.bodegas))
            bodegas = self.mapa_bodegas()
            self.copiar(cur, "transportista", ("cod_transporte", "razon_social", "cuit", "calle", "numero"),
                        ((t["cod"], t["razon_social"], t["cuit"], t["calle"], t["numero"]) for t in p.transportistas))
            transp = self.mapa_transportistas()
            self.copiar(cur, "transportista_email", ("id_transportista", "email"),
                        ((transp[t["cod"]], e) for t in p.transportistas for e in t["emails"]))
            self.copiar(cur, "transportista_telefono", ("id_transportista", "telefono"),
                        ((transp[t["cod"]], tel) for t in p.transportistas for tel in t["telefonos"]))
            self.copiar(cur, "sala_de_ventas", ("calle", "numero", "dia_cierre_semanal", "id_localidad"),
                        ((s["calle"], s["numero"], s["dia_cierre"], locs[s["loc"]]) for s in p.salas))
            salas = self.mapa_salas()
            self.copiar(cur, "transportista_localidad", ("id_transportista", "id_localidad"),
                        ((transp[t["cod"]], locs[loc]) for t in p.transportistas for loc in t["localidades"]))
            self.copiar(cur, "empleado", ("cuit", "nombre", "fecha_ingreso", "salario", "id_sala"),
                        ((e["cuit"], e["nombre"], e["fecha_ingreso"], e["salario"], salas[e["sala"]])
                         for e in p.empleados))
            provincia = {n: pr for n, pr in p.cat.departamentos}
            self.copiar(cur, "finca", ("nombre", "sup_total_ha", "id_departamento"),
                        ((f["nombre"], f["sup"], deps[(f["departamento"], provincia[f["departamento"]])])
                         for f in p.fincas))
            fincas_db = self.mapa(f"SELECT id_finca, nombre FROM {ESQUEMA}.finca")
            fincas = [fincas_db[f["nombre"]] for f in p.fincas]
            self.copiar(cur, "parcela", ("id_finca", "num_parcela", "superficie", "anio_plantacion", "id_cepa"),
                        ((fincas[pa["finca"]], pa["num"], pa["superficie"], pa["anio"], cepas[pa["cepa"]])
                         for pa in p.parcelas))
            self.copiar(cur, "lote_de_uva", ("num_lote", "id_finca", "num_parcela", "campania", "fecha_cosecha",
                                             "kilos_cosechados", "id_bodega_entrega"),
                        ((lt["num_lote"], fincas[lt["finca"]], lt["num_parcela"], lt["campania"], lt["fecha"],
                          lt["kilos"], bodegas[p.bodegas[lt["bodega"]]["cuit"]]) for lt in p.lotes))
            lotes_db = self.mapa(f"SELECT id_lote_uva, num_lote FROM {ESQUEMA}.lote_de_uva")
            self.copiar(cur, "analisis_calidad", ("id_lote_uva", "fecha", "grado_brix", "ph", "acidez_total"),
                        ((lotes_db[p.lotes[a["lote"]]["num_lote"]], a["fecha"], a["brix"], a["ph"], a["acidez"])
                         for a in p.analisis))

    def fase_vinos(self):
        p = self.plan
        with self.conn.transaction(), self.conn.cursor() as cur:
            bodegas = self.mapa_bodegas()
            cepas = self.mapa_por_nombre("cepa", "id_cepa")
            maridajes = self.mapa_por_nombre("maridaje", "id_maridaje")
            self.copiar(cur, "vino", ("cod_vino", "nombre_comercial", "tipo", "anada", "presentacion_ml",
                                      "graduacion_alcoholica", "precio_venta", "id_bodega"),
                        ((v["cod"], v["nombre"], v["tipo"], v["anada"], v["ml"], v["graduacion"], v["precio"],
                          bodegas[p.bodegas[v["bodega"]]["cuit"]]) for v in p.vinos))
            vinos = self.mapa_vinos()
            self.copiar(cur, "vino_cepa", ("id_vino", "id_cepa", "porcentaje_corte"),
                        ((vinos[i], cepas[c], pct) for i, v in enumerate(p.vinos) for c, pct in v["cepas"]))
            self.copiar(cur, "vino_maridaje", ("id_vino", "id_maridaje"),
                        ((vinos[i], maridajes[m]) for i, v in enumerate(p.vinos) for m in v["maridajes"]))
            # RN-05: el trigger diferido controla que cada vino sume 100. Se adelanta
            # el control para fallar acá con un mensaje claro (si falla, ROLLBACK de todo).
            cur.execute("SET CONSTRAINTS ALL IMMEDIATE")

    def fase_clientes(self):
        p = self.plan
        with self.conn.transaction(), self.conn.cursor() as cur:
            locs = self.mapa_localidades()
            tipos = self.mapa_por_nombre("tipo_cliente", "id_tipo_cliente")
            self.copiar(cur, "cliente", ("nombre_o_razon_social", "tipo_documento", "num_documento", "calle",
                                         "numero", "fecha_alta", "id_localidad", "id_tipo_cliente"),
                        ((c["nombre"], c["tipo_doc"], c["num_doc"], c["calle"], c["numero"], c["fecha_alta"],
                          locs[c["loc"]], tipos[c["tipo"]]) for c in p.clientes))
            ids = self.mapa_clientes()
            self.copiar(cur, "socio", ("id_cliente",),
                        ((ids[i],) for i, c in enumerate(p.clientes) if c["tipo"] == "Socio"))
            self.copiar(cur, "distribuidor", ("id_cliente", "zona_cobertura", "numero_habilitacion"),
                        ((ids[i], c["zona"], c["habilitacion"]) for i, c in enumerate(p.clientes)
                         if c["tipo"] == "Distribuidor"))
            self.copiar(cur, "exportador", ("id_cliente", "pais_destino_principal"),
                        ((ids[i], c["pais"]) for i, c in enumerate(p.clientes) if c["tipo"] == "Exportador"))
            self.copiar(cur, "permiso_exportacion", ("codigo", "fecha_emision", "fecha_vencimiento", "id_cliente"),
                        ((pe["codigo"], pe["emision"], pe["vencimiento"], ids[pe["cliente"]]) for pe in p.permisos))

    def _documentos_pendientes(self, sql_presentes: str, plan_docs: list, clave: str) -> list:
        hechos = set(self.presentes(sql_presentes, [d[clave] for d in plan_docs]))
        return [d for d in plan_docs if d[clave] not in hechos]

    def fase_ingresos(self):
        p = self.plan
        pendientes = self._documentos_pendientes(
            f"SELECT cod_ingreso FROM {ESQUEMA}.ingreso WHERE cod_ingreso = ANY(%s::text[])", p.ingresos, "cod")
        bodegas, transp, vinos = self.mapa_bodegas(), self.mapa_transportistas(), self.mapa_vinos()
        hechos = len(p.ingresos) - len(pendientes)
        for bloque in trozos(pendientes, self.plan.perfil.lote_documentos):
            with self.conn.transaction(), self.conn.cursor() as cur:
                # Estado: DEFAULT 'en_confeccion' (el trigger RN-10 sólo admite ese estado al crear)
                self.copiar(cur, "ingreso", ("cod_ingreso", "fecha", "id_transportista", "id_bodega"),
                            ((i["cod"], i["fecha"], transp[p.transportistas[i["transportista"]]["cod"]],
                              bodegas[p.bodegas[i["bodega"]]["cuit"]]) for i in bloque))
                ids = self.mapa(f"SELECT id_ingreso, cod_ingreso FROM {ESQUEMA}.ingreso "
                                "WHERE cod_ingreso = ANY(%s::text[])", ([i["cod"] for i in bloque],))
                self.copiar(cur, "renglon_ingreso", ("id_ingreso", "id_vino", "cantidad_botellas"),
                            ((ids[i["cod"]], vinos[v], q) for i in bloque for v, q in i["renglones"]))
                orden = [ids[i["cod"]] for i in bloque]
                cur.execute(f"UPDATE {ESQUEMA}.ingreso SET estado = 'terminado' WHERE id_ingreso = ANY(%s::int[])",
                            (orden,))
                cur.executemany(f"CALL {ESQUEMA}.sp_procesar_ingreso(%s::integer)", [(x,) for x in orden])
            hechos += len(bloque)
            print(f"   ingresos procesados: {hechos}/{len(p.ingresos)}", flush=True)

    def fase_transferencias(self):
        p = self.plan
        pendientes = self._documentos_pendientes(
            f"SELECT num_solicitud FROM {ESQUEMA}.transferencia WHERE num_solicitud = ANY(%s::text[])",
            p.transferencias, "num")
        salas, vinos = self.mapa_salas(), self.mapa_vinos()
        hechos = len(p.transferencias) - len(pendientes)
        for bloque in trozos(pendientes, self.plan.perfil.lote_documentos):
            with self.conn.transaction(), self.conn.cursor() as cur:
                # fecha_confeccion la fija el trigger RN-11 (CURRENT_DATE); estado por DEFAULT
                self.copiar(cur, "transferencia", ("num_solicitud", "id_sala"),
                            ((t["num"], salas[t["sala"]]) for t in bloque))
                ids = self.mapa(f"SELECT id_transferencia, num_solicitud FROM {ESQUEMA}.transferencia "
                                "WHERE num_solicitud = ANY(%s::text[])", ([t["num"] for t in bloque],))
                self.copiar(cur, "renglon_transferencia", ("id_transferencia", "id_vino", "cantidad_botellas"),
                            ((ids[t["num"]], vinos[v], q) for t in bloque for v, q in t["renglones"]))
                orden = [ids[t["num"]] for t in bloque]
                cur.execute(f"UPDATE {ESQUEMA}.transferencia SET estado = 'terminado' "
                            "WHERE id_transferencia = ANY(%s::int[])", (orden,))
                cur.executemany(f"CALL {ESQUEMA}.sp_procesar_transferencia(%s::integer)", [(x,) for x in orden])
            hechos += len(bloque)
            print(f"   transferencias procesadas: {hechos}/{len(p.transferencias)}", flush=True)

    def _controlar_cronologia_lote(self, ids_sala: list[int], pares: list[tuple[int, int]]):
        """Antes de insertar un lote de comprobantes (dentro de su transacción) verifica
        que la venta de hoy respete la cronología y que las salas puedan vender hoy.
        Si algo falla se lanza ErrorCarga y se revierte sólo este lote."""
        hoy, isodow = self.filas("SELECT CURRENT_DATE, EXTRACT(ISODOW FROM CURRENT_DATE)::int")[0]
        if hoy <= FIN_HISTORIAL:
            raise ErrorCarga(f"CURRENT_DATE del servidor ({hoy}) no es posterior a {FIN_HISTORIAL}")
        pendientes_o_futuras = self.escalar(
            f"SELECT count(*) FROM {ESQUEMA}.transferencia "
            "WHERE estado <> 'procesado' OR fecha_confeccion > CURRENT_DATE")
        if pendientes_o_futuras:
            raise ErrorCarga(f"Hay {pendientes_o_futuras} transferencias sin procesar o con fecha posterior a hoy: "
                             "las ventas deben ser posteriores a las transferencias procesadas")
        cerradas = self.filas(
            f"SELECT id_sala, dia_cierre_semanal::text FROM {ESQUEMA}.sala_de_ventas "
            f"WHERE id_sala = ANY(%s::int[]) AND array_position(enum_range(NULL::{ESQUEMA}.dia_semana), "
            "dia_cierre_semanal) = %s", (ids_sala, isodow))
        if cerradas:
            raise ErrorCarga(f"Hoy ({hoy}) cierran {len(cerradas)} salas con ventas planificadas en este lote "
                             f"(p. ej. {cerradas[:3]}). El plan se generó para el día {self.plan.fecha_carga} "
                             "y el día cambió durante la carga. Los lotes anteriores quedaron completos; "
                             "ver 'Reanudación' en db/seed/README.md.")
        sin_abastecer = self.escalar(
            f"SELECT count(*) FROM unnest(%s::int[], %s::int[]) AS p(id_sala, id_vino) "
            f"WHERE NOT EXISTS (SELECT 1 FROM {ESQUEMA}.transferencia t "
            f"JOIN {ESQUEMA}.renglon_transferencia r ON r.id_transferencia = t.id_transferencia "
            "WHERE t.id_sala = p.id_sala AND r.id_vino = p.id_vino "
            "AND t.estado = 'procesado' AND t.fecha_confeccion <= CURRENT_DATE)",
            ([s for s, _v in pares], [v for _s, v in pares]))
        if sin_abastecer:
            raise ErrorCarga(f"{sin_abastecer} pares (sala, vino) del lote no tienen una transferencia procesada "
                             "con fecha anterior o igual a hoy")

    def fase_comprobantes(self):
        p = self.plan
        hechos_db = set(self.presentes(f"SELECT num_comprobante FROM {ESQUEMA}.comprobante "
                                       "WHERE num_comprobante = ANY(%s::text[])", [c[0] for c in p.comprobantes]))
        pendientes = [c for c in p.comprobantes if c[0] not in hechos_db]
        salas, vinos, clientes = self.mapa_salas(), self.mapa_vinos(), self.mapa_clientes()
        hechos, inicio = len(p.comprobantes) - len(pendientes), time.perf_counter()
        lotes_esta_ejecucion = 0
        for bloque in trozos(pendientes, self.plan.perfil.lote_comprobantes):
            with self.conn.transaction(), self.conn.cursor() as cur:
                # CURRENT_DATE es la fecha de inicio de ESTA transacción: es la misma que
                # pondrá el DEFAULT de comprobante.fecha a todo el lote.
                self._controlar_cronologia_lote(
                    sorted({salas[c[2]] for c in bloque}),
                    sorted({(salas[c[2]], vinos[v]) for c in bloque for v, _q in c[3]}))
                # fecha: DEFAULT CURRENT_DATE (no se envía). subtotal, descuento y total:
                # DEFAULT 0 y los recalcula trg_comprobante_totales.
                self.copiar(cur, "comprobante", ("num_comprobante", "id_cliente", "id_sala"),
                            ((c[0], clientes[c[1]], salas[c[2]]) for c in bloque))
                ids = self.mapa(f"SELECT id_comprobante, num_comprobante FROM {ESQUEMA}.comprobante "
                                "WHERE num_comprobante = ANY(%s::text[])", ([c[0] for c in bloque],))
                # precio, descuento y subtotal van en 0: trg_detalle_validar los reemplaza por el
                # precio vigente, el descuento del tipo de cliente y el subtotal (igual que los tests).
                # trg_detalle_actualizar descuenta el stock y recalcula el comprobante.
                self.copiar(cur, "detalle_comprobante", ("id_comprobante", "id_vino", "cantidad",
                                                         "precio_unitario_venta", "descuento_aplicado",
                                                         "subtotal_renglon"),
                            ((ids[c[0]], vinos[v], q, 0, 0, 0) for c in bloque for v, q in c[3]))
                lotes_esta_ejecucion += 1
                if self.interrumpir_en_lote == lotes_esta_ejecucion:
                    # Sólo perfil prueba (main lo valida): fallo DENTRO de la transacción,
                    # después de insertar cabeceras y renglones => debe revertirse el lote entero.
                    raise ErrorCarga(f"Interrupción simulada en el lote {lotes_esta_ejecucion} de comprobantes "
                                     f"({bloque[0][0]}..{bloque[-1][0]}): este lote se revierte")
            hechos += len(bloque)
            seg = time.perf_counter() - inicio
            print(f"   comprobantes: {num(hechos)}/{num(len(p.comprobantes))} ({num(seg)} s)", flush=True)

    def fase_precios(self):
        p = self.plan
        with self.conn.transaction(), self.conn.cursor() as cur:
            # Cambio de precio real: el trigger RN-13 inserta cada fila de auditoría.
            cur.executemany(f"UPDATE {ESQUEMA}.vino SET precio_venta = %s WHERE cod_vino = %s AND precio_venta = %s",
                            [(n, p.vinos[v]["cod"], a) for v, a, n in p.ajustes_precio])
            if self.conteo("auditoria_precio") != len(p.ajustes_precio):
                raise ErrorCarga("La auditoría de precios no registró todos los cambios (se revierte la fase)")

    # -- orquestación ------------------------------------------------------
    def revisar(self) -> list[tuple[Fase, str, str]]:
        estados = [(f, *self.estado_fase(f)) for f in self.fases]
        todas_completas = all(e in ("completa", "completa_extra") for _f, e, _d in estados)
        anterior_incompleta = None
        normalizados = []
        for fase, estado, detalle in estados:
            if estado == "completa_extra" and not todas_completas:
                # Filas de más con la carga sin terminar: podrían ser datos previos ajenos.
                raise ErrorCarga(f"La fase '{fase.clave}' tiene más filas que el plan ({detalle}) y la carga "
                                 "no está terminada. Puede haber datos ajenos a esta carga. No se modificó nada.")
            if estado == "completa_extra":
                estado, detalle = "completa", detalle + " (hay filas posteriores a la carga)"
            normalizados.append((fase, estado, detalle))
            if estado == "inconsistente":
                raise ErrorCarga(f"La fase '{fase.clave}' tiene datos que no coinciden con el plan ({detalle}). "
                                 "Puede haber datos previos ajenos a esta carga o una semilla distinta. "
                                 "No se modificó nada.")
            if anterior_incompleta and estado != "pendiente":
                raise ErrorCarga(f"La fase '{fase.clave}' tiene datos pero la fase anterior "
                                 f"'{anterior_incompleta}' no está completa. No se modificó nada.")
            if estado != "completa":
                anterior_incompleta = fase.clave
        return normalizados

    def cargar(self):
        for fase, estado, _detalle in self.revisar():
            if estado == "completa":
                print(f"== {fase.titulo}: ya completa, se saltea")
                continue
            print(f"== {fase.titulo}" + (" (se reanuda)" if estado == "en_curso" else ""), flush=True)
            inicio = time.perf_counter()
            fase.ejecutar()
            seg = time.perf_counter() - inicio
            self.tiempos.append((fase.clave, seg))
            nuevo, detalle = self.estado_fase(fase)
            if nuevo != "completa":
                raise ErrorCarga(f"La fase '{fase.clave}' terminó sin quedar completa ({detalle})")
            print(f"   OK en {num(seg, 1)} s ({detalle})", flush=True)
        print("== Actualizando estadísticas del planificador (ANALYZE)", flush=True)
        inicio = time.perf_counter()
        for t in TODAS_LAS_TABLAS:
            self.conn.execute(f"ANALYZE {ESQUEMA}.{t}")
        self.tiempos.append(("analyze", time.perf_counter() - inicio))


CONTROLES_VOLUMEN_TPI = (200, 201)   # en validaciones.sql: mínimos de volumen de la Etapa 3


def ejecutar_validaciones(conn, perfil: Perfil = PERFIL_DEFINITIVO) -> int:
    sql = ARCHIVO_VALIDACIONES.read_text(encoding="utf-8")
    with conn.cursor() as cur:
        cur.execute(sql)
        filas = cur.fetchall()
    fallas = 0
    print(f"\n{'Control':<92}{'Valor':>12}  Resultado")
    for orden, control, valor, resultado in filas:
        if resultado == "FALLA" and orden in CONTROLES_VOLUMEN_TPI and not perfil.exigir_volumen_tpi:
            resultado = f"INFO (perfil {perfil.nombre}: mínimo del TPI no aplica)"
        print(f"{control[:90]:<92}{valor:>12}  {resultado}")
        fallas += resultado == "FALLA"
    print(f"\nControles con FALLA: {fallas}")
    return fallas


# =====================================================================
# Programa principal
# =====================================================================
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Carga masiva de Bodegas del Atuel (Etapa 3)")
    ap.add_argument("--semilla", type=int, default=SEMILLA_POR_DEFECTO,
                    help=f"semilla del generador (por defecto {SEMILLA_POR_DEFECTO})")
    modo = ap.add_mutually_exclusive_group()
    modo.add_argument("--solo-plan", action="store_true", help="genera el plan y muestra las cantidades; no se conecta")
    modo.add_argument("--verificar", action="store_true", help="sólo ejecuta las consultas de control (lectura)")
    modo.add_argument("--confirmar", action="store_true", help="ejecuta (o reanuda) la carga")
    ap.add_argument("--fecha-carga", type=date.fromisoformat,
                    help="sólo con --solo-plan: fecha de carga simulada AAAA-MM-DD (por defecto hoy). "
                         "En la carga real la fecha es CURRENT_DATE del servidor")
    ap.add_argument("--perfil", choices=sorted(PERFILES), default=PERFIL_DEFINITIVO.nombre,
                    help="definitivo (por defecto: volúmenes del TPI) o prueba (volúmenes reducidos; "
                         "exige --env con un .env de prueba)")
    ap.add_argument("--env", type=Path, default=None,
                    help="archivo .env de conexión (definitivo: por defecto el de la raíz; "
                         "prueba: obligatorio y distinto del principal)")
    ap.add_argument("--reporte", type=Path, help="guarda tiempos y conteos en un JSON")
    ap.add_argument("--interrumpir-en-lote", type=int, metavar="N",
                    help="SÓLO perfil prueba: simula un fallo dentro del lote N de comprobantes de esta "
                         "ejecución (se revierte ese lote) para probar atomicidad y reanudación")
    args = ap.parse_args(argv)
    perfil = PERFILES[args.perfil]
    if args.fecha_carga and not args.solo_plan:
        ap.error("--fecha-carga sólo se usa con --solo-plan (en la carga real manda CURRENT_DATE del servidor)")
    if args.interrumpir_en_lote is not None and (perfil.nombre != "prueba" or not args.confirmar):
        ap.error("--interrumpir-en-lote sólo se admite con --perfil prueba --confirmar")
    if args.interrumpir_en_lote is not None and args.interrumpir_en_lote < 1:
        ap.error("--interrumpir-en-lote debe ser un número de lote >= 1")

    def generar_plan(fecha_carga: date) -> tuple[Plan, float]:
        print(f"Generando el plan (perfil {perfil.nombre}, semilla {args.semilla}, fecha de carga {fecha_carga})...",
              flush=True)
        t0 = time.perf_counter()
        plan_ = GeneradorPlan(args.semilla, leer_catalogos(), fecha_carga, perfil).generar()
        controlar_requisitos_volumen(plan_)
        controlar_stock_plan(plan_)
        t = time.perf_counter() - t0
        print("\n".join(resumen_plan(plan_)))
        print(f"Plan generado en {num(t, 1)} s")
        return plan_, t

    def abrir_conexion():
        params = parametros_destino(perfil, args.env)
        print(f"Perfil: {perfil.nombre} | Base destino: {destino_texto(params)}", flush=True)
        conn_ = conectar(params)
        base_real = conn_.execute("SELECT current_database()").fetchone()[0]
        if base_real != params["dbname"]:
            conn_.close()
            raise ErrorCarga(f"Se esperaba la base {params['dbname']} y la conexión abrió {base_real}")
        return conn_

    try:
        if args.verificar:
            conn = abrir_conexion()
            with conn:
                return SALIDA_CONTROLES_FALLIDOS if ejecutar_validaciones(conn, perfil) else SALIDA_OK

        if args.solo_plan:
            generar_plan(args.fecha_carga or date.today())
            return SALIDA_OK

        conn = abrir_conexion()
        with conn:
            if not conn.execute("SELECT pg_try_advisory_lock(%s)", (CLAVE_BLOQUEO,)).fetchone()[0]:
                raise ErrorCarga("Hay otra carga en curso sobre esta base (bloqueo consultivo tomado)")
            cargador = Cargador(conn)
            cargador.interrumpir_en_lote = args.interrumpir_en_lote
            cargador.verificar_esquema()            # antes de leer cualquier tabla
            # Día de carga D: el de los comprobantes ya cargados (si una carga anterior los
            # empezó) para regenerar el MISMO plan; si no hay, CURRENT_DATE del servidor.
            hoy, primera_venta = conn.execute(
                f"SELECT CURRENT_DATE, (SELECT MIN(fecha) FROM {ESQUEMA}.comprobante)").fetchone()
            fecha_carga = primera_venta or hoy
            if primera_venta and primera_venta != hoy:
                print(f"Aviso: los comprobantes existentes son del {primera_venta}; se regenera el plan "
                      f"para ese día (hoy es {hoy}).")
            plan, t_plan = generar_plan(fecha_carga)
            cargador.usar_plan(plan)
            estados = cargador.revisar()
            print("\nEstado de las fases:")
            for fase, estado, detalle in estados:
                print(f"  {fase.clave:<15}{estado:<12}{detalle}")
            if all(e == "completa" for _f, e, _d in estados):
                print("\nLa carga con esta semilla ya está completa. No se modificó nada.")
                return SALIDA_CONTROLES_FALLIDOS if ejecutar_validaciones(conn, perfil) else SALIDA_OK
            if not args.confirmar:
                print("\nModo revisión: no se escribió nada. Use --confirmar para ejecutar la carga.")
                return SALIDA_OK
            inicio = time.perf_counter()
            cargador.cargar()
            total = time.perf_counter() - inicio
            print(f"\nCarga terminada en {num(total, 1)} s")
            fallas = ejecutar_validaciones(conn, perfil)
            if args.reporte:
                conteos = {t: cargador.conteo(t) for t in TODAS_LAS_TABLAS}
                args.reporte.write_text(json.dumps({
                    "fecha": datetime.now().isoformat(timespec="seconds"), "semilla": args.semilla,
                    "segundos_plan": round(t_plan, 1), "segundos_carga": round(total, 1),
                    "segundos_por_fase": {k: round(v, 1) for k, v in cargador.tiempos},
                    "perfil": perfil.nombre, "fecha_carga_plan": plan.fecha_carga.isoformat(),
                    "locale_faker": plan.locale_faker,
                    "python": sys.version.split()[0],
                    "conteos": conteos, "controles_con_falla": fallas}, indent=2, ensure_ascii=False),
                    encoding="utf-8")
                print(f"Reporte guardado en {args.reporte}")
            return SALIDA_CONTROLES_FALLIDOS if fallas else SALIDA_OK
    except ErrorCarga as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        return SALIDA_ERROR_CONTROLADO
    except Exception as exc:
        if not type(exc).__module__.startswith("psycopg"):
            raise
        # Error de PostgreSQL (p. ej. un trigger rechazó un renglón): la transacción en
        # curso (el lote o la fase) ya se revirtió; lo confirmado antes queda intacto.
        diag = getattr(exc, "diag", None)
        print(f"\nERROR de PostgreSQL [{getattr(exc, 'sqlstate', None) or '-'}]: "
              f"{getattr(diag, 'message_primary', None) or exc}", file=sys.stderr)
        if getattr(diag, "context", None):
            print(f"Contexto: {diag.context}", file=sys.stderr)
        print("La transacción en curso se revirtió. Corrija la causa y vuelva a ejecutar: la carga se "
              "reanuda desde el último lote confirmado (ver db/seed/README.md).", file=sys.stderr)
        return SALIDA_ERROR_POSTGRES


if __name__ == "__main__":
    sys.exit(main())
