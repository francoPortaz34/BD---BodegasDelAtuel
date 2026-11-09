// Pantallas provisorias: secciones de subetapas futuras y ruta inexistente.
import { encabezadoPagina } from "../componentes/contenido.js";
import { h, icono } from "../dom.js";

export function vistaPendiente(ruta) {
  return (contenedor) => {
    contenedor.replaceChildren(
      encabezadoPagina({ titulo: ruta.titulo, descripcion: ruta.descripcion }),
      h("div", { class: "estado estado--pendiente" },
        icono("reloj", "estado__icono"),
        h("div", { class: "estado__cuerpo" },
          h("p", { class: "estado__titulo" }, "Sección en desarrollo"),
          h("p", { class: "estado__texto" }, `Esta pantalla se implementa en la subetapa ${ruta.subetapa} de la Etapa 7.`))));
  };
}

export function vistaNoEncontrada(contenedor) {
  contenedor.replaceChildren(
    encabezadoPagina({ titulo: "Página no encontrada", descripcion: "La dirección no corresponde a ninguna sección." }),
    h("a", { class: "boton", href: "#/" }, "Volver al inicio"));
}
