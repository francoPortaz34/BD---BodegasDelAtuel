// Piezas compartidas por las pantallas de transferencias.
import { etiqueta } from "../componentes/contenido.js";

export const hashTransferencia = (nro) => `#/transferencias/${encodeURIComponent(nro)}`;

/** Estados del ENUM estado_movimiento (001_esquema.sql), en orden. */
export const ESTADOS = [
  { valor: "en_confeccion", texto: "En confección" },
  { valor: "terminado", texto: "Terminada" },
  { valor: "procesado", texto: "Procesada" },
];

export const textoEstado = (estado) => ESTADOS.find((e) => e.valor === estado)?.texto ?? estado ?? null;

export const etiquetaEstado = (estado) =>
  (estado ? etiqueta(textoEstado(estado), ESTADOS.some((e) => e.valor === estado) ? `estado-${estado}` : "") : null);

// ---------- Transferencias gestionadas desde este navegador ----------
// La API NO tiene un listado de transferencias. Para retomar las que se crearon
// o modificaron acá (por ejemplo, una que quedó en confección) se guardan en
// localStorage los datos que devolvió la API. No es el listado de la base.

const CLAVE = "bodegas.transferenciasGestionadas";
const MAXIMO = 20;

export function transferenciasRecordadas() {
  try {
    const datos = JSON.parse(localStorage.getItem(CLAVE) ?? "[]");
    return Array.isArray(datos) ? datos.filter((t) => t && typeof t.num_solicitud === "string") : [];
  } catch {
    return [];
  }
}

export function recordarTransferencia(t) {
  try {
    const nueva = {
      num_solicitud: t.num_solicitud,
      fecha_confeccion: t.fecha_confeccion ?? null,
      estado: t.estado ?? null,
      id_sala: t.id_sala ?? null,
    };
    const resto = transferenciasRecordadas().filter((x) => x.num_solicitud !== nueva.num_solicitud);
    localStorage.setItem(CLAVE, JSON.stringify([nueva, ...resto].slice(0, MAXIMO)));
  } catch {
    // Sin almacenamiento: la operación igual quedó hecha en la base
  }
}

export function olvidarTransferencias() {
  try { localStorage.removeItem(CLAVE); } catch { /* sin almacenamiento */ }
}
