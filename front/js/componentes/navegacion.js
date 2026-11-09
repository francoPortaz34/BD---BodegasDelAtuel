// Menú de navegación entre las secciones principales.
import { h, icono } from "../dom.js";

export function crearNavegacion(contenedor, rutas) {
  const enlaces = new Map();
  const lista = h("ul", { class: "menu" },
    rutas.filter((r) => r.menu).map((r) => {
      const enlace = h("a", { class: "menu__enlace", href: `#${r.ruta}` },
        icono(r.icono), h("span", {}, r.menu),
        r.subetapa && h("span", { class: "menu__marca", title: `Se implementa en la subetapa ${r.subetapa}` }, "Próx."));
      enlaces.set(r.ruta, enlace);
      return h("li", {}, enlace);
    }));
  contenedor.replaceChildren(lista);

  /** Marca como activa la sección de la ruta (o su sección padre, p. ej. /vinos/V0001). */
  function marcarActiva(ruta) {
    for (const [destino, enlace] of enlaces) {
      const activa = destino === "/" ? ruta === "/" : ruta === destino || ruta.startsWith(`${destino}/`);
      if (activa) enlace.setAttribute("aria-current", "page");
      else enlace.removeAttribute("aria-current");
    }
  }
  return { marcarActiva };
}
