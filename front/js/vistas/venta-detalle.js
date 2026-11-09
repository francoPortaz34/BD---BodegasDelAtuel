// Detalle de una venta (#/ventas/:nro) tal como lo devuelve GET /comprobantes/{nro}.
// Todos los importes (precio unitario, descuento, subtotales y total) son los
// que calculó la base: no se recalcula nada.
import { obtenerSalas } from "../api/catalogos.js";
import { ApiError } from "../api/cliente.js";
import { obtenerVenta } from "../api/ventas.js";
import { tomarAviso } from "../componentes/avisos.js";
import { encabezadoPagina, tabla, tarjeta } from "../componentes/contenido.js";
import { cargando, mensajeError, vacio } from "../componentes/estados.js";
import { h, icono } from "../dom.js";
import { formatoDecimal, formatoPrecio, hashDetalle } from "./vinos-comun.js";
import { formatoFecha, textoSala } from "./ventas-comun.js";

function datosGenerales(venta, sala) {
  const dato = (nombre, valor, clase) => [h("dt", {}, nombre), h("dd", { class: clase }, valor ?? "—")];
  return h("dl", { class: "ficha" },
    dato("Comprobante", venta.num_comprobante, "mono"),
    dato("Fecha", formatoFecha(venta.fecha)),
    dato("Cliente", venta.cliente ? `${venta.cliente} (N° ${venta.id_cliente})` : `N° ${venta.id_cliente}`),
    dato("Sala de venta", sala),
    dato("Subtotal", formatoPrecio(venta.subtotal)),
    dato("Descuento", formatoPrecio(venta.descuento)),
    dato("Total", h("strong", {}, formatoPrecio(venta.total) ?? "—")));
}

export function vistaDetalleVenta(contenedor, { params, signal }) {
  const nro = params.nro;
  const volver = () => h("a", { class: "boton boton--secundario", href: "#/ventas" }, icono("anterior"), "Volver a ventas");
  let cabecera = encabezadoPagina({ titulo: "Detalle de la venta", descripcion: `Comprobante ${nro}`, acciones: volver() });
  const cuerpo = h("div", { class: "detalle" });
  const avisoGuardado = tomarAviso();   // "Venta registrada…" cuando se llega desde el alta
  contenedor.replaceChildren(...[cabecera, avisoGuardado, cuerpo].filter(Boolean));

  async function cargar() {
    cuerpo.replaceChildren(cargando("Cargando la venta…"));
    let venta;
    try {
      venta = await obtenerVenta(nro, { signal });
      if (!venta || typeof venta !== "object" || !Array.isArray(venta.renglones)) {
        throw new ApiError("La API devolvió una respuesta con un formato inesperado.", { tipo: "formato" });
      }
    } catch (error) {
      if (signal.aborted || error?.name === "AbortError") return;
      const noExiste = error?.estado === 404;
      cuerpo.replaceChildren(mensajeError(error, { onReintentar: noExiste ? null : cargar }));
      if (noExiste) cuerpo.append(h("p", { class: "detalle__nota" }, `No hay un comprobante registrado con el número «${nro}».`));
      return;
    }
    if (signal.aborted) return;

    // La sala llega como id: se completa con el catálogo de salas si está disponible
    const sala = h("span", {}, `N° ${venta.id_sala}`);
    obtenerSalas().then((salas) => {
      const s = Array.isArray(salas) ? salas.find((x) => x.id_sala === venta.id_sala) : null;
      if (s && !signal.aborted) sala.textContent = textoSala(s);
    }).catch(() => { /* se deja el número de sala */ });

    document.title = `Venta ${venta.num_comprobante} · Bodegas del Atuel`;
    const nueva = encabezadoPagina({
      titulo: `Venta ${venta.num_comprobante}`,
      descripcion: [formatoFecha(venta.fecha), venta.cliente].filter(Boolean).join(" · "),
      acciones: volver(),
    });
    cabecera.replaceWith(nueva);
    cabecera = nueva;

    const general = tarjeta({ titulo: "Datos del comprobante", clase: "tarjeta--ancha" });
    general.cuerpo.append(datosGenerales(venta, sala));

    const renglones = tarjeta({ titulo: "Vinos vendidos", clase: "tarjeta--ancha" });
    renglones.cuerpo.append(venta.renglones.length
      ? tabla({
        descripcion: "Vinos vendidos",
        filas: venta.renglones,
        columnas: [
          { titulo: "Código", valor: (r) => h("a", { href: hashDetalle(r.cod_vino, {}) }, r.cod_vino), clase: "mono" },
          { titulo: "Vino", valor: (r) => r.nombre_comercial },
          { titulo: "Cantidad", valor: (r) => r.cantidad, clase: "num" },
          { titulo: "Precio unitario", valor: (r) => formatoPrecio(r.precio_unitario_venta), clase: "num" },
          { titulo: "Descuento", valor: (r) => formatoDecimal(r.descuento_aplicado, " %"), clase: "num" },
          { titulo: "Subtotal", valor: (r) => formatoPrecio(r.subtotal_renglon), clase: "num" },
        ],
      })
      : vacio("El comprobante no tiene renglones."));

    cuerpo.replaceChildren(h("div", { class: "rejilla" }, general.tarjeta, renglones.tarjeta));
  }

  cargar();
}
