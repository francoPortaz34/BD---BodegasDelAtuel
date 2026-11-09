// Vinos (solo lectura en la subetapa 2): GET /vinos y GET /vinos/{cod}.
// Los filtros y la paginación los resuelve la API; acá solo se arman los
// parámetros. cliente.js omite los que vienen vacíos.
import { api, ApiError } from "./cliente.js";

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

/**
 * Todos los vinos (para elegirlos en una venta), recorriendo GET /vinos de a 100
 * hasta una página incompleta. Se guarda en memoria; forzar = volver a pedir.
 * GET /vinos no devuelve id_vino: para obtenerlo se usa obtenerVino(cod).
 */
let todosLosVinos = null;
export function obtenerVinosParaSeleccion({ forzar = false } = {}) {
  if (forzar) todosLosVinos = null;
  if (!todosLosVinos) {
    todosLosVinos = (async () => {
      const vinos = [];
      for (let pagina = 1; pagina <= 1000; pagina++) {
        const datos = await listarVinos({ pagina, tamanio: 100 });
        if (!Array.isArray(datos?.vinos)) throw new ApiError("La API devolvió el listado de vinos con un formato inesperado.", { tipo: "formato" });
        vinos.push(...datos.vinos);
        if (datos.vinos.length < 100) break;
      }
      return vinos;
    })().catch((error) => {
      todosLosVinos = null;   // un fallo no queda en caché: el reintento vuelve a pedir
      throw error;
    });
  }
  return todosLosVinos;
}

/** Presentaciones admitidas por la base (CHECK ck_vino_presentacion, 002_constraints.sql). */
export const PRESENTACIONES_ML = [187, 375, 750, 1500, 3000];

/**
 * POST /vinos (201) -> ficha completa del vino creado (como GET /vinos/{cod}).
 * Cuerpo (VinoNuevo): cod_vino, nombre_comercial, tipo, anada, presentacion_ml,
 * graduacion_alcoholica, precio_venta, id_bodega, cepas [{id_cepa, porcentaje_corte}].
 * NO admite maridajes: se asignan después con modificarVino().
 * La suma 100 de los cortes (RN-05) la controla la base al COMMIT.
 */
export function crearVino(vino, { signal } = {}) {
  return api.post("/vinos", vino, { signal });
}

/**
 * PUT /vinos/{cod} -> ficha completa actualizada. El código no se modifica.
 * Cuerpo (VinoEdicion): los mismos campos de la ficha (todos obligatorios) y,
 * opcionales, cepas [{id_cepa, porcentaje_corte}] y maridajes [id_maridaje].
 * Una lista enviada REEMPLAZA la actual; omitida, no se toca. Todo en una transacción.
 */
export function modificarVino(cod, vino, { signal } = {}) {
  return api.put(`/vinos/${encodeURIComponent(cod)}`, vino, { signal });
}
