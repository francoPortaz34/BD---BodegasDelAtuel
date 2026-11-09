// Bloques de contenido reutilizables: encabezado de página, tarjeta y tabla.
import { h } from "../dom.js";

/** Encabezado de la pantalla con título, descripción y acciones opcionales. */
export function encabezadoPagina({ titulo, descripcion, acciones } = {}) {
  return h("div", { class: "pagina__encabezado" },
    h("div", {},
      h("h1", { class: "pagina__titulo" }, titulo),
      descripcion && h("p", { class: "pagina__descripcion" }, descripcion)),
    acciones && h("div", { class: "pagina__acciones" }, acciones));
}

/** Tarjeta con título y cuerpo; devuelve { tarjeta, cuerpo } para cargar datos en el cuerpo. */
export function tarjeta({ titulo, subtitulo, acciones, clase = "" } = {}) {
  const cuerpo = h("div", { class: "tarjeta__cuerpo" });
  const el = h("section", { class: `tarjeta ${clase}`.trim() },
    (titulo || acciones) && h("header", { class: "tarjeta__encabezado" },
      h("div", {},
        titulo && h("h2", { class: "tarjeta__titulo" }, titulo),
        subtitulo && h("p", { class: "tarjeta__subtitulo" }, subtitulo)),
      acciones && h("div", { class: "tarjeta__acciones" }, acciones)),
    cuerpo);
  return { tarjeta: el, cuerpo };
}

/**
 * Tabla genérica.
 * columnas: [{ titulo, valor: (fila) => texto | Node, clase? }]
 */
export function tabla({ columnas, filas, descripcion }) {
  return h("div", { class: "tabla-contenedor" },
    h("table", { class: "tabla" },
      descripcion && h("caption", { class: "visualmente-oculto" }, descripcion),
      h("thead", {}, h("tr", {}, columnas.map((c) => h("th", { scope: "col", class: c.clase }, c.titulo)))),
      h("tbody", {}, filas.map((fila) =>
        h("tr", {}, columnas.map((c) => h("td", { class: c.clase }, c.valor(fila) ?? "—")))))));
}

/** Etiqueta pequeña (por ejemplo el tipo de cepa). */
export function etiqueta(texto, variante = "") {
  return h("span", { class: `etiqueta ${variante ? `etiqueta--${variante}` : ""}`.trim() }, texto);
}
