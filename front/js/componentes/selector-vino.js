// Campo para elegir UN vino por su código, con sugerencias de los vinos del
// catálogo (datalist). Al elegirlo se pide GET /vinos/{cod} SOLO para ese vino
// (GET /vinos no trae id_vino). No se consultan los vinos de antemano.
import { ApiError } from "../api/cliente.js";
import { obtenerVino } from "../api/vinos.js";
import { h } from "../dom.js";

let contador = 0;

/**
 * vinos: lista de GET /vinos (cod_vino, nombre_comercial, anada, presentacion_ml)
 * Devuelve { input, info, error, lista (datalist a insertar), leer() -> { vino } | { error }, limpiar() }
 */
export function crearSelectorVino({ vinos, signal, etiqueta = "Vino (código)", placeholder = "Código del vino (ej.: V0001)" }) {
  const idLista = `selector-vino-${++contador}`;
  const porCodigo = new Map(vinos.map((v) => [String(v.cod_vino).toUpperCase(), v]));
  const lista = h("datalist", { id: idLista },
    vinos.map((v) => h("option", { value: v.cod_vino },
      [v.nombre_comercial, v.anada, v.presentacion_ml && `${v.presentacion_ml} ml`].filter(Boolean).join(" · "))));
  const input = h("input", {
    class: "campo__control", type: "text", list: idLista, autocomplete: "off", placeholder, "aria-label": etiqueta,
  });
  const info = h("span", { class: "renglon__info" });
  const error = h("span", { class: "campo__error", "aria-live": "polite" });

  let estado = "vacio";   // vacio | buscando | ok | error
  let vino = null;
  let secuencia = 0;

  async function resolver() {
    const cod = input.value.trim().toUpperCase();
    const numero = ++secuencia;
    vino = null;
    error.textContent = "";
    input.removeAttribute("aria-invalid");
    if (!cod) { estado = "vacio"; info.textContent = ""; return; }
    const delCatalogo = porCodigo.get(cod);
    if (!delCatalogo) {
      estado = "error"; info.textContent = "";
      error.textContent = "No hay un vino con ese código en el catálogo.";
      input.setAttribute("aria-invalid", "true");
      return;
    }
    input.value = delCatalogo.cod_vino;
    estado = "buscando";
    info.textContent = `${delCatalogo.nombre_comercial} · verificando…`;
    try {
      const detalle = await obtenerVino(delCatalogo.cod_vino, { signal });
      if (numero !== secuencia || signal?.aborted) return;
      if (!Number.isInteger(detalle?.id_vino)) {
        throw new ApiError("La API devolvió el vino sin su identificador.", { tipo: "formato" });
      }
      vino = detalle;
      estado = "ok";
      info.textContent = [detalle.nombre_comercial, detalle.anada, `${detalle.presentacion_ml} ml`, detalle.bodega].filter(Boolean).join(" · ");
    } catch (e) {
      if (numero !== secuencia || signal?.aborted || e?.name === "AbortError") return;
      estado = "error";
      info.textContent = "";
      error.textContent = `No se pudo verificar el vino: ${e.message}`;
      input.setAttribute("aria-invalid", "true");
    }
  }

  input.addEventListener("change", resolver);

  function leer() {
    const mensaje = estado === "vacio" ? "Elegí un vino."
      : estado === "buscando" ? "Esperá a que se verifique el vino."
        : estado === "error" ? (error.textContent || "Vino inválido.") : "";
    error.textContent = mensaje;
    input.toggleAttribute("aria-invalid", Boolean(mensaje));
    return mensaje ? { error: mensaje } : { vino };
  }

  function limpiar() {
    secuencia++;
    input.value = "";
    vino = null;
    estado = "vacio";
    info.textContent = "";
    error.textContent = "";
    input.removeAttribute("aria-invalid");
  }

  return { input, info, error, lista, leer, limpiar };
}
