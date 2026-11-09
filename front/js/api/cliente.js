// Cliente HTTP único del front: TODAS las llamadas a la API pasan por acá.
// - Arma la URL a partir de la configuración centralizada (js/config.js).
// - Envía y recibe JSON.
// - Corta las peticiones que superan el tiempo máximo.
// - Convierte cualquier falla en un ApiError con un mensaje para mostrar.
//   Los mensajes de las reglas de negocio ({"error": "..."} de la API) se
//   conservan TAL CUAL, sin reemplazarlos por un texto genérico.
import { config } from "../config.js";

export class ApiError extends Error {
  /**
   * @param {string} mensaje  texto para mostrar al usuario
   * @param {object} datos
   *   tipo:     "red" (sin conexión), "tiempo" (no respondió), "http" (respondió
   *             con 4xx/5xx) o "formato" (respuesta que no es JSON)
   *   estado:   código HTTP, si hubo respuesta
   *   sqlstate: código de PostgreSQL que informa la API, si lo hay
   *   cuerpo:   cuerpo JSON de la respuesta, si lo hay
   */
  constructor(mensaje, { tipo, estado = null, sqlstate = null, cuerpo = null } = {}) {
    super(mensaje);
    this.name = "ApiError";
    this.tipo = tipo;
    this.estado = estado;
    this.sqlstate = sqlstate;
    this.cuerpo = cuerpo;
  }
}

const MENSAJES_HTTP = {
  400: "La API rechazó la petición por un dato con formato inválido.",
  404: "El recurso solicitado no existe.",
  409: "La operación entra en conflicto con los datos existentes.",
  422: "Los datos enviados no son válidos.",
  500: "Error interno de la API.",
  502: "No se pudo conectar con la API.",
  503: "El servicio no está disponible en este momento.",
};

/** Arma la URL completa con los parámetros de consulta (omite los vacíos). */
export function construirUrl(ruta, consulta) {
  const url = `${config.apiUrl}${ruta.startsWith("/") ? ruta : `/${ruta}`}`;
  if (!consulta) return url;
  const parametros = new URLSearchParams();
  for (const [clave, valor] of Object.entries(consulta)) {
    if (valor === undefined || valor === null || valor === "") continue;
    parametros.append(clave, String(valor));
  }
  const texto = parametros.toString();
  return texto ? `${url}?${texto}` : url;
}

/** Extrae el mensaje de error que envía la API, sin modificarlo. */
function mensajeDeRespuesta(cuerpo, estado) {
  if (cuerpo && typeof cuerpo === "object") {
    // Errores de PostgreSQL y reglas de negocio: {"error": "...", "sqlstate": "..."}
    if (typeof cuerpo.error === "string" && cuerpo.error) return cuerpo.error;
    // HTTPException de FastAPI: {"detail": "..."}
    if (typeof cuerpo.detail === "string" && cuerpo.detail) return cuerpo.detail;
    // Validación de FastAPI (422): {"detail": [{"loc": [...], "msg": "..."}]}
    if (Array.isArray(cuerpo.detail) && cuerpo.detail.length) {
      return cuerpo.detail
        .map((d) => {
          const campo = Array.isArray(d.loc) ? d.loc.filter((p) => p !== "body").join(".") : "";
          return campo ? `${campo}: ${d.msg}` : d.msg;
        })
        .join(" · ");
    }
  }
  return MENSAJES_HTTP[estado] ?? `La API respondió con el código HTTP ${estado}.`;
}

/**
 * Hace una petición a la API y devuelve el cuerpo JSON ya interpretado.
 * @param {string} metodo  GET, POST, PUT o DELETE
 * @param {string} ruta    ruta de la API, por ejemplo "/vinos"
 * @param {object} [opciones]
 *   consulta: objeto con parámetros de consulta (?clave=valor)
 *   cuerpo:   objeto que se envía como JSON
 *   signal:   AbortSignal para cancelar (por ejemplo al cambiar de pantalla)
 */
export async function solicitar(metodo, ruta, { consulta, cuerpo, signal } = {}) {
  const url = construirUrl(ruta, consulta);
  const controlador = new AbortController();
  const temporizador = setTimeout(() => controlador.abort(), config.timeoutMs);
  const cancelar = () => controlador.abort();
  signal?.addEventListener("abort", cancelar, { once: true });

  const encabezados = { Accept: "application/json" };
  if (cuerpo !== undefined) encabezados["Content-Type"] = "application/json";

  let respuesta;
  let texto;
  try {
    respuesta = await fetch(url, {
      method: metodo,
      headers: encabezados,
      body: cuerpo !== undefined ? JSON.stringify(cuerpo) : undefined,
      signal: controlador.signal,
    });
    texto = await respuesta.text();
  } catch (error) {
    // Cancelación pedida por quien llamó: se propaga el AbortError sin mostrarlo
    if (signal?.aborted) throw new DOMException("Petición cancelada", "AbortError");
    if (controlador.signal.aborted) {
      throw new ApiError(
        `La API no respondió en ${Math.round(config.timeoutMs / 1000)} segundos.`,
        { tipo: "tiempo" },
      );
    }
    throw new ApiError(
      `No se pudo conectar con la API (${config.apiUrl}). Verificá que esté en ejecución.`,
      { tipo: "red" },
    );
  } finally {
    clearTimeout(temporizador);
    signal?.removeEventListener("abort", cancelar);
  }

  let datos = null;
  if (texto) {
    try {
      datos = JSON.parse(texto);
    } catch {
      if (respuesta.ok) {
        throw new ApiError("La API devolvió una respuesta que no es JSON.", {
          tipo: "formato",
          estado: respuesta.status,
        });
      }
    }
  }

  if (!respuesta.ok) {
    throw new ApiError(mensajeDeRespuesta(datos, respuesta.status), {
      tipo: "http",
      estado: respuesta.status,
      sqlstate: datos?.sqlstate ?? null,
      cuerpo: datos,
    });
  }
  return datos;
}

export const api = {
  get: (ruta, opciones) => solicitar("GET", ruta, opciones),
  post: (ruta, cuerpo, opciones) => solicitar("POST", ruta, { ...opciones, cuerpo }),
  put: (ruta, cuerpo, opciones) => solicitar("PUT", ruta, { ...opciones, cuerpo }),
  delete: (ruta, opciones) => solicitar("DELETE", ruta, opciones),
};
