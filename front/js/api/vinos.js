// Vinos (solo lectura en la subetapa 2): GET /vinos y GET /vinos/{cod}.
// Los filtros y la paginación los resuelve la API; acá solo se arman los
// parámetros. cliente.js omite los que vienen vacíos.
import { api } from "./cliente.js";

/** Valores del ENUM tipo_vino (db/migrations/001_esquema.sql). La API los espera en minúscula. */
export const TIPOS_VINO = ["tinto", "blanco", "rosado", "espumante"];

/** Cantidad por página por defecto de la API (GET /vinos: tamanio entre 1 y 100). */
export const TAMANIO_POR_DEFECTO = 20;

/**
 * GET /vinos -> { pagina, tamanio, vinos: [{cod_vino, nombre_comercial, tipo, anada,
 * presentacion_ml, graduacion_alcoholica, precio_venta, id_bodega, bodega}] }
 * La respuesta NO informa el total de registros.
 * @param {object} filtros  tipo (texto), cepa (nombre de la cepa), bodega (id_bodega),
 *                          anada, pagina (>= 1), tamanio (1 a 100)
 */
export function listarVinos({ tipo, cepa, bodega, anada, pagina, tamanio } = {}, { signal } = {}) {
  return api.get("/vinos", { consulta: { tipo, cepa, bodega, anada, pagina, tamanio }, signal });
}

/**
 * GET /vinos/{cod} -> datos del vino + id_vino, cepas [{id_cepa, nombre, porcentaje_corte}]
 * y maridajes [{id_maridaje, nombre, temperatura_sugerida}]. 404 "Vino no encontrado".
 */
export function obtenerVino(cod, { signal } = {}) {
  return api.get(`/vinos/${encodeURIComponent(cod)}`, { signal });
}
