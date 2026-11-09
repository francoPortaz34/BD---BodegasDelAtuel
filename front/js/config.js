// Lee la configuración de front/config.js (window.BODEGAS_CONFIG) y completa
// los valores por defecto. El resto de la aplicación importa la URL desde acá.
const externa = window.BODEGAS_CONFIG ?? {};

export const config = Object.freeze({
  // Sin barra final, para concatenar rutas que empiezan con "/"
  apiUrl: String(externa.apiUrl ?? "/api").replace(/\/+$/, ""),
  timeoutMs: Number(externa.timeoutMs) > 0 ? Number(externa.timeoutMs) : 15000,
});
