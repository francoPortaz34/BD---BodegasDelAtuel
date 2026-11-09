// Enrutador por hash (#/ruta): no necesita configuración del servidor web.
// Admite parámetros (#/vinos/:cod) y consulta (#/vinos?pagina=2), que usarán
// las subetapas siguientes. Al cambiar de pantalla cancela (AbortSignal) las
// peticiones pendientes de la anterior para que no dibujen sobre la nueva.
import { mensajeError } from "./componentes/estados.js";

function compilar(patron) {
  const nombres = [];
  const expresion = patron.replace(/:([a-zA-Z_]+)/g, (_, nombre) => {
    nombres.push(nombre);
    return "([^/]+)";
  });
  return { regex: new RegExp(`^${expresion}/?$`), nombres };
}

/**
 * rutas: [{ ruta, titulo, vista(contenedor, { params, consulta, signal }) }]
 * Una ruta "*" atiende las direcciones desconocidas.
 */
export function crearRouter({ rutas, contenedor, alCambiar }) {
  const compiladas = rutas.filter((r) => r.ruta !== "*").map((r) => ({ ...r, ...compilar(r.ruta) }));
  const noEncontrada = rutas.find((r) => r.ruta === "*");
  let controlador = null;

  function buscar(camino) {
    for (const r of compiladas) {
      const coincidencia = camino.match(r.regex);
      if (coincidencia) {
        const params = Object.fromEntries(r.nombres.map((n, i) => [n, decodeURIComponent(coincidencia[i + 1])]));
        return { definicion: r, params };
      }
    }
    return { definicion: noEncontrada, params: {} };
  }

  async function resolver() {
    const [camino = "/", textoConsulta = ""] = location.hash.replace(/^#/, "").split("?");
    const { definicion, params } = buscar(camino || "/");

    controlador?.abort();
    controlador = new AbortController();
    const { signal } = controlador;

    alCambiar?.({ camino: camino || "/", definicion });
    document.title = `${definicion.titulo} · Bodegas del Atuel`;
    contenedor.replaceChildren();
    contenedor.focus({ preventScroll: true });
    window.scrollTo(0, 0);

    try {
      await definicion.vista(contenedor, { params, consulta: new URLSearchParams(textoConsulta), signal });
    } catch (error) {
      if (signal.aborted || error?.name === "AbortError") return;
      contenedor.replaceChildren(mensajeError(error, { onReintentar: resolver }));
    }
  }

  window.addEventListener("hashchange", resolver);
  return { iniciar: resolver };
}
