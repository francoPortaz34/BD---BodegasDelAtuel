// Estados reutilizables de cualquier pantalla: cargando, error y sin datos,
// más cargarEn(), que encadena los tres alrededor de una petición.
import { h, icono } from "../dom.js";

export function cargando(texto = "Cargando…") {
  return h("div", { class: "estado estado--cargando", role: "status", "aria-live": "polite" },
    h("span", { class: "spinner", "aria-hidden": "true" }),
    h("p", { class: "estado__texto" }, texto));
}

export function vacio(texto = "No hay datos para mostrar.") {
  return h("div", { class: "estado estado--vacio", role: "status" },
    icono("vacio", "estado__icono"),
    h("p", { class: "estado__texto" }, texto));
}

function tituloError(error) {
  switch (error?.tipo) {
    case "red": return "Sin conexión con la API";
    case "tiempo": return "La API no respondió";
    case "formato": return "Respuesta inesperada de la API";
    case "http":
      if (error.estado === 404) return "No encontrado";
      if (error.estado === 409) return "Operación rechazada";
      if (error.estado === 422 || error.estado === 400) return "Datos inválidos";
      if (error.estado === 502 || error.estado === 503) return "Servicio no disponible";
      return "Error de la API";
    default: return "Ocurrió un error";
  }
}

/**
 * Muestra el error tal como lo informa la API (el mensaje de la regla de
 * negocio no se reemplaza), con el código HTTP / SQLSTATE como referencia.
 */
export function mensajeError(error, { onReintentar } = {}) {
  const detalles = [
    error?.estado ? `HTTP ${error.estado}` : null,
    error?.sqlstate ? `SQLSTATE ${error.sqlstate}` : null,
  ].filter(Boolean).join(" · ");

  return h("div", { class: "estado estado--error", role: "alert" },
    icono("alerta", "estado__icono"),
    h("div", { class: "estado__cuerpo" },
      h("p", { class: "estado__titulo" }, tituloError(error)),
      h("p", { class: "estado__texto" }, error?.message || String(error)),
      detalles && h("p", { class: "estado__detalle" }, detalles)),
    onReintentar && h("button", { class: "boton boton--secundario", type: "button", onClick: onReintentar },
      icono("reintentar"), "Reintentar"));
}

/**
 * Muestra "cargando" en el contenedor, ejecuta cargar() y luego dibuja el
 * resultado, el estado vacío o el error con un botón para reintentar.
 * Si la pantalla se cerró (signal abortado) no dibuja nada.
 */
export async function cargarEn(contenedor, opciones) {
  const {
    cargar, mostrar, signal,
    esVacio = (datos) => Array.isArray(datos) && datos.length === 0,
    textoCarga, textoVacio,
  } = opciones;

  contenedor.replaceChildren(cargando(textoCarga));
  try {
    const datos = await cargar();
    if (signal?.aborted) return;
    contenedor.replaceChildren(esVacio(datos) ? vacio(textoVacio) : mostrar(datos));
  } catch (error) {
    if (signal?.aborted || error?.name === "AbortError") return;
    contenedor.replaceChildren(mensajeError(error, {
      onReintentar: () => cargarEn(contenedor, opciones),
    }));
  }
}
