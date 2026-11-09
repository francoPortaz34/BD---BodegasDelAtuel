// Avisos de resultado (por ejemplo "Vino registrado") y aviso "pendiente" que
// sobrevive a una navegación: la pantalla que guarda lo deja y la siguiente
// (el detalle) lo muestra una sola vez. Solo vive en memoria.
import { h, icono } from "../dom.js";

let pendiente = null;

export function dejarAviso(texto, variante = "ok") {
  pendiente = { texto, variante };
}

/** Devuelve el aviso pendiente como nodo (y lo descarta), o null si no hay. */
export function tomarAviso() {
  const a = pendiente;
  pendiente = null;
  return a ? aviso(a.texto, a.variante) : null;
}

/** variante: "ok" | "advertencia" */
export function aviso(texto, variante = "ok", ...extra) {
  return h("div", { class: `aviso aviso--${variante}`, role: variante === "ok" ? "status" : "alert" },
    icono(variante === "ok" ? "ok" : "alerta", "aviso__icono"),
    h("div", { class: "aviso__cuerpo" }, h("p", { class: "aviso__texto" }, texto), extra));
}
