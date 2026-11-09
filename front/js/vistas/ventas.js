// Pantalla principal de ventas (#/ventas): consulta de un comprobante por su
// número y acceso al registro de una venta nueva.
// La API no ofrece un listado de comprobantes; se muestran además las ventas
// registradas desde este navegador (localStorage), avisando que no es el listado
// completo de la base.
import { encabezadoPagina, tabla, tarjeta } from "../componentes/contenido.js";
import { vacio } from "../componentes/estados.js";
import { campoValidable } from "../componentes/formulario.js";
import { h, icono } from "../dom.js";
import { formatoPrecio } from "./vinos-comun.js";
import { formatoFecha, hashVenta, olvidarVentas, ventasRecordadas } from "./ventas-comun.js";

function consulta() {
  const nro = campoValidable({
    etiqueta: "Número de comprobante",
    control: h("input", {
      class: "campo__control", type: "search", maxlength: 20, autocomplete: "off",
      placeholder: "Ej.: C-00000001", name: "nro",
    }),
  });
  const formulario = h("form", { class: "busqueda", role: "search", "aria-label": "Consultar un comprobante", novalidate: true },
    nro.el,
    h("button", { class: "boton", type: "submit" }, icono("buscar"), "Consultar"));

  formulario.addEventListener("submit", (evento) => {
    evento.preventDefault();
    const valor = nro.control.value.trim();
    if (!valor) {
      nro.error("Ingresá el número de comprobante.");
      nro.control.focus();
      return;
    }
    nro.error("");
    location.hash = hashVenta(valor);
  });

  const { tarjeta: el, cuerpo } = tarjeta({
    titulo: "Consultar una venta",
    subtitulo: "Buscá un comprobante por su número exacto para ver su detalle.",
  });
  cuerpo.append(h("div", { class: "seccion" }, formulario));
  return el;
}

function recientes() {
  const { tarjeta: el, cuerpo } = tarjeta({
    titulo: "Registradas desde este navegador",
    subtitulo: "La API no ofrece un listado de ventas: acá se ven solo las registradas desde este navegador, con los datos que devolvió la API.",
  });

  function pintar() {
    const ventas = ventasRecordadas();
    if (!ventas.length) {
      cuerpo.replaceChildren(vacio("Todavía no registraste ventas desde este navegador."));
      return;
    }
    cuerpo.replaceChildren(
      tabla({
        descripcion: "Ventas registradas desde este navegador",
        filas: ventas,
        columnas: [
          { titulo: "Comprobante", valor: (v) => h("a", { href: hashVenta(v.num_comprobante) }, v.num_comprobante), clase: "mono" },
          { titulo: "Fecha", valor: (v) => formatoFecha(v.fecha) },
          { titulo: "Cliente", valor: (v) => v.cliente },
          { titulo: "Total", valor: (v) => formatoPrecio(v.total), clase: "num" },
        ],
      }),
      h("div", { class: "seccion seccion--pie" },
        h("button", {
          class: "enlace", type: "button",
          onClick: () => { olvidarVentas(); pintar(); },
        }, "Quitar esta lista del navegador (no borra ventas)")));
  }
  pintar();
  return el;
}

export function vistaVentas(contenedor) {
  contenedor.replaceChildren(
    encabezadoPagina({
      titulo: "Ventas",
      descripcion: "Registrá ventas y consultá comprobantes. Precios, descuentos, totales y stock los calcula la base de datos.",
      acciones: h("a", { class: "boton", href: "#/ventas/nueva" }, icono("mas"), "Nueva venta"),
    }),
    h("div", { class: "rejilla" }, consulta(), recientes()));
}
