// Pantalla de catálogos: salas, bodegas, cepas y maridajes, cada uno con sus
// propios estados de carga, error y vacío (si uno falla, los demás se ven igual).
import { obtenerBodegas, obtenerCepas, obtenerMaridajes, obtenerSalas } from "../api/catalogos.js";
import { encabezadoPagina, etiqueta, tabla, tarjeta } from "../componentes/contenido.js";
import { cargarEn } from "../componentes/estados.js";
import { h, icono } from "../dom.js";

const numero = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 1 });

// Solo formato de presentación (no se calcula nada)
const direccion = (f) => [f.calle, f.numero].filter(Boolean).join(" ") || null;
const cuit = (c) => (/^\d{11}$/.test(c ?? "") ? `${c.slice(0, 2)}-${c.slice(2, 10)}-${c.slice(10)}` : c);
const capital = (t) => (t ? t.charAt(0).toUpperCase() + t.slice(1) : null);

const CATALOGOS = [
  {
    titulo: "Salas de venta",
    obtener: obtenerSalas,
    vacio: "No hay salas de venta registradas.",
    columnas: [
      { titulo: "N°", valor: (f) => f.id_sala, clase: "num" },
      { titulo: "Dirección", valor: direccion },
      { titulo: "Localidad", valor: (f) => f.localidad },
      { titulo: "Provincia", valor: (f) => f.provincia },
      { titulo: "Cierre semanal", valor: (f) => capital(f.dia_cierre_semanal) },
    ],
  },
  {
    titulo: "Bodegas",
    obtener: obtenerBodegas,
    vacio: "No hay bodegas registradas.",
    columnas: [
      { titulo: "Razón social", valor: (f) => f.razon_social },
      { titulo: "CUIT", valor: (f) => cuit(f.cuit), clase: "mono" },
      { titulo: "Dirección", valor: direccion },
    ],
  },
  {
    titulo: "Cepas",
    obtener: obtenerCepas,
    vacio: "No hay cepas registradas.",
    columnas: [
      { titulo: "Nombre", valor: (f) => f.nombre },
      { titulo: "Tipo", valor: (f) => (f.tipo ? etiqueta(capital(f.tipo), f.tipo) : null) },
    ],
  },
  {
    titulo: "Maridajes",
    obtener: obtenerMaridajes,
    vacio: "No hay maridajes registrados.",
    columnas: [
      { titulo: "Nombre", valor: (f) => f.nombre },
      {
        titulo: "Temperatura sugerida",
        valor: (f) => (f.temperatura_sugerida == null ? null : `${numero.format(f.temperatura_sugerida)} °C`),
        clase: "num",
      },
    ],
  },
];

function bloqueCatalogo(catalogo, signal) {
  const contador = h("span", { class: "tarjeta__contador" });
  const actualizar = h("button", {
    class: "boton boton--icono", type: "button",
    title: `Volver a consultar ${catalogo.titulo.toLowerCase()}`,
    "aria-label": `Volver a consultar ${catalogo.titulo.toLowerCase()}`,
  }, icono("reintentar"));

  const { tarjeta: el, cuerpo } = tarjeta({ titulo: catalogo.titulo, acciones: [contador, actualizar] });

  const cargar = (forzar = false) => {
    contador.textContent = "";
    return cargarEn(cuerpo, {
      signal,
      textoCarga: `Cargando ${catalogo.titulo.toLowerCase()}…`,
      textoVacio: catalogo.vacio,
      cargar: async () => {
        const datos = await catalogo.obtener({ forzar });
        if (!signal.aborted) contador.textContent = `${datos.length} registros`;
        return datos;
      },
      mostrar: (filas) => tabla({ columnas: catalogo.columnas, filas, descripcion: catalogo.titulo }),
    });
  };

  actualizar.addEventListener("click", () => cargar(true));
  cargar();
  return el;
}

export function vistaCatalogos(contenedor, { signal }) {
  contenedor.replaceChildren(
    encabezadoPagina({
      titulo: "Catálogos",
      descripcion: "Datos de referencia que usan el catálogo de vinos, las ventas, las transferencias y el tablero.",
    }),
    h("div", { class: "rejilla" }, CATALOGOS.map((c) => bloqueCatalogo(c, signal))));
}
