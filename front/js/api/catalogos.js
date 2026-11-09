// Catálogos de solo lectura (GET /salas, /bodegas, /cepas, /maridajes).
// Son tablas chicas que cambian poco: se piden una vez y se guardan en memoria
// para reutilizarlas en los selectores de las pantallas siguientes (filtros del
// catálogo de vinos, alta/edición, ventas, transferencias y tablero).
// Si una petición falla se descarta de la caché, así el reintento vuelve a pedirla.
import { api } from "./cliente.js";

const cache = new Map();

function obtener(ruta, { forzar = false } = {}) {
  if (forzar) cache.delete(ruta);
  if (!cache.has(ruta)) {
    // Sin signal: la petición es compartida y no debe cancelarse si una
    // pantalla se cierra antes de que llegue la respuesta.
    const promesa = api.get(ruta).catch((error) => {
      cache.delete(ruta);
      throw error;
    });
    cache.set(ruta, promesa);
  }
  return cache.get(ruta);
}

/** [{id_sala, calle, numero, dia_cierre_semanal, id_localidad, localidad, provincia}] */
export const obtenerSalas = (opciones) => obtener("/salas", opciones);
/** [{id_bodega, cuit, razon_social, calle, numero}] ordenadas por razón social */
export const obtenerBodegas = (opciones) => obtener("/bodegas", opciones);
/** [{id_cepa, nombre, tipo}] ordenadas por nombre */
export const obtenerCepas = (opciones) => obtener("/cepas", opciones);
/** [{id_maridaje, nombre, temperatura_sugerida}] ordenados por nombre */
export const obtenerMaridajes = (opciones) => obtener("/maridajes", opciones);
