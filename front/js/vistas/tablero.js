// Tablero (#/tablero): los reportes de GET /reportes/*. Cada bloque tiene sus
// propios estados de carga, error (con reintento) y sin datos. Todas las cifras
// (botellas, montos, cantidades, stock) vienen calculadas por la base: acá solo
// se les da formato.
import { obtenerSalas } from "../api/catalogos.js";
import { ApiError } from "../api/cliente.js";
import {
  obtenerTopVinos, obtenerTransportistaActivo, obtenerTrazabilidad, obtenerVentasPorSala, obtenerVinosSinStock,
} from "../api/reportes.js";
import { encabezadoPagina, tabla, tarjeta } from "../componentes/contenido.js";
import { cargarEn, mensajeError, vacio } from "../componentes/estados.js";
import { campoValidable } from "../componentes/formulario.js";
import { h, icono } from "../dom.js";
import { etiquetaTipo, formatoDecimal, formatoPrecio, hashDetalle } from "./vinos-comun.js";
import { formatoFecha, textoSala } from "./ventas-comun.js";
import { etiquetaEstado, hashTransferencia } from "./transferencias-comun.js";

const numero = (v) => formatoDecimal(v);
const enlaceVino = (cod) => (cod ? h("a", { href: hashDetalle(cod, {}) }, cod) : null);
const esLista = (d) => {
  if (!Array.isArray(d)) throw new ApiError("La API devolvió el reporte con un formato inesperado.", { tipo: "formato" });
  return d;
};

/** Botón de actualizar (mismo patrón que la pantalla de catálogos). */
function botonActualizar(titulo, alHacerClic) {
  return h("button", {
    class: "boton boton--icono", type: "button", title: `Volver a consultar: ${titulo}`, "aria-label": `Volver a consultar: ${titulo}`,
    onClick: alHacerClic,
  }, icono("reintentar"));
}

/** Reporte sin parámetros: se consulta al abrir el tablero. */
function bloqueFijo({ titulo, subtitulo, obtener, columnas, textoVacio, clase, signal }) {
  const contador = h("span", { class: "tarjeta__contador" });
  const consultar = () => {
    contador.textContent = "";
    return cargarEn(cuerpo, {
      signal,
      textoCarga: `Consultando ${titulo.toLowerCase()}…`,
      textoVacio,
      cargar: async () => {
        const filas = esLista(await obtener({ signal }));
        if (!signal.aborted) contador.textContent = `${filas.length} ${filas.length === 1 ? "fila" : "filas"}`;
        return filas;
      },
      mostrar: (filas) => tabla({ columnas, filas, descripcion: titulo }),
    });
  };
  const { tarjeta: el, cuerpo } = tarjeta({ titulo, subtitulo, clase, acciones: [contador, botonActualizar(titulo, consultar)] });
  consultar();
  return el;
}

function bloqueSinStock(signal) {
  const titulo = "Vinos sin stock en una sala";
  const sala = campoValidable({
    etiqueta: "Sala",
    control: h("select", { class: "campo__control", disabled: true }, h("option", { value: "" }, "Cargando salas…")),
  });
  const resultado = h("div", { class: "reporte__resultado" });
  const contador = h("span", { class: "tarjeta__contador" });

  const consultar = () => {
    contador.textContent = "";
    if (!sala.control.value) {
      resultado.replaceChildren(vacio("Elegí una sala para ver qué vinos le faltan."));
      return;
    }
    cargarEn(resultado, {
      signal,
      textoCarga: "Consultando…",
      textoVacio: "Esta sala no tiene vinos faltantes que haya en el depósito central.",
      cargar: async () => {
        const filas = esLista(await obtenerVinosSinStock(Number(sala.control.value), { signal }));
        if (!signal.aborted) contador.textContent = `${filas.length} ${filas.length === 1 ? "vino" : "vinos"}`;
        return filas;
      },
      mostrar: (filas) => tabla({
        descripcion: titulo,
        filas,
        columnas: [
          { titulo: "Código", valor: (f) => enlaceVino(f.cod_vino), clase: "mono" },
          { titulo: "Vino", valor: (f) => f.nombre_comercial },
          { titulo: "Stock en depósito", valor: (f) => numero(f.stock_deposito), clase: "num" },
        ],
      }),
    });
  };

  const cargarSalas = (forzar = false) => {
    obtenerSalas({ forzar }).then((salas) => {
      if (signal.aborted) return;
      sala.control.replaceChildren(h("option", { value: "" }, "Elegí la sala"),
        ...esLista(salas).map((s) => h("option", { value: String(s.id_sala) }, textoSala(s))));
      sala.control.disabled = false;
      sala.error("");
      resultado.replaceChildren(vacio("Elegí una sala para ver qué vinos le faltan."));
    }).catch((error) => {
      if (signal.aborted) return;
      sala.control.replaceChildren(h("option", { value: "" }, "Salas no disponibles"));
      resultado.replaceChildren(mensajeError(error, { onReintentar: () => cargarSalas(true) }));
    });
  };

  sala.control.addEventListener("change", consultar);
  const { tarjeta: el, cuerpo } = tarjeta({
    titulo,
    subtitulo: "Vinos que la sala no tiene pero el depósito central sí: candidatos para una transferencia.",
    acciones: [contador, botonActualizar(titulo, consultar)],
  });
  cuerpo.append(h("div", { class: "seccion" }, sala.el), resultado);
  cargarSalas();
  return el;
}

function bloqueTrazabilidad(signal) {
  const titulo = "Trazabilidad de un vino";
  const cod = campoValidable({
    etiqueta: "Código del vino",
    control: h("input", { class: "campo__control", type: "search", autocomplete: "off", placeholder: "Ej.: V0401", maxlength: 20 }),
  });
  const resultado = h("div", { class: "reporte__resultado" }, vacio("Ingresá un código para ver el recorrido del vino."));
  const formulario = h("form", { class: "busqueda", novalidate: true, role: "search", "aria-label": titulo },
    cod.el, h("button", { class: "boton", type: "submit" }, icono("buscar"), "Consultar"));

  const subtabla = (subtitulo, filas, columnas, textoVacio) => h("section", { class: "subreporte" },
    h("h3", { class: "subreporte__titulo" }, subtitulo),
    Array.isArray(filas) && filas.length ? tabla({ columnas, filas, descripcion: subtitulo }) : vacio(textoVacio));

  const consultar = (valor) => cargarEn(resultado, {
    signal,
    textoCarga: "Consultando el recorrido…",
    esVacio: () => false,
    cargar: async () => {
      const d = await obtenerTrazabilidad(valor, { signal });
      if (!d || typeof d !== "object" || !d.vino) throw new ApiError("La API devolvió el reporte con un formato inesperado.", { tipo: "formato" });
      return d;
    },
    mostrar: (d) => h("div", {},
      h("div", { class: "seccion trazabilidad__vino" },
        enlaceVino(d.vino.cod_vino), " · ", h("strong", {}, d.vino.nombre_comercial ?? ""), " ",
        etiquetaTipo(d.vino.tipo), " ",
        h("span", { class: "seccion__ayuda" }, [d.vino.anada, d.vino.presentacion_ml && `${d.vino.presentacion_ml} ml`, d.vino.bodega].filter(Boolean).join(" · "))),
      subtabla("Ingresos al depósito", d.ingresos, [
        { titulo: "Ingreso", valor: (f) => f.cod_ingreso, clase: "mono" },
        { titulo: "Fecha", valor: (f) => formatoFecha(f.fecha) },
        { titulo: "Estado", valor: (f) => etiquetaEstado(f.estado) },
        { titulo: "Transportista", valor: (f) => f.transportista },
        { titulo: "Botellas", valor: (f) => numero(f.botellas), clase: "num" },
      ], "Sin ingresos registrados."),
      subtabla("Transferencias a salas", d.transferencias, [
        { titulo: "Solicitud", valor: (f) => h("a", { href: hashTransferencia(f.num_solicitud) }, f.num_solicitud), clase: "mono" },
        { titulo: "Fecha", valor: (f) => formatoFecha(f.fecha_confeccion) },
        { titulo: "Estado", valor: (f) => etiquetaEstado(f.estado) },
        { titulo: "Sala", valor: (f) => [`N° ${f.id_sala}`, f.localidad].filter(Boolean).join(" · ") },
        { titulo: "Botellas", valor: (f) => numero(f.botellas), clase: "num" },
      ], "Sin transferencias registradas."),
      subtabla("Ventas por sala", d.ventas_por_sala, [
        { titulo: "Sala", valor: (f) => [`N° ${f.id_sala}`, f.localidad].filter(Boolean).join(" · ") },
        { titulo: "Comprobantes", valor: (f) => numero(f.comprobantes), clase: "num" },
        { titulo: "Botellas", valor: (f) => numero(f.botellas), clase: "num" },
      ], "Sin ventas registradas.")),
  });

  formulario.addEventListener("submit", (e) => {
    e.preventDefault();
    const valor = cod.control.value.trim();
    if (!valor) { cod.error("Ingresá el código del vino."); cod.control.focus(); return; }
    cod.error("");
    consultar(valor);
  });

  const { tarjeta: el, cuerpo } = tarjeta({
    titulo, clase: "tarjeta--ancha",
    subtitulo: "Recorrido de un vino por la red: ingresos al depósito, transferencias a salas y ventas.",
  });
  cuerpo.append(h("div", { class: "seccion" }, formulario), resultado);
  return el;
}

export function vistaTablero(contenedor, { signal }) {
  contenedor.replaceChildren(
    encabezadoPagina({
      titulo: "Tablero",
      descripcion: "Reportes calculados por la base de datos. Cada bloque se puede volver a consultar por separado.",
    }),
    h("div", { class: "rejilla" },
      bloqueFijo({
        titulo: "Vinos más vendidos", subtitulo: "Los 10 vinos con más botellas vendidas en toda la red.",
        obtener: obtenerTopVinos, textoVacio: "Todavía no hay ventas registradas.", signal, clase: "tarjeta--ancha",
        columnas: [
          { titulo: "Código", valor: (f) => enlaceVino(f.cod_vino), clase: "mono" },
          { titulo: "Vino", valor: (f) => f.nombre_comercial },
          { titulo: "Añada", valor: (f) => f.anada, clase: "num" },
          { titulo: "Presentación", valor: (f) => formatoDecimal(f.presentacion_ml, " ml"), clase: "num" },
          { titulo: "Botellas vendidas", valor: (f) => numero(f.botellas_vendidas), clase: "num" },
        ],
      }),
      bloqueFijo({
        titulo: "Ventas por sala", subtitulo: "Monto vendido por sala en el último trimestre (con descuentos).",
        obtener: obtenerVentasPorSala, textoVacio: "No hubo ventas en el último trimestre.", signal,
        columnas: [
          { titulo: "Sala", valor: (f) => `N° ${f.id_sala}`, clase: "num" },
          { titulo: "Localidad", valor: (f) => f.localidad },
          { titulo: "Monto vendido", valor: (f) => formatoPrecio(f.monto_total), clase: "num" },
        ],
      }),
      bloqueFijo({
        titulo: "Transportista más activo", subtitulo: "Con más ingresos al depósito en el último mes (todos, si hay empate).",
        obtener: obtenerTransportistaActivo, textoVacio: "No hubo ingresos en el último mes.", signal,
        columnas: [
          { titulo: "Código", valor: (f) => f.cod_transporte, clase: "mono" },
          { titulo: "Razón social", valor: (f) => f.razon_social },
          { titulo: "Ingresos", valor: (f) => numero(f.ingresos), clase: "num" },
        ],
      }),
      bloqueSinStock(signal),
      bloqueTrazabilidad(signal)));
}
