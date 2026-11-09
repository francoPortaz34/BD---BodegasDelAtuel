// Ventas (comprobantes). La API solo ofrece registrar una venta y consultar
// una por su número: NO existe un listado de comprobantes (GET /comprobantes).
// Precios, descuentos, subtotales, totales y stock los resuelve la base.
import { api } from "./cliente.js";

/**
 * POST /comprobantes (201) -> comprobante completo (como obtenerVenta).
 * Cuerpo: { num_comprobante, id_cliente, id_sala, renglones: [{ id_vino, cantidad }] }
 * La fecha la pone la base (CURRENT_DATE). Toda la venta es una transacción:
 * si un renglón falla (por ejemplo, stock insuficiente, RN-09) no se guarda nada.
 */
export function registrarVenta(venta, { signal } = {}) {
  return api.post("/comprobantes", venta, { signal });
}

/**
 * GET /comprobantes/{nro} -> { id_comprobante, num_comprobante, fecha, id_cliente, cliente,
 * id_sala, subtotal, descuento, total, renglones: [{ id_vino, cod_vino, nombre_comercial,
 * cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon }] }
 * 404 "Comprobante no encontrado".
 */
export function obtenerVenta(nro, { signal } = {}) {
  return api.get(`/comprobantes/${encodeURIComponent(nro)}`, { signal });
}
