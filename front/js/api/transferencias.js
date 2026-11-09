// Transferencias del DEPÓSITO CENTRAL a UNA sala de venta (no hay transferencias
// entre salas: el modelo solo tiene la sala de destino).
// Es un documento con estados: en_confeccion -> terminado -> procesado.
// No existe un listado (GET /transferencias) ni endpoints para quitar o
// modificar renglones. Fecha, estados, bloqueo de renglones y stock los
// controla la base (RN-09, RN-11, RN-12, sp_procesar_transferencia).
// Todas las funciones devuelven la transferencia completa:
// { id_transferencia, num_solicitud, fecha_confeccion, estado, id_sala,
//   renglones: [{ id_vino, cod_vino, nombre_comercial, cantidad_botellas }] }
import { api } from "./cliente.js";

const ruta = (nro, resto = "") => `/transferencias/${encodeURIComponent(nro)}${resto}`;

/** GET /transferencias/{nro}; 404 "Transferencia no encontrada". */
export function obtenerTransferencia(nro, { signal } = {}) {
  return api.get(ruta(nro), { signal });
}

/** POST /transferencias (201) { num_solicitud, id_sala }. Nace 'en_confeccion' con la fecha de hoy. */
export function crearTransferencia(datos, { signal } = {}) {
  return api.post("/transferencias", datos, { signal });
}

/** POST /transferencias/{nro}/renglones (201) { id_vino, cantidad_botellas }. Solo en confección (RN-12). */
export function agregarRenglonTransferencia(nro, renglon, { signal } = {}) {
  return api.post(ruta(nro, "/renglones"), renglon, { signal });
}

/** POST /transferencias/{nro}/terminar: en_confeccion -> terminado (RN-11). */
export function terminarTransferencia(nro, { signal } = {}) {
  return api.post(ruta(nro, "/terminar"), undefined, { signal });
}

/**
 * POST /transferencias/{nro}/procesar: mueve el stock del depósito a la sala y
 * pasa a 'procesado'. Atómico: si falta stock o no está terminada -> 409 sin cambios.
 */
export function procesarTransferencia(nro, { signal } = {}) {
  return api.post(ruta(nro, "/procesar"), undefined, { signal });
}
