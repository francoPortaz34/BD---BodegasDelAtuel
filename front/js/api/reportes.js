// Reportes del tablero (GET /reportes/*). Todas las cifras las calcula la base:
// el front solo las muestra.
import { api } from "./cliente.js";

/** Los 10 vinos con más botellas vendidas: [{ cod_vino, nombre_comercial, anada, presentacion_ml, botellas_vendidas }] */
export const obtenerTopVinos = ({ signal } = {}) => api.get("/reportes/top-vinos", { signal });

/** Monto vendido por sala en el último trimestre: [{ id_sala, localidad, monto_total }] */
export const obtenerVentasPorSala = ({ signal } = {}) => api.get("/reportes/ventas-por-sala", { signal });

/** Vinos sin stock en la sala pero con stock en el depósito: [{ cod_vino, nombre_comercial, stock_deposito }] */
export const obtenerVinosSinStock = (sala, { signal } = {}) =>
  api.get("/reportes/vinos-sin-stock", { consulta: { sala }, signal });

/** Transportista(s) con más ingresos en el último mes (todos si hay empate): [{ cod_transporte, razon_social, ingresos }] */
export const obtenerTransportistaActivo = ({ signal } = {}) => api.get("/reportes/transportista-activo", { signal });

/**
 * Recorrido de un vino: { vino, ingresos: [{ cod_ingreso, fecha, estado, transportista, botellas }],
 * transferencias: [{ num_solicitud, fecha_confeccion, estado, id_sala, localidad, botellas }],
 * ventas_por_sala: [{ id_sala, localidad, comprobantes, botellas }] }. 404 "Vino no encontrado".
 */
export const obtenerTrazabilidad = (cod, { signal } = {}) =>
  api.get(`/reportes/trazabilidad/${encodeURIComponent(cod)}`, { signal });
