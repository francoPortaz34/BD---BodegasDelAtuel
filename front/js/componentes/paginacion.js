// Controles de paginación "anterior / siguiente" para listados cuya API no
// informa el total de registros: quien la usa indica si hay página siguiente.
import { h, icono } from "../dom.js";

/**
 * alIr(pagina): se llama al pedir otra página.
 * Devuelve { el, actualizar({ pagina, haySiguiente, texto }), ocultar() }
 *   haySiguiente: true | false | null (todavía se está verificando)
 */
export function crearPaginacion({ alIr }) {
  let actual = 1;
  const anterior = h("button", { class: "boton boton--secundario", type: "button" },
    icono("anterior"), "Anterior");
  const siguiente = h("button", { class: "boton boton--secundario", type: "button" },
    "Siguiente", icono("siguiente"));
  const estado = h("span", { class: "paginacion__estado", "aria-live": "polite" });
  const el = h("nav", { class: "paginacion", "aria-label": "Paginación", hidden: true },
    anterior, estado, siguiente);

  anterior.addEventListener("click", () => { if (actual > 1) alIr(actual - 1); });
  siguiente.addEventListener("click", () => alIr(actual + 1));

  function actualizar({ pagina, haySiguiente, texto }) {
    actual = pagina;
    el.hidden = false;
    anterior.disabled = pagina <= 1;
    siguiente.disabled = haySiguiente !== true;
    siguiente.title = haySiguiente === null ? "Verificando si hay más resultados…"
      : haySiguiente ? "" : "No hay más resultados";
    estado.textContent = texto ?? `Página ${pagina}`;
  }

  return { el, actualizar, ocultar: () => { el.hidden = true; } };
}
