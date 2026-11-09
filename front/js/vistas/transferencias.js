// Transferencias del depósito central a una sala.
//   #/transferencias        consulta por número + transferencias gestionadas en este navegador
//   #/transferencias/nueva  crear la cabecera (número + sala de destino)
// La carga de vinos, terminar y procesar se hacen en el detalle (#/transferencias/:nro),
// porque la API trabaja la transferencia como un documento con estados.
import { obtenerSalas } from "../api/catalogos.js";
import { ApiError } from "../api/cliente.js";
import { crearTransferencia } from "../api/transferencias.js";
import { aviso, dejarAviso } from "../componentes/avisos.js";
import { encabezadoPagina, tabla, tarjeta } from "../componentes/contenido.js";
import { cargando, mensajeError, vacio } from "../componentes/estados.js";
import { campoValidable } from "../componentes/formulario.js";
import { h, icono } from "../dom.js";
import { formatoFecha, textoSala } from "./ventas-comun.js";
import {
  etiquetaEstado, hashTransferencia, olvidarTransferencias, recordarTransferencia, transferenciasRecordadas,
} from "./transferencias-comun.js";

// ---------- Pantalla principal ----------

function consulta() {
  const nro = campoValidable({
    etiqueta: "Número de solicitud",
    control: h("input", { class: "campo__control", type: "search", maxlength: 20, autocomplete: "off", placeholder: "Ej.: TR-000001" }),
  });
  const formulario = h("form", { class: "busqueda", role: "search", "aria-label": "Consultar una transferencia", novalidate: true },
    nro.el, h("button", { class: "boton", type: "submit" }, icono("buscar"), "Consultar"));
  formulario.addEventListener("submit", (e) => {
    e.preventDefault();
    const valor = nro.control.value.trim();
    if (!valor) { nro.error("Ingresá el número de solicitud."); nro.control.focus(); return; }
    nro.error("");
    location.hash = hashTransferencia(valor);
  });
  const { tarjeta: el, cuerpo } = tarjeta({
    titulo: "Consultar una transferencia",
    subtitulo: "Buscá por número de solicitud exacto para ver su estado y sus vinos.",
  });
  cuerpo.append(h("div", { class: "seccion" }, formulario));
  return el;
}

function gestionadas() {
  const { tarjeta: el, cuerpo } = tarjeta({
    titulo: "Gestionadas desde este navegador",
    subtitulo: "La API no ofrece un listado de transferencias: acá se ven solo las creadas o modificadas desde este navegador, con el último estado que devolvió la API.",
  });
  function pintar() {
    const lista = transferenciasRecordadas();
    if (!lista.length) {
      cuerpo.replaceChildren(vacio("Todavía no gestionaste transferencias desde este navegador."));
      return;
    }
    cuerpo.replaceChildren(
      tabla({
        descripcion: "Transferencias gestionadas desde este navegador",
        filas: lista,
        columnas: [
          { titulo: "Solicitud", valor: (t) => h("a", { href: hashTransferencia(t.num_solicitud) }, t.num_solicitud), clase: "mono" },
          { titulo: "Fecha", valor: (t) => formatoFecha(t.fecha_confeccion) },
          { titulo: "Sala", valor: (t) => (t.id_sala != null ? `N° ${t.id_sala}` : null), clase: "num" },
          { titulo: "Último estado visto", valor: (t) => etiquetaEstado(t.estado) },
        ],
      }),
      h("div", { class: "seccion seccion--pie" },
        h("button", { class: "enlace", type: "button", onClick: () => { olvidarTransferencias(); pintar(); } },
          "Quitar esta lista del navegador (no borra transferencias)")));
  }
  pintar();
  return el;
}

export function vistaTransferencias(contenedor) {
  contenedor.replaceChildren(
    encabezadoPagina({
      titulo: "Transferencias",
      descripcion: "Envíos de vinos del depósito central a las salas de venta. El stock lo controla y lo mueve la base de datos al procesar.",
      acciones: h("a", { class: "boton", href: "#/transferencias/nueva" }, icono("mas"), "Nueva transferencia"),
    }),
    h("div", { class: "rejilla" }, consulta(), gestionadas()));
}

// ---------- Nueva transferencia (cabecera) ----------

function formularioNueva(salas, signal) {
  const numero = campoValidable({
    etiqueta: "Número de solicitud", requerido: true,
    control: h("input", { class: "campo__control", type: "text", maxlength: 20, autocomplete: "off", placeholder: "Ej.: TR-009001" }),
    ayuda: "La API no lo asigna: ingresalo (hasta 20 caracteres, único).",
  });
  const sala = campoValidable({
    etiqueta: "Sala de destino", requerido: true, clase: "campo--doble",
    control: h("select", { class: "campo__control" },
      h("option", { value: "" }, "Elegí la sala"),
      ...salas.map((s) => h("option", { value: String(s.id_sala) }, textoSala(s)))),
  });
  const origen = h("div", { class: "campo" },
    h("span", { class: "campo__etiqueta" }, "Origen"),
    h("p", { class: "campo__fijo" }, "Depósito central"),
    h("span", { class: "campo__ayuda" }, "Las transferencias siempre salen del depósito central."));

  const datos = tarjeta({ titulo: "Datos de la transferencia", subtitulo: "La fecha de confección la registra la base (día de hoy, RN-11)." });
  datos.cuerpo.append(h("div", { class: "formulario__campos" }, numero.el, origen, sala.el));

  const grupo = h("fieldset", { class: "formulario__grupo" }, h("legend", { class: "visualmente-oculto" }, "Nueva transferencia"), datos.tarjeta);
  const resumen = h("div", { class: "formulario__resumen", tabindex: "-1" });
  const resultado = h("div", { class: "formulario__resultado", tabindex: "-1" });
  const crear = h("button", { class: "boton", type: "submit" }, icono("ok"), "Crear transferencia");
  const formulario = h("form", { class: "formulario", novalidate: true },
    h("p", { class: "formulario__nota" }, "Se crea en confección; después, en su detalle, se agregan los vinos, se termina y se procesa."),
    resumen, grupo, resultado,
    h("div", { class: "formulario__acciones" }, crear, h("a", { class: "boton boton--secundario", href: "#/transferencias" }, "Cancelar")));

  const ocupado = (si) => {
    grupo.disabled = si;
    crear.disabled = si;
    crear.setAttribute("aria-busy", String(si));
    crear.replaceChildren(si ? h("span", { class: "spinner spinner--chico", "aria-hidden": "true" }) : icono("ok"), si ? "Creando…" : "Crear transferencia");
  };

  let enviando = false;
  formulario.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (enviando) return;   // sin envíos duplicados
    resumen.replaceChildren();
    resultado.replaceChildren();
    const num = numero.control.value.trim();
    const errNum = !num ? "Ingresá el número de solicitud." : num.length > 20 ? "Hasta 20 caracteres." : "";
    const errSala = sala.control.value ? "" : "Elegí la sala de destino.";
    numero.error(errNum);
    sala.error(errSala);
    if (errNum || errSala) {
      resumen.replaceChildren(aviso("Revisá los datos marcados.", "advertencia"));
      (errNum ? numero.control : sala.control).focus();
      return;
    }

    enviando = true;
    ocupado(true);
    let creada;
    try {
      creada = await crearTransferencia({ num_solicitud: num, id_sala: Number(sala.control.value) });
    } catch (error) {
      enviando = false;
      if (signal.aborted) return;
      ocupado(false);
      resultado.replaceChildren(...[mensajeError(error),
        (error?.tipo === "red" || error?.tipo === "tiempo")
          && h("p", { class: "detalle__nota" }, `No se sabe si llegó a crearse. Antes de reintentar, consultá la solicitud ${num}.`)].filter(Boolean));
      resultado.focus();
      return;
    }
    const nro = typeof creada?.num_solicitud === "string" ? creada.num_solicitud : num;
    recordarTransferencia({ ...(creada && typeof creada === "object" ? creada : {}), num_solicitud: nro });
    if (signal.aborted) return;
    dejarAviso(`Transferencia ${nro} creada en confección. Agregá los vinos a enviar.`);
    location.hash = hashTransferencia(nro);
  });

  return formulario;
}

export function vistaNuevaTransferencia(contenedor, { signal }) {
  const cuerpo = h("div", { class: "formulario-transferencia" });
  contenedor.replaceChildren(
    encabezadoPagina({
      titulo: "Nueva transferencia",
      descripcion: "Del depósito central a una sala de venta.",
      acciones: h("a", { class: "boton boton--secundario", href: "#/transferencias" }, icono("anterior"), "Volver a transferencias"),
    }),
    cuerpo);

  async function cargar(forzar = false) {
    cuerpo.replaceChildren(cargando("Cargando salas…"));
    try {
      const salas = await obtenerSalas({ forzar });
      if (!Array.isArray(salas)) throw new ApiError("La API devolvió las salas con un formato inesperado.", { tipo: "formato" });
      if (signal.aborted) return;
      cuerpo.replaceChildren(formularioNueva(salas, signal));
    } catch (error) {
      if (signal.aborted) return;
      cuerpo.replaceChildren(h("p", { class: "formulario__nota" }, "No se pudieron cargar las salas."),
        mensajeError(error, { onReintentar: () => cargar(true) }));
    }
  }
  cargar();
}
