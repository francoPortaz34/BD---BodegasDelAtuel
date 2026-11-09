// Clientes (solo búsqueda, para elegir el cliente de una venta).
import { api } from "./cliente.js";

/**
 * GET /clientes -> { pagina, tamanio, clientes: [{ id_cliente, nombre_o_razon_social,
 * tipo_documento, num_documento, calle, numero, fecha_alta, id_localidad,
 * id_tipo_cliente, tipo_cliente, subtipo, ... }] }
 * nombre / documento: coincidencia parcial (sin distinguir mayúsculas); combinables.
 * No informa el total de registros.
 */
export function buscarClientes({ nombre, documento, pagina, tamanio } = {}, { signal } = {}) {
  return api.get("/clientes", { consulta: { nombre, documento, pagina, tamanio }, signal });
}
