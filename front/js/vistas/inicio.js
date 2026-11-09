// Pantalla de inicio: accesos a las secciones y resumen de los catálogos.
import { obtenerBodegas, obtenerCepas, obtenerMaridajes, obtenerSalas } from "../api/catalogos.js";
import { encabezadoPagina } from "../componentes/contenido.js";
import { h, icono } from "../dom.js";
import { rutas } from "../rutas.js";

const RESUMEN = [
  { titulo: "Salas de venta", obtener: obtenerSalas },
  { titulo: "Bodegas", obtener: obtenerBodegas },
  { titulo: "Cepas", obtener: obtenerCepas },
  { titulo: "Maridajes", obtener: obtenerMaridajes },
];

function indicador({ titulo, obtener }, signal) {
  const valor = h("span", { class: "indicador__valor indicador__valor--cargando" }, "…");
  obtener()
    .then((datos) => {
      if (signal.aborted) return;
      valor.className = "indicador__valor";
      valor.textContent = String(datos.length);
    })
    .catch(() => {
      if (signal.aborted) return;
      valor.className = "indicador__valor indicador__valor--error";
      valor.textContent = "—";
      valor.title = "No se pudo consultar";
    });
  return h("a", { class: "indicador", href: "#/catalogos" },
    valor, h("span", { class: "indicador__titulo" }, titulo));
}

export function vistaInicio(contenedor, { signal }) {
  const secciones = rutas.filter((r) => r.menu && r.ruta !== "/");

  contenedor.replaceChildren(
    encabezadoPagina({
      titulo: "Bienvenido",
      descripcion: "Gestión de vinos, ventas y transferencias entre el depósito central y las salas de venta.",
    }),
    h("div", { class: "indicadores", "aria-label": "Catálogos registrados" },
      RESUMEN.map((r) => indicador(r, signal))),
    h("h2", { class: "subtitulo" }, "Secciones"),
    h("div", { class: "accesos" },
      secciones.map((r) => h("a", { class: "acceso", href: `#${r.ruta}` },
        icono(r.icono, "acceso__icono"),
        h("span", { class: "acceso__titulo" }, r.titulo,
          r.subetapa && h("span", { class: "menu__marca" }, "Próx.")),
        h("span", { class: "acceso__texto" }, r.descripcion)))));
}
