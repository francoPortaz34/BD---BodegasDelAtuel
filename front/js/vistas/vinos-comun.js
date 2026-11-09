// Piezas compartidas por el listado y el detalle de vinos:
// - El estado de búsqueda (filtros + página) vive en la dirección:
//   #/vinos?tipo=tinto&cepa=Malbec&bodega=3&anada=2020&pagina=2&tamanio=20
//   Así se conserva al ir al detalle y volver, al recargar y con atrás/adelante.
// - Formato de presentación de los valores que devuelve la API (no se calcula nada).
import { TAMANIO_POR_DEFECTO, TIPOS_VINO } from "../api/vinos.js";
import { etiqueta } from "../componentes/contenido.js";

const TAMANIOS = [10, 20, 50, 100];
export { TAMANIOS };

const entero = (texto, minimo, maximo) => {
  if (!/^\d{1,6}$/.test(texto ?? "")) return null;
  const n = Number(texto);
  return n >= minimo && n <= maximo ? n : null;
};

/** Lee y sanea el estado de búsqueda desde los parámetros de la dirección. */
export function leerBusqueda(consulta) {
  const tipo = (consulta.get("tipo") ?? "").trim().toLowerCase();
  const cepa = (consulta.get("cepa") ?? "").trim();
  return {
    tipo: TIPOS_VINO.includes(tipo) ? tipo : "",
    cepa,
    bodega: entero(consulta.get("bodega"), 1, 2147483647) ?? "",
    anada: entero(consulta.get("anada"), 0, 32767) ?? "",   // SMALLINT
    pagina: entero(consulta.get("pagina"), 1, 999999) ?? 1,
    tamanio: entero(consulta.get("tamanio"), 1, 100) ?? TAMANIO_POR_DEFECTO,
  };
}

/** Texto de consulta (sin "?") con los valores no vacíos ni por defecto. */
export function escribirBusqueda({ tipo, cepa, bodega, anada, pagina, tamanio }) {
  const p = new URLSearchParams();
  if (tipo) p.set("tipo", tipo);
  if (cepa) p.set("cepa", cepa);
  if (bodega !== "" && bodega != null) p.set("bodega", String(bodega));
  if (anada !== "" && anada != null) p.set("anada", String(anada));
  if (pagina && pagina !== 1) p.set("pagina", String(pagina));
  if (tamanio && tamanio !== TAMANIO_POR_DEFECTO) p.set("tamanio", String(tamanio));
  return p.toString();
}

export const hashCatalogo = (busqueda) => {
  const texto = escribirBusqueda(busqueda);
  return texto ? `#/vinos?${texto}` : "#/vinos";
};

/** Detalle de un vino; lleva la búsqueda actual para poder volver a ella. */
export const hashDetalle = (cod, busqueda) => {
  const texto = escribirBusqueda(busqueda);
  return `#/vinos/${encodeURIComponent(cod)}${texto ? `?${texto}` : ""}`;
};

/** Alta y edición; también llevan la búsqueda para volver a ella al cancelar o guardar. */
export const hashAlta = (busqueda) => {
  const texto = escribirBusqueda(busqueda);
  return `#/vinos/nuevo${texto ? `?${texto}` : ""}`;
};

export const hashEdicion = (cod, busqueda) => {
  const texto = escribirBusqueda(busqueda);
  return `#/vinos/${encodeURIComponent(cod)}/editar${texto ? `?${texto}` : ""}`;
};

export const hayFiltros = (b) => Boolean(b.tipo || b.cepa || b.bodega !== "" || b.anada !== "");

// ---------- Formato (solo presentación) ----------

const pesos = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", minimumFractionDigits: 2 });
const decimal = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 2 });

// La API serializa los DECIMAL como número; si llegara como texto se respeta tal cual.
const comoNumero = (v) => (v === null || v === undefined || v === "" ? null : Number(v));

export function formatoPrecio(v) {
  const n = comoNumero(v);
  return n === null ? null : Number.isFinite(n) ? pesos.format(n) : String(v);
}

export function formatoDecimal(v, sufijo = "") {
  const n = comoNumero(v);
  return n === null ? null : `${Number.isFinite(n) ? decimal.format(n) : String(v)}${sufijo}`;
}

export const capital = (t) => (t ? t.charAt(0).toUpperCase() + t.slice(1) : null);

// La variante de color solo se aplica a los tipos conocidos
export const etiquetaTipo = (tipo) =>
  (tipo ? etiqueta(capital(tipo), TIPOS_VINO.includes(tipo) ? `vino-${tipo}` : "") : null);
