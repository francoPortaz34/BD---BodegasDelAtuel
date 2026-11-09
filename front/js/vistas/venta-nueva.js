// Registro de una venta (#/ventas/nueva).
//
// Contrato real (POST /comprobantes): { num_comprobante, id_cliente, id_sala,
// renglones: [{ id_vino, cantidad }] }. La fecha la pone la base.
// El front NO calcula precios, descuentos, subtotales, totales ni stock, ni
// decide si la venta puede hacerse: lo resuelve la base (RN-01, RN-06, RN-08,
// RN-09) y sus mensajes se muestran tal cual. Si la API rechaza la venta, no se
// guarda nada (una sola transacción) y el formulario queda como estaba.
//
// GET /vinos no devuelve id_vino: al elegir cada vino se pide GET /vinos/{cod}.
import { obtenerSalas } from "../api/catalogos.js";
import { ApiError } from "../api/cliente.js";
import { buscarClientes } from "../api/clientes.js";
import { registrarVenta } from "../api/ventas.js";
import { obtenerVino, obtenerVinosParaSeleccion } from "../api/vinos.js";
import { aviso, dejarAviso } from "../componentes/avisos.js";
import { encabezadoPagina, tarjeta } from "../componentes/contenido.js";
import { cargando, mensajeError, vacio } from "../componentes/estados.js";
import { campoValidable } from "../componentes/formulario.js";
import { crearPaginacion } from "../componentes/paginacion.js";
import { h, icono } from "../dom.js";
import { formatoPrecio } from "./vinos-comun.js";
import { hashVenta, recordarVenta, textoSala } from "./ventas-comun.js";

const TAMANIO_CLIENTES = 8;
const ENTERO_POSITIVO = /^[1-9]\d{0,8}$/;   // cantidad > 0 (CHECK ck_detalle_cantidad), INTEGER

// ---------- Cliente: búsqueda paginada en GET /clientes ----------

function selectorCliente(signal) {
  let elegido = null;
  let secuencia = 0;
  let consulta = null;

  const criterio = h("select", { class: "campo__control", "aria-label": "Buscar por" },
    h("option", { value: "nombre" }, "Nombre o razón social"),
    h("option", { value: "documento" }, "N° de documento"));
  const texto = h("input", {
    class: "campo__control", type: "search", autocomplete: "off",
    placeholder: "Ej.: Gomez o 26833481", "aria-label": "Texto a buscar",
  });
  const buscar = h("button", { class: "boton boton--secundario", type: "button" }, icono("buscar"), "Buscar");
  const resultados = h("div", { class: "resultados", "aria-live": "polite" });
  const paginacion = crearPaginacion({ alIr: (pagina) => consultar(pagina) });
  const error = h("p", { class: "campo__error", "aria-live": "polite" });
  const seleccion = h("div", { class: "seleccion", hidden: true });
  const buscador = h("div", { class: "buscador" },
    h("div", { class: "buscador__fila" }, criterio, texto, buscar),
    resultados, paginacion.el);

  async function consultar(pagina = 1) {
    const valor = texto.value.trim();
    if (!valor) {
      error.textContent = "Escribí un nombre o un documento para buscar.";
      texto.focus();
      return;
    }
    error.textContent = "";
    consulta = { [criterio.value]: valor };
    const numero = ++secuencia;
    resultados.replaceChildren(cargando("Buscando clientes…"));
    paginacion.ocultar();
    try {
      const datos = await buscarClientes({ ...consulta, pagina, tamanio: TAMANIO_CLIENTES }, { signal });
      if (numero !== secuencia || signal.aborted) return;   // llegó tarde: hay una búsqueda más nueva
      if (!Array.isArray(datos?.clientes)) {
        throw new ApiError("La API devolvió una respuesta con un formato inesperado.", { tipo: "formato" });
      }
      const { clientes } = datos;
      if (!clientes.length) {
        resultados.replaceChildren(vacio(pagina > 1 ? "No hay más clientes." : "No hay clientes que coincidan con la búsqueda."));
        if (pagina > 1) paginacion.actualizar({ pagina, haySiguiente: false });
        return;
      }
      resultados.replaceChildren(h("ul", { class: "lista-clientes" }, clientes.map((c) =>
        h("li", {}, h("button", { class: "cliente", type: "button", onClick: () => elegir(c) },
          h("span", { class: "cliente__nombre" }, c.nombre_o_razon_social),
          h("span", { class: "cliente__detalle" },
            [`${c.tipo_documento ?? ""} ${c.num_documento ?? ""}`.trim(), c.tipo_cliente, `N° ${c.id_cliente}`].filter(Boolean).join(" · ")))))));
      // Sin total: una página incompleta es la última; una vacía al avanzar se informa
      paginacion.actualizar({ pagina, haySiguiente: clientes.length === TAMANIO_CLIENTES });
    } catch (e) {
      if (numero !== secuencia || signal.aborted || e?.name === "AbortError") return;
      resultados.replaceChildren(mensajeError(e, { onReintentar: () => consultar(pagina) }));
    }
  }

  function elegir(cliente) {
    elegido = cliente;
    error.textContent = "";
    seleccion.replaceChildren(
      h("div", { class: "seleccion__datos" },
        h("span", { class: "seleccion__titulo" }, cliente.nombre_o_razon_social),
        h("span", { class: "seleccion__detalle" },
          [`${cliente.tipo_documento ?? ""} ${cliente.num_documento ?? ""}`.trim(), cliente.tipo_cliente && `Tipo: ${cliente.tipo_cliente}`, `N° ${cliente.id_cliente}`].filter(Boolean).join(" · "))),
      h("button", { class: "boton boton--secundario boton--chico", type: "button", onClick: cambiar }, "Cambiar cliente"));
    seleccion.hidden = false;
    buscador.hidden = true;
    seleccion.querySelector("button").focus();
  }

  function cambiar() {
    elegido = null;
    seleccion.hidden = true;
    buscador.hidden = false;
    texto.focus();
  }

  buscar.addEventListener("click", () => consultar(1));
  // Enter en el buscador busca (no envía la venta)
  texto.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); consultar(1); } });

  const el = h("div", {},
    h("p", { class: "seccion__ayuda" }, "El descuento lo aplica la base según el tipo de cliente."),
    seleccion, buscador, error);

  return {
    el,
    leer: () => {
      if (elegido) return elegido.id_cliente;
      error.textContent = "Buscá y elegí el cliente de la venta.";
      return null;
    },
    foco: () => (elegido ? null : texto),
  };
}

// ---------- Renglones: vino + cantidad ----------

function crearRenglones(vinos, signal) {
  const porCodigo = new Map(vinos.map((v) => [String(v.cod_vino).toUpperCase(), v]));
  const idLista = `vinos-${Math.random().toString(36).slice(2)}`;
  const lista = h("datalist", { id: idLista },
    vinos.map((v) => h("option", { value: v.cod_vino },
      [v.nombre_comercial, v.anada, v.presentacion_ml && `${v.presentacion_ml} ml`].filter(Boolean).join(" · "))));
  const filas = [];
  const contenedor = h("div", { class: "renglones" });
  const errorGeneral = h("p", { class: "campo__error", "aria-live": "polite" });
  const agregar = h("button", { class: "boton boton--secundario", type: "button" }, icono("mas"), "Agregar vino");

  function actualizarBotones() {
    for (const f of filas) f.quitar.disabled = filas.length === 1;
  }

  function agregarFila() {
    const codigo = h("input", {
      class: "campo__control", type: "text", list: idLista, autocomplete: "off",
      placeholder: "Código del vino (ej.: V0001)", "aria-label": "Vino (código)",
    });
    const cantidad = h("input", {
      class: "campo__control", type: "number", min: 1, step: 1, inputmode: "numeric",
      placeholder: "Cant.", "aria-label": "Cantidad de botellas",
    });
    const quitar = h("button", { class: "boton boton--icono", type: "button", title: "Quitar este vino", "aria-label": "Quitar este vino" }, icono("quitar"));
    const info = h("span", { class: "renglon__info" });
    const error = h("span", { class: "campo__error", "aria-live": "polite" });
    const el = h("div", { class: "renglon" },
      h("div", { class: "renglon__campos" }, codigo, cantidad, quitar), info, error);
    // estado: "vacio" | "buscando" | "ok" | "error"
    const fila = { el, codigo, cantidad, quitar, info, error, estado: "vacio", id_vino: null, cod: null, secuencia: 0 };
    filas.push(fila);
    contenedor.append(el);

    codigo.addEventListener("change", () => resolver(fila));
    quitar.addEventListener("click", () => {
      filas.splice(filas.indexOf(fila), 1);
      el.remove();
      actualizarBotones();
      (filas.at(-1)?.codigo ?? agregar).focus();
    });
    actualizarBotones();
    return fila;
  }

  /** Obtiene el id_vino del vino elegido con GET /vinos/{cod} (solo para ese vino). */
  async function resolver(fila) {
    const cod = fila.codigo.value.trim().toUpperCase();
    const numero = ++fila.secuencia;
    fila.id_vino = null;
    fila.error.textContent = "";
    fila.codigo.removeAttribute("aria-invalid");
    if (!cod) { fila.estado = "vacio"; fila.cod = null; fila.info.textContent = ""; return; }
    const vino = porCodigo.get(cod);
    if (!vino) {
      fila.estado = "error"; fila.cod = null; fila.info.textContent = "";
      fila.error.textContent = "No hay un vino con ese código en el catálogo.";
      fila.codigo.setAttribute("aria-invalid", "true");
      return;
    }
    fila.codigo.value = vino.cod_vino;
    fila.cod = vino.cod_vino;
    fila.estado = "buscando";
    fila.info.textContent = `${vino.nombre_comercial} · verificando…`;
    try {
      const detalle = await obtenerVino(vino.cod_vino, { signal });
      if (numero !== fila.secuencia || signal.aborted) return;
      if (!Number.isInteger(detalle?.id_vino)) {
        throw new ApiError("La API devolvió el vino sin su identificador.", { tipo: "formato" });
      }
      fila.id_vino = detalle.id_vino;
      fila.estado = "ok";
      // Precio vigente solo informativo: el de la venta lo fija la base (RN-01)
      fila.info.textContent = [detalle.nombre_comercial, detalle.anada, `${detalle.presentacion_ml} ml`,
        `precio vigente ${formatoPrecio(detalle.precio_venta)}`].filter(Boolean).join(" · ");
    } catch (e) {
      if (numero !== fila.secuencia || signal.aborted || e?.name === "AbortError") return;
      fila.estado = "error";
      fila.info.textContent = "";
      fila.error.textContent = `No se pudo verificar el vino: ${e.message}`;
      fila.codigo.setAttribute("aria-invalid", "true");
    }
  }

  agregar.addEventListener("click", () => agregarFila().codigo.focus());
  agregarFila();

  /** [{id_vino, cantidad}] o null si hay errores (y los muestra). */
  function leer() {
    errorGeneral.textContent = "";
    let valido = true;
    const vistos = new Set();
    for (const f of filas) {
      const errores = [];
      if (f.estado === "vacio") errores.push("Elegí un vino.");
      else if (f.estado === "buscando") errores.push("Esperá a que se verifique el vino.");
      else if (f.estado === "error") errores.push(f.error.textContent || "Vino inválido.");
      else if (vistos.has(f.cod)) errores.push("Este vino ya está en la venta: modificá la cantidad del otro renglón.");
      if (f.cod) vistos.add(f.cod);
      const cant = f.cantidad.value.trim();
      const errorCantidad = !cant ? "Ingresá la cantidad." : !ENTERO_POSITIVO.test(cant) ? "La cantidad debe ser un número entero mayor que 0." : "";
      if (errorCantidad) errores.push(errorCantidad);
      f.error.textContent = errores.join(" ");
      f.codigo.toggleAttribute("aria-invalid", f.estado !== "ok" || errores.some((x) => x.startsWith("Este vino")));
      f.cantidad.toggleAttribute("aria-invalid", Boolean(errorCantidad));
      if (errores.length) valido = false;
    }
    if (!filas.length) { errorGeneral.textContent = "Agregá al menos un vino."; valido = false; }
    if (!valido) return null;
    return filas.map((f) => ({ id_vino: f.id_vino, cantidad: Number(f.cantidad.value.trim()) }));
  }

  const el = h("div", {},
    h("p", { class: "seccion__ayuda" },
      "Escribí o elegí el código de cada vino. El stock de la sala lo controla la base al registrar (RN-09): si no alcanza, la venta se rechaza con su mensaje."),
    lista, contenedor, errorGeneral, h("div", { class: "renglones__acciones" }, agregar));
  return { el, leer, primerInvalido: () => contenedor.querySelector("[aria-invalid]") ?? (filas.length ? null : agregar) };
}

// ---------- Formulario ----------

function formularioVenta({ salas, vinos, signal }) {
  const numero = campoValidable({
    etiqueta: "Número de comprobante", requerido: true,
    control: h("input", { class: "campo__control", type: "text", maxlength: 20, autocomplete: "off", placeholder: "Ej.: C-00090001" }),
    ayuda: "La API no lo asigna: ingresalo (hasta 20 caracteres, único).",
  });
  const sala = campoValidable({
    etiqueta: "Sala de venta", requerido: true, clase: "campo--doble",
    control: h("select", { class: "campo__control" },
      h("option", { value: "" }, "Elegí la sala"),
      ...salas.map((s) => h("option", { value: String(s.id_sala) },
        `${textoSala(s)}${s.dia_cierre_semanal ? ` (cierra ${s.dia_cierre_semanal})` : ""}`))),
  });
  const cliente = selectorCliente(signal);
  const renglones = crearRenglones(vinos, signal);

  const comprobante = tarjeta({ titulo: "Comprobante", subtitulo: "La fecha la registra la base (día de hoy)." });
  comprobante.cuerpo.append(h("div", { class: "formulario__campos" }, numero.el, sala.el));
  const tarjetaCliente = tarjeta({ titulo: "Cliente" });
  tarjetaCliente.cuerpo.append(h("div", { class: "seccion" }, cliente.el));
  const tarjetaVinos = tarjeta({ titulo: "Vinos", subtitulo: "Precios, descuentos y totales los calcula la base al registrar." });
  tarjetaVinos.cuerpo.append(h("div", { class: "seccion" }, renglones.el));

  const grupo = h("fieldset", { class: "formulario__grupo" },
    h("legend", { class: "visualmente-oculto" }, "Datos de la venta"),
    comprobante.tarjeta, tarjetaCliente.tarjeta, tarjetaVinos.tarjeta);
  const resumen = h("div", { class: "formulario__resumen", tabindex: "-1" });
  const resultado = h("div", { class: "formulario__resultado", tabindex: "-1" });
  const registrar = h("button", { class: "boton", type: "submit" }, icono("ok"), "Registrar venta");
  const cancelar = h("a", { class: "boton boton--secundario", href: "#/ventas" }, "Cancelar");
  const formulario = h("form", { class: "formulario", novalidate: true },
    h("p", { class: "formulario__nota" }, "Los campos marcados con * son obligatorios."),
    resumen, grupo, resultado, h("div", { class: "formulario__acciones" }, registrar, cancelar));

  const validarNumero = (v) => (!v ? "Ingresá el número de comprobante." : v.length > 20 ? "Hasta 20 caracteres." : "");
  numero.control.addEventListener("blur", () => { if (numero.control.value) numero.error(validarNumero(numero.control.value.trim())); });
  sala.control.addEventListener("change", () => sala.error(sala.control.value ? "" : "Elegí la sala."));

  function ocupado(si) {
    grupo.disabled = si;   // deshabilita también el buscador de clientes y los renglones
    registrar.disabled = si;
    registrar.setAttribute("aria-busy", String(si));
    registrar.replaceChildren(si ? h("span", { class: "spinner spinner--chico", "aria-hidden": "true" }) : icono("ok"),
      si ? "Registrando…" : "Registrar venta");
  }

  const mostrar = (...nodos) => {
    resultado.replaceChildren(...nodos);
    resultado.scrollIntoView({ block: "nearest" });
    resultado.focus({ preventScroll: true });
  };

  let enviando = false;
  formulario.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    if (enviando) return;   // sin envíos duplicados (doble clic, Enter repetido)
    resumen.replaceChildren();
    resultado.replaceChildren();

    const num = numero.control.value.trim();
    const errNumero = validarNumero(num);
    numero.error(errNumero);
    const errSala = sala.control.value ? "" : "Elegí la sala.";
    sala.error(errSala);
    const idCliente = cliente.leer();
    const lineas = renglones.leer();
    if (errNumero || errSala || idCliente === null || !lineas) {
      resumen.replaceChildren(aviso("Revisá los datos marcados antes de registrar la venta.", "advertencia"));
      (errNumero ? numero.control : errSala ? sala.control : cliente.foco() ?? renglones.primerInvalido() ?? resumen).focus();
      return;
    }

    enviando = true;
    ocupado(true);
    let venta;
    try {
      // Sin signal: una vez enviada, la venta se completa en el servidor aunque se salga de la pantalla
      venta = await registrarVenta({ num_comprobante: num, id_cliente: idCliente, id_sala: Number(sala.control.value), renglones: lineas });
    } catch (error) {
      enviando = false;
      if (signal.aborted) return;
      ocupado(false);
      const extra = error?.tipo === "red" || error?.tipo === "tiempo"
        ? h("p", { class: "detalle__nota" }, `No se sabe si la venta llegó a registrarse. Antes de reintentar, consultá el comprobante ${num} en Ventas.`)
        : null;
      mostrar(...[mensajeError(error), extra].filter(Boolean));
      return;
    }

    // 201: la venta quedó registrada en la base
    const nro = typeof venta?.num_comprobante === "string" ? venta.num_comprobante : num;
    recordarVenta({ ...(venta && typeof venta === "object" ? venta : {}), num_comprobante: nro });
    if (signal.aborted) return;
    dejarAviso(`Venta ${nro} registrada correctamente.`);
    location.hash = hashVenta(nro);
  });

  return formulario;
}

// ---------- Vista ----------

export function vistaNuevaVenta(contenedor, { signal }) {
  const cuerpo = h("div", { class: "formulario-venta" });
  contenedor.replaceChildren(
    encabezadoPagina({
      titulo: "Nueva venta",
      descripcion: "Elegí la sala, el cliente y los vinos. La base valida el stock y calcula precios, descuentos y totales.",
      acciones: h("a", { class: "boton boton--secundario", href: "#/ventas" }, icono("anterior"), "Volver a ventas"),
    }),
    cuerpo);

  async function cargar(forzar = false) {
    cuerpo.replaceChildren(cargando("Cargando salas y vinos…"));
    try {
      // Sin signal: son cachés compartidas (catalogos.js / vinos.js)
      const [salas, vinos] = await Promise.all([
        obtenerSalas({ forzar }).catch((e) => { e.recurso = "las salas"; throw e; }),
        obtenerVinosParaSeleccion({ forzar }).catch((e) => { e.recurso = "los vinos"; throw e; }),
      ]);
      if (!Array.isArray(salas)) throw Object.assign(new ApiError("La API devolvió las salas con un formato inesperado.", { tipo: "formato" }), { recurso: "las salas" });
      if (signal.aborted) return;
      cuerpo.replaceChildren(formularioVenta({ salas, vinos, signal }));
    } catch (error) {
      if (signal.aborted) return;
      cuerpo.replaceChildren(
        h("p", { class: "formulario__nota" }, `No se pudieron cargar ${error?.recurso ?? "los datos del formulario"}.`),
        mensajeError(error, { onReintentar: () => cargar(true) }));
    }
  }
  cargar();
}
