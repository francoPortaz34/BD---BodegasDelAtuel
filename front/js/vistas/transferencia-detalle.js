// Detalle de una transferencia (#/transferencias/:nro) y sus acciones según el
// estado que informa la API (el endpoint existe para que el front habilite los
// botones según el estado):
//   en_confeccion -> agregar vinos (de a uno) y terminar
//   terminado     -> procesar (mueve el stock del depósito a la sala)
//   procesado     -> solo consulta
// El front no calcula ni mueve stock: lo hace sp_procesar_transferencia. Si la
// base rechaza una operación, se muestra su mensaje tal cual y no cambia nada.
// No hay endpoints para quitar ni modificar renglones.
import { obtenerSalas } from "../api/catalogos.js";
import { ApiError } from "../api/cliente.js";
import {
  agregarRenglonTransferencia, obtenerTransferencia, procesarTransferencia, terminarTransferencia,
} from "../api/transferencias.js";
import { obtenerVinosParaSeleccion } from "../api/vinos.js";
import { aviso, tomarAviso } from "../componentes/avisos.js";
import { encabezadoPagina, tabla, tarjeta } from "../componentes/contenido.js";
import { cargando, mensajeError, vacio } from "../componentes/estados.js";
import { crearSelectorVino } from "../componentes/selector-vino.js";
import { h, icono } from "../dom.js";
import { hashDetalle } from "./vinos-comun.js";
import { formatoFecha, textoSala } from "./ventas-comun.js";
import { ESTADOS, etiquetaEstado, recordarTransferencia } from "./transferencias-comun.js";

const ENTERO_POSITIVO = /^[1-9]\d{0,8}$/;   // cantidad_botellas > 0 (ck_renglon_transferencia_cantidad)

const esTransferencia = (t) => t && typeof t === "object" && typeof t.num_solicitud === "string" && Array.isArray(t.renglones);
const formatoInvalido = () => new ApiError("La API devolvió una respuesta con un formato inesperado.", { tipo: "formato" });

function pasos(estado) {
  const actual = ESTADOS.findIndex((e) => e.valor === estado);
  return h("ol", { class: "pasos", "aria-label": "Estado de la transferencia" },
    ESTADOS.map((e, i) => h("li", {
      class: `pasos__paso ${i < actual ? "pasos__paso--hecho" : ""} ${i === actual ? "pasos__paso--actual" : ""}`.trim(),
      "aria-current": i === actual ? "step" : null,
    }, h("span", { class: "pasos__numero", "aria-hidden": "true" }, String(i + 1)), e.texto)));
}

/** Botón con confirmación en línea (sin diálogos modales del navegador). */
function accionConfirmada({ texto, icono: nombreIcono, advertencias, confirmar, alConfirmar }) {
  const caja = h("div", { class: "accion" });
  const iniciar = h("button", { class: "boton", type: "button" }, icono(nombreIcono), texto);
  const mostrarInicio = () => caja.replaceChildren(iniciar);
  iniciar.addEventListener("click", () => {
    const si = h("button", { class: "boton", type: "button" }, icono("ok"), confirmar);
    const no = h("button", { class: "boton boton--secundario", type: "button", onClick: mostrarInicio }, "Cancelar");
    si.addEventListener("click", () => alConfirmar({ si, no }));
    caja.replaceChildren(h("div", { class: "confirmacion", role: "group", "aria-label": `Confirmar: ${texto}` },
      advertencias.filter(Boolean).map((a) => h("p", { class: "confirmacion__texto" }, a)),
      h("div", { class: "confirmacion__botones" }, si, no)));
    si.focus();
  });
  mostrarInicio();
  return caja;
}

export function vistaDetalleTransferencia(contenedor, { params, signal }) {
  const nro = params.nro;
  const volver = () => h("a", { class: "boton boton--secundario", href: "#/transferencias" }, icono("anterior"), "Volver a transferencias");
  let cabecera = encabezadoPagina({ titulo: "Detalle de la transferencia", descripcion: `Solicitud ${nro}`, acciones: volver() });
  const avisos = h("div", { class: "detalle__avisos" });
  const cuerpo = h("div", { class: "detalle" });
  const pendiente = tomarAviso();
  if (pendiente) avisos.append(pendiente);
  contenedor.replaceChildren(cabecera, avisos, cuerpo);

  let salas = null;
  let ocupada = false;   // una operación a la vez (sin envíos duplicados)

  async function cargar() {
    cuerpo.replaceChildren(cargando("Cargando la transferencia…"));
    let t;
    try {
      t = await obtenerTransferencia(nro, { signal });
      if (!esTransferencia(t)) throw formatoInvalido();
    } catch (error) {
      if (signal.aborted || error?.name === "AbortError") return;
      const noExiste = error?.estado === 404;
      cuerpo.replaceChildren(mensajeError(error, { onReintentar: noExiste ? null : cargar }));
      if (noExiste) cuerpo.append(h("p", { class: "detalle__nota" }, `No hay una transferencia con el número de solicitud «${nro}».`));
      return;
    }
    if (signal.aborted) return;
    pintar(t);
  }

  /** Ejecuta una operación de escritura y vuelve a dibujar con la respuesta de la API. */
  async function operar({ ejecutar, exito, resultado, botones }) {
    if (ocupada) return;
    ocupada = true;
    for (const b of botones) b.disabled = true;
    resultado.replaceChildren(cargando("Enviando a la API…"));
    let t;
    try {
      // Sin signal: una vez enviada, la operación se completa en el servidor
      t = await ejecutar();
      if (!esTransferencia(t)) throw formatoInvalido();
    } catch (error) {
      ocupada = false;
      if (signal.aborted) return;
      for (const b of botones) b.disabled = false;
      const incierto = error?.tipo === "red" || error?.tipo === "tiempo" || error?.tipo === "formato";
      resultado.replaceChildren(...[mensajeError(error),
        incierto && h("div", { class: "detalle__nota" },
          "No se sabe si la operación llegó a aplicarse. ",
          h("button", { class: "enlace", type: "button", onClick: cargar }, "Volver a consultar la transferencia"))].filter(Boolean));
      return;
    }
    ocupada = false;
    recordarTransferencia(t);
    if (signal.aborted) return;
    avisos.replaceChildren(aviso(exito(t)));
    pintar(t);
  }

  function pintar(t) {
    document.title = `Transferencia ${t.num_solicitud} · Bodegas del Atuel`;
    const nueva = encabezadoPagina({
      titulo: `Transferencia ${t.num_solicitud}`,
      descripcion: `Depósito central → sala N° ${t.id_sala}`,
      acciones: volver(),
    });
    cabecera.replaceWith(nueva);
    cabecera = nueva;

    const destino = h("span", {}, `N° ${t.id_sala}`);
    (salas ? Promise.resolve(salas) : obtenerSalas()).then((lista) => {
      salas = lista;
      const s = Array.isArray(lista) ? lista.find((x) => x.id_sala === t.id_sala) : null;
      if (s && !signal.aborted) destino.textContent = textoSala(s);
    }).catch(() => { /* queda el número de sala */ });

    const dato = (nombre, valor, clase) => [h("dt", {}, nombre), h("dd", { class: clase }, valor ?? "—")];
    const general = tarjeta({ titulo: "Datos de la transferencia", clase: "tarjeta--ancha" });
    general.cuerpo.append(
      h("div", { class: "seccion" }, pasos(t.estado)),
      h("dl", { class: "ficha" },
        dato("Solicitud", t.num_solicitud, "mono"),
        dato("Fecha de confección", formatoFecha(t.fecha_confeccion)),
        dato("Estado", etiquetaEstado(t.estado)),
        dato("Origen", "Depósito central"),
        dato("Destino", destino)));

    const renglones = tarjeta({ titulo: "Vinos a transferir", clase: "tarjeta--ancha" });
    renglones.cuerpo.append(t.renglones.length
      ? tabla({
        descripcion: "Vinos de la transferencia",
        filas: t.renglones,
        columnas: [
          { titulo: "Código", valor: (r) => h("a", { href: hashDetalle(r.cod_vino, {}) }, r.cod_vino), clase: "mono" },
          { titulo: "Vino", valor: (r) => r.nombre_comercial },
          { titulo: "Botellas", valor: (r) => r.cantidad_botellas, clase: "num" },
        ],
      })
      : vacio(t.estado === "en_confeccion" ? "Todavía no se agregaron vinos." : "La transferencia no tiene vinos."));

    const bloques = [general.tarjeta, renglones.tarjeta];
    if (t.estado === "en_confeccion") bloques.push(bloqueAgregar(t), bloqueTerminar(t));
    else if (t.estado === "terminado") bloques.push(bloqueProcesar(t));
    else if (t.estado === "procesado") {
      const fin = tarjeta({ titulo: "Transferencia procesada", clase: "tarjeta--ancha" });
      fin.cuerpo.append(h("p", { class: "seccion seccion__ayuda" }, "La base ya movió el stock del depósito central a la sala. No admite más cambios."));
      bloques.push(fin.tarjeta);
    }
    cuerpo.replaceChildren(h("div", { class: "rejilla" }, bloques));
  }

  function bloqueAgregar(t) {
    const { tarjeta: el, cuerpo: caja } = tarjeta({
      titulo: "Agregar un vino",
      subtitulo: "Se agrega de a un vino. No hay forma de quitar ni modificar renglones: revisá antes de agregar.",
      clase: "tarjeta--ancha",
    });
    const zona = h("div", { class: "seccion" }, cargando("Cargando vinos…"));
    caja.append(zona);

    obtenerVinosParaSeleccion().then((vinos) => {
      if (signal.aborted) return;
      const selector = crearSelectorVino({ vinos, signal });
      const cantidad = h("input", {
        class: "campo__control", type: "number", min: 1, step: 1, inputmode: "numeric",
        placeholder: "Botellas", "aria-label": "Cantidad de botellas",
      });
      const errorCantidad = h("span", { class: "campo__error", "aria-live": "polite" });
      const agregar = h("button", { class: "boton", type: "submit" }, icono("mas"), "Agregar");
      const resultado = h("div", { class: "formulario__resultado", tabindex: "-1" });
      const formulario = h("form", { class: "agregar-renglon", novalidate: true },
        selector.lista,
        h("div", { class: "renglon__campos renglon__campos--agregar" }, selector.input, cantidad, agregar),
        selector.info, selector.error, errorCantidad, resultado);

      formulario.addEventListener("submit", (e) => {
        e.preventDefault();
        if (ocupada) return;
        resultado.replaceChildren();
        const { vino, error } = selector.leer();
        const cant = cantidad.value.trim();
        const errCant = !cant ? "Ingresá la cantidad de botellas." : !ENTERO_POSITIVO.test(cant) ? "La cantidad debe ser un número entero mayor que 0." : "";
        errorCantidad.textContent = errCant;
        cantidad.toggleAttribute("aria-invalid", Boolean(errCant));
        // Un vino aparece una sola vez por transferencia (UNIQUE uq_renglon_transferencia_vino)
        const repetido = !error && t.renglones.some((r) => r.id_vino === vino.id_vino);
        if (repetido) {
          selector.error.textContent = "Este vino ya está en la transferencia.";
          selector.input.setAttribute("aria-invalid", "true");
        }
        if (error || errCant || repetido) { (formulario.querySelector("[aria-invalid]") ?? selector.input).focus(); return; }
        operar({
          ejecutar: () => agregarRenglonTransferencia(t.num_solicitud, { id_vino: vino.id_vino, cantidad_botellas: Number(cant) }),
          exito: () => `${vino.cod_vino} agregado (${cant} botellas).`,
          resultado,
          botones: [agregar],
        });
      });
      zona.replaceChildren(formulario);
    }).catch((error) => {
      if (signal.aborted) return;
      zona.replaceChildren(h("p", { class: "formulario__nota" }, "No se pudieron cargar los vinos."),
        mensajeError(error, { onReintentar: () => pintar(t) }));
    });
    return el;
  }

  function bloqueTerminar(t) {
    const { tarjeta: el, cuerpo: caja } = tarjeta({ titulo: "Terminar la transferencia", clase: "tarjeta--ancha" });
    const resultado = h("div", { class: "formulario__resultado", tabindex: "-1" });
    caja.append(h("div", { class: "seccion" },
      accionConfirmada({
        texto: "Terminar transferencia", icono: "ok", confirmar: "Sí, terminar",
        advertencias: [
          "Al terminarla ya no se podrán agregar vinos (RN-12).",
          t.renglones.length ? null : "Atención: la transferencia no tiene vinos y la base no permite procesar una transferencia sin renglones.",
        ],
        alConfirmar: ({ si, no }) => operar({
          ejecutar: () => terminarTransferencia(t.num_solicitud),
          exito: () => "Transferencia terminada. Ya se puede procesar.",
          resultado, botones: [si, no],
        }),
      }),
      resultado));
    return el;
  }

  function bloqueProcesar(t) {
    const { tarjeta: el, cuerpo: caja } = tarjeta({ titulo: "Procesar la transferencia", clase: "tarjeta--ancha" });
    const resultado = h("div", { class: "formulario__resultado", tabindex: "-1" });
    caja.append(h("div", { class: "seccion" },
      h("p", { class: "seccion__ayuda" }, "Procesar mueve el stock del depósito central a la sala. La base controla que alcance el stock de cada vino; si no alcanza, no se mueve nada."),
      accionConfirmada({
        texto: "Procesar transferencia", icono: "transferencias", confirmar: "Sí, procesar",
        advertencias: ["Se descontará el stock del depósito central y se sumará a la sala. La operación no se puede deshacer."],
        alConfirmar: ({ si, no }) => operar({
          ejecutar: () => procesarTransferencia(t.num_solicitud),
          exito: () => "Transferencia procesada: la base movió el stock a la sala.",
          resultado, botones: [si, no],
        }),
      }),
      resultado));
    return el;
  }

  cargar();
}
