// Piezas compartidas por las pantallas de ventas.

export const hashVenta = (nro) => `#/ventas/${encodeURIComponent(nro)}`;

/** "2021-01-04" -> "04/01/2021" sin pasar por Date (evita corrimientos de zona horaria). */
export function formatoFecha(texto) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(texto ?? "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : texto ?? null;
}

/** "N° 3 · San Rafael · San Martín 100" (solo presentación). */
export function textoSala(sala) {
  if (!sala) return null;
  const direccion = [sala.calle, sala.numero].filter(Boolean).join(" ");
  return [`N° ${sala.id_sala}`, sala.localidad, direccion].filter(Boolean).join(" · ");
}

// ---------- Ventas registradas desde este navegador ----------
// La API NO tiene un listado de comprobantes. Para no perder de vista lo que se
// registró, se guardan los datos que devolvió la API al registrar (número,
// fecha, cliente y total, tal cual) en localStorage. Es solo una comodidad de
// este navegador: no es el listado de ventas de la base.

const CLAVE = "bodegas.ventasRegistradas";
const MAXIMO = 20;

export function ventasRecordadas() {
  try {
    const datos = JSON.parse(localStorage.getItem(CLAVE) ?? "[]");
    return Array.isArray(datos) ? datos.filter((v) => v && typeof v.num_comprobante === "string") : [];
  } catch {
    return [];   // navegación privada o almacenamiento bloqueado
  }
}

export function recordarVenta(venta) {
  try {
    const nueva = {
      num_comprobante: venta.num_comprobante,
      fecha: venta.fecha ?? null,
      cliente: venta.cliente ?? null,
      total: venta.total ?? null,
    };
    const resto = ventasRecordadas().filter((v) => v.num_comprobante !== nueva.num_comprobante);
    localStorage.setItem(CLAVE, JSON.stringify([nueva, ...resto].slice(0, MAXIMO)));
  } catch {
    // Sin almacenamiento disponible: la venta igual quedó registrada en la base
  }
}

export function olvidarVentas() {
  try { localStorage.removeItem(CLAVE); } catch { /* sin almacenamiento */ }
}
