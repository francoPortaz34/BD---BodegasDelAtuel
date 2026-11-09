// Campos de formulario reutilizables (etiqueta + control + ayuda + error).
import { h } from "../dom.js";

let contador = 0;

/** Campo simple: etiqueta, control y ayuda opcional (filtros del catálogo). */
export function campo(etiquetaTexto, control, ayuda) {
  return h("label", { class: "campo" },
    h("span", { class: "campo__etiqueta" }, etiquetaTexto), control, ayuda);
}

/**
 * Campo con mensaje de error propio, asociado al control (aria-describedby).
 * Devuelve { el, control, error(mensaje) }: error("") lo limpia.
 */
export function campoValidable({ etiqueta, control, ayuda, requerido = false, clase = "" }) {
  const id = `campo-${++contador}`;
  const idError = `${id}-error`;
  const idAyuda = `${id}-ayuda`;
  control.id = id;
  control.setAttribute("aria-describedby", [ayuda ? idAyuda : null, idError].filter(Boolean).join(" "));
  const mensaje = h("span", { class: "campo__error", id: idError, "aria-live": "polite" });

  const el = h("div", { class: `campo ${clase}`.trim() },
    h("label", { class: "campo__etiqueta", for: id }, etiqueta,
      requerido && h("span", { class: "campo__requerido", "aria-hidden": "true" }, " *")),
    control,
    ayuda && h("span", { class: "campo__ayuda", id: idAyuda }, ayuda),
    mensaje);

  function error(texto) {
    mensaje.textContent = texto ?? "";
    if (texto) control.setAttribute("aria-invalid", "true");
    else control.removeAttribute("aria-invalid");
  }
  return { el, control, error };
}
