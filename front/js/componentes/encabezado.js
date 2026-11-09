// Encabezado de la aplicación: marca y estado de la conexión con la API (/salud).
import { api } from "../api/cliente.js";
import { config } from "../config.js";
import { h, icono } from "../dom.js";

export function crearEncabezado(contenedor) {
  const indicador = h("button", {
    class: "conexion", type: "button", "aria-live": "polite",
    title: "Verificar la conexión con la API",
  });

  function pintar(estado, texto, detalle) {
    indicador.dataset.estado = estado;
    indicador.title = `${detalle}\nAPI: ${config.apiUrl}\n(clic para volver a verificar)`;
    indicador.replaceChildren(h("span", { class: "conexion__punto", "aria-hidden": "true" }),
      h("span", { class: "conexion__texto" }, texto));
  }

  async function verificar() {
    pintar("verificando", "Verificando…", "Consultando /salud");
    try {
      await api.get("/salud");
      pintar("ok", "Conectado", "API y base de datos disponibles");
    } catch (error) {
      // 503 con {"api": "ok"}: la API responde pero no llega a PostgreSQL
      if (error.estado === 503 && error.cuerpo?.api === "ok") {
        pintar("parcial", "Sin base de datos", "La API responde, pero no puede conectarse a la base");
      } else {
        pintar("error", "Sin conexión", error.message);
      }
    }
  }

  indicador.addEventListener("click", verificar);

  contenedor.replaceChildren(
    h("a", { class: "marca", href: "#/" },
      icono("copa", "marca__logo"),
      h("span", { class: "marca__texto" },
        h("span", { class: "marca__nombre" }, "Bodegas del Atuel"),
        h("span", { class: "marca__lema" }, "Sistema de gestión"))),
    indicador);

  verificar();
  return { verificar };
}
