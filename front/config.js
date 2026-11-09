// Configuración del front (Etapa 7). Es el ÚNICO lugar donde se define a qué API
// se conecta la aplicación; js/config.js la lee y completa los valores por defecto.
//
// apiUrl:
//   "/api"                   (por defecto) mismo origen: el servidor del front
//                            reenvía /api/* a la API (front/servidor.py en
//                            desarrollo). No requiere CORS.
//   "http://127.0.0.1:8000"  llamada directa a la API: requiere que la API
//                            habilite CORS para el origen del front.
// timeoutMs: tiempo máximo de espera de cada petición, en milisegundos.
window.BODEGAS_CONFIG = {
  apiUrl: "/api",
  timeoutMs: 15000,
};
