// Detalle de un vino (#/vinos/:cod): ficha, composición de cepas y maridajes
// tal como los devuelve GET /vinos/{cod}. La dirección trae la búsqueda del
// catálogo (?tipo=...&pagina=...) para volver exactamente a ella.
import { obtenerVino } from "../api/vinos.js";
import { tomarAviso } from "../componentes/avisos.js";
import { encabezadoPagina, tabla, tarjeta } from "../componentes/contenido.js";
import { cargando, mensajeError, vacio } from "../componentes/estados.js";
import { h, icono } from "../dom.js";
import { etiquetaTipo, formatoDecimal, formatoPrecio, hashCatalogo, hashEdicion, leerBusqueda } from "./vinos-comun.js";

function ficha(vino) {
  const dato = (nombre, valor, clase) => [
    h("dt", {}, nombre),
    h("dd", { class: clase }, valor ?? "—"),
  ];
  return h("dl", { class: "ficha" },
    dato("Código", vino.cod_vino, "mono"),
    dato("Nombre comercial", vino.nombre_comercial),
    dato("Tipo", etiquetaTipo(vino.tipo)),
    dato("Añada", vino.anada),
    dato("Presentación", formatoDecimal(vino.presentacion_ml, " ml")),
    dato("Graduación alcohólica", formatoDecimal(vino.graduacion_alcoholica, " %")),
    dato("Precio de venta", formatoPrecio(vino.precio_venta)),
    dato("Bodega", vino.bodega));
}

function bloque(titulo, filas, textoVacio, columnas) {
  const { tarjeta: el, cuerpo } = tarjeta({ titulo });
  const lista = Array.isArray(filas) ? filas : [];
  // Sin asociaciones: se informa, no se completa con datos inventados
  cuerpo.append(lista.length ? tabla({ columnas, filas: lista, descripcion: titulo }) : vacio(textoVacio));
  return el;
}

export function vistaDetalleVino(contenedor, { params, consulta, signal }) {
  const cod = params.cod;
  const volver = () => h("a", { class: "boton boton--secundario", href: hashCatalogo(leerBusqueda(consulta)) },
    icono("anterior"), "Volver al catálogo");

  // "Editar" solo aparece cuando el vino se cargó (no tiene sentido con un 404)
  const editar = () => h("a", { class: "boton", href: hashEdicion(cod, leerBusqueda(consulta)) },
    icono("editar"), "Editar");
  const encabezado = (titulo, descripcion, conEditar = false) =>
    encabezadoPagina({ titulo, descripcion, acciones: [volver(), conEditar && editar()] });
  let cabecera = encabezado("Detalle del vino", `Código ${cod}`);
  const cuerpo = h("div", { class: "detalle" });
  // Aviso que deja el alta o la edición al guardar ("Cambios guardados…")
  const avisoGuardado = tomarAviso();
  contenedor.replaceChildren(...[cabecera, avisoGuardado, cuerpo].filter(Boolean));

  async function cargar() {
    cuerpo.replaceChildren(cargando("Cargando el vino…"));
    let vino;
    try {
      vino = await obtenerVino(cod, { signal });
    } catch (error) {
      if (signal.aborted || error?.name === "AbortError") return;
      // 404: el mensaje de la API ("Vino no encontrado") se muestra tal cual y no
      // tiene sentido reintentar. Otros errores (red, 5xx) permiten reintentar.
      const noExiste = error?.estado === 404;
      cuerpo.replaceChildren(mensajeError(error, { onReintentar: noExiste ? null : cargar }));
      if (noExiste) cuerpo.append(h("p", { class: "detalle__nota" }, `No hay un vino registrado con el código «${cod}».`));
      return;
    }
    if (signal.aborted) return;

    document.title = `${vino.nombre_comercial ?? cod} · Bodegas del Atuel`;
    const nueva = encabezado(vino.nombre_comercial ?? "Detalle del vino",
      [vino.cod_vino, vino.bodega].filter(Boolean).join(" · "), true);
    cabecera.replaceWith(nueva);
    cabecera = nueva;

    const { tarjeta: general, cuerpo: cuerpoGeneral } = tarjeta({ titulo: "Información general", clase: "tarjeta--ancha" });
    cuerpoGeneral.append(ficha(vino));

    cuerpo.replaceChildren(h("div", { class: "rejilla" },
      general,
      bloque("Composición de cepas", vino.cepas, "Sin cepas registradas.", [
        { titulo: "Cepa", valor: (c) => c.nombre },
        // Porcentaje tal como lo guarda la base (no se recalcula)
        { titulo: "Porcentaje de corte", valor: (c) => formatoDecimal(c.porcentaje_corte, " %"), clase: "num" },
      ]),
      bloque("Maridajes", vino.maridajes, "Sin maridajes registrados.", [
        { titulo: "Maridaje", valor: (m) => m.nombre },
        { titulo: "Temperatura sugerida", valor: (m) => formatoDecimal(m.temperatura_sugerida, " °C"), clase: "num" },
      ])));
  }

  cargar();
}
