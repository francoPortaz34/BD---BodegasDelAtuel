// Alta (#/vinos/nuevo) y edición (#/vinos/:cod/editar) de vinos: ficha,
// composición de cepas y maridajes. Bodegas, cepas y maridajes salen de la API.
//
// Contrato real de la API:
// - POST /vinos   ficha + cod_vino + cepas. NO admite maridajes.
// - PUT  /vinos/{cod}  ficha (obligatoria) + cepas y maridajes opcionales; una
//   lista enviada reemplaza la actual. El código no se puede cambiar.
// En el alta, si se eligieron maridajes, después del POST se hace un PUT con la
// misma ficha y los maridajes (no es atómico: si el PUT falla, el vino queda
// creado sin maridajes y se avisa con el error de la API).
//
// Las reglas de negocio las decide la base: en particular la suma 100 de los
// porcentajes de corte (RN-05) NO se calcula acá; si no se cumple, se muestra
// el mensaje de la base tal cual.
import { obtenerBodegas, obtenerCepas, obtenerMaridajes } from "../api/catalogos.js";
import { ApiError } from "../api/cliente.js";
import { crearVino, modificarVino, obtenerVino, PRESENTACIONES_ML, TIPOS_VINO } from "../api/vinos.js";
import { aviso, dejarAviso } from "../componentes/avisos.js";
import { encabezadoPagina, tarjeta } from "../componentes/contenido.js";
import { cargando, mensajeError } from "../componentes/estados.js";
import { campoValidable } from "../componentes/formulario.js";
import { h, icono } from "../dom.js";
import { capital, hashCatalogo, hashDetalle, hashEdicion, leerBusqueda } from "./vinos-comun.js";

// ---------- Validación de formato (mensajes claros antes de enviar) ----------
// Reflejan los tipos y CHECK de la tabla vino (001_esquema.sql, 002_constraints.sql).
// La API y la base siguen siendo la autoridad: lo que pase acá igual lo valida la base.

const DECIMAL_2 = /^\d+(\.\d{1,2})?$/;

const validar = {
  cod: (v) => (!v ? "Ingresá el código del vino."
    : v.length > 20 ? "El código admite hasta 20 caracteres." : ""),
  nombre: (v) => (!v ? "Ingresá el nombre comercial."
    : v.length > 100 ? "El nombre admite hasta 100 caracteres." : ""),
  tipo: (v) => (TIPOS_VINO.includes(v) ? "" : "Elegí el tipo de vino."),
  anada: (v) => (!v ? "Ingresá la añada."
    : !/^\d{4}$/.test(v) || Number(v) < 1900 || Number(v) > 2100 ? "La añada debe ser un año entre 1900 y 2100." : ""),
  presentacion: (v) => (PRESENTACIONES_ML.includes(Number(v)) ? "" : "Elegí la presentación."),
  graduacion: (v) => (!v ? "Ingresá la graduación alcohólica."
    : !DECIMAL_2.test(v) ? "Usá un número con hasta 2 decimales (por ejemplo 13.5)."
      : Number(v) < 5 || Number(v) > 20 ? "La graduación debe estar entre 5 y 20 %." : ""),
  precio: (v) => (!v ? "Ingresá el precio de venta."
    : !DECIMAL_2.test(v) ? "Usá un número con hasta 2 decimales (por ejemplo 12500.50)."
      : Number(v) <= 0 ? "El precio debe ser mayor que cero."
        : Number(v) >= 1e10 ? "El precio es demasiado grande." : ""),
  bodega: (v) => (v ? "" : "Elegí la bodega."),
  porcentaje: (v) => (!v ? "Ingresá el porcentaje."
    : !DECIMAL_2.test(v) ? "Hasta 2 decimales."
      : Number(v) <= 0 || Number(v) > 100 ? "Debe ser mayor que 0 y hasta 100." : ""),
};

// ---------- Carga de datos ----------

/** Asocia a cada petición un nombre para informar QUÉ no se pudo cargar. */
const conNombre = (promesa, nombre) => promesa.catch((error) => {
  if (error && typeof error === "object") error.recurso = nombre;
  throw error;
});

// ---------- Composición de cepas ----------

function crearComposicion(cepas, iniciales) {
  const filas = [];
  const lista = h("div", { class: "cortes" });
  const errorGeneral = h("p", { class: "campo__error", "aria-live": "polite" });
  const agregar = h("button", { class: "boton boton--secundario", type: "button" }, icono("mas"), "Agregar cepa");

  /** Cada cepa puede elegirse una sola vez: se deshabilita en las demás filas. */
  function sincronizar() {
    const elegidas = new Set(filas.map((f) => f.select.value).filter(Boolean));
    for (const f of filas) {
      for (const op of f.select.options) {
        op.disabled = Boolean(op.value) && op.value !== f.select.value && elegidas.has(op.value);
      }
      f.quitar.disabled = filas.length === 1;
    }
    agregar.disabled = filas.length >= cepas.length;
    lista.classList.toggle("cortes--vacia", filas.length === 0);
  }

  function agregarFila({ id_cepa = "", porcentaje_corte = "" } = {}) {
    const select = h("select", { class: "campo__control", "aria-label": "Cepa" },
      h("option", { value: "" }, "Elegí una cepa"),
      ...cepas.map((c) => h("option", { value: String(c.id_cepa) }, c.tipo ? `${c.nombre} (${c.tipo})` : c.nombre)));
    select.value = String(id_cepa);
    const porcentaje = h("input", {
      class: "campo__control", type: "number", inputmode: "decimal", min: "0.01", max: "100", step: "0.01",
      placeholder: "%", "aria-label": "Porcentaje de corte",
      value: porcentaje_corte === "" || porcentaje_corte == null ? "" : String(porcentaje_corte),
    });
    const error = h("span", { class: "campo__error", "aria-live": "polite" });
    const quitar = h("button", {
      class: "boton boton--icono", type: "button", title: "Quitar esta cepa", "aria-label": "Quitar esta cepa",
    }, icono("quitar"));
    const el = h("div", { class: "corte" },
      h("div", { class: "corte__campos" }, select,
        h("div", { class: "corte__porcentaje" }, porcentaje, h("span", { "aria-hidden": "true" }, "%")),
        quitar),
      error);
    const fila = { el, select, porcentaje, quitar, error };
    filas.push(fila);
    lista.append(el);

    select.addEventListener("change", sincronizar);
    quitar.addEventListener("click", () => {
      filas.splice(filas.indexOf(fila), 1);
      el.remove();
      sincronizar();
      (filas.at(-1)?.select ?? agregar).focus();
    });
    sincronizar();
    return fila;
  }

  agregar.addEventListener("click", () => agregarFila().select.focus());
  (iniciales.length ? iniciales : [{}]).forEach(agregarFila);

  /** Devuelve [{id_cepa, porcentaje_corte}] o null si hay errores (y los muestra). */
  function leer() {
    errorGeneral.textContent = "";
    let valido = true;
    const vistas = new Set();
    for (const f of filas) {
      const errorCepa = !f.select.value ? "Elegí una cepa."
        : vistas.has(f.select.value) ? "Esta cepa ya está en la composición." : "";
      const errorPorcentaje = validar.porcentaje(f.porcentaje.value.trim());
      vistas.add(f.select.value);
      f.error.textContent = [errorCepa, errorPorcentaje].filter(Boolean).join(" ");
      f.select.toggleAttribute("aria-invalid", Boolean(errorCepa));
      f.porcentaje.toggleAttribute("aria-invalid", Boolean(errorPorcentaje));
      if (errorCepa || errorPorcentaje) valido = false;
    }
    if (filas.length === 0) {
      errorGeneral.textContent = "Agregá al menos una cepa.";
      valido = false;
    }
    if (!valido) return null;
    // El porcentaje se envía como texto: la API lo recibe como Decimal exacto
    return filas.map((f) => ({ id_cepa: Number(f.select.value), porcentaje_corte: f.porcentaje.value.trim() }));
  }

  const primerInvalido = () => lista.querySelector("[aria-invalid]") ?? (filas.length ? null : agregar);

  const el = h("div", {},
    h("p", { class: "seccion__ayuda" },
      "Agregá cada cepa con su porcentaje de corte. La base controla que los porcentajes sumen exactamente 100 (RN-05)."),
    lista, errorGeneral, h("div", { class: "cortes__acciones" }, agregar));
  return { el, leer, primerInvalido };
}

// ---------- Maridajes ----------

function crearMaridajes(maridajes, seleccionados) {
  const elegidos = new Set(seleccionados.map(String));
  const casillas = maridajes.map((m) => {
    const casilla = h("input", { type: "checkbox", value: String(m.id_maridaje), checked: elegidos.has(String(m.id_maridaje)) });
    return {
      casilla,
      el: h("label", { class: "opcion" }, casilla,
        h("span", { class: "opcion__texto" }, m.nombre,
          m.temperatura_sugerida != null && h("span", { class: "opcion__detalle" }, ` · ${m.temperatura_sugerida} °C`))),
    };
  });
  const el = h("fieldset", { class: "opciones" },
    h("legend", { class: "visualmente-oculto" }, "Maridajes recomendados"),
    casillas.length ? casillas.map((c) => c.el) : h("p", { class: "seccion__ayuda" }, "No hay maridajes registrados."));
  // Casillas: cada maridaje puede marcarse una sola vez (sin duplicados)
  const leer = () => casillas.filter((c) => c.casilla.checked).map((c) => Number(c.casilla.value));
  return { el, leer };
}

// ---------- Formulario ----------

function formularioVino({ modo, vino, catalogos, busqueda, signal }) {
  const esAlta = modo === "alta";
  const { bodegas, cepas, maridajes } = catalogos;
  const texto = (props) => h("input", { class: "campo__control", type: "text", autocomplete: "off", ...props });
  const numero = (props) => h("input", { class: "campo__control", type: "number", ...props });
  const selector = (opciones, valor, vacio) => {
    const s = h("select", { class: "campo__control" },
      h("option", { value: "" }, vacio), ...opciones.map((o) => h("option", { value: o.valor }, o.texto)));
    s.value = valor == null ? "" : String(valor);
    return s;
  };

  const campos = {
    cod: campoValidable({
      etiqueta: "Código", requerido: esAlta,
      control: texto({ maxlength: 20, value: vino?.cod_vino ?? "", readonly: !esAlta, placeholder: "Ej.: V0500" }),
      ayuda: esAlta ? "Hasta 20 caracteres. No se puede modificar después." : "El código no se puede modificar.",
    }),
    nombre: campoValidable({
      etiqueta: "Nombre comercial", requerido: true, clase: "campo--doble",
      control: texto({ maxlength: 100, value: vino?.nombre_comercial ?? "" }),
    }),
    tipo: campoValidable({
      etiqueta: "Tipo", requerido: true,
      control: selector(TIPOS_VINO.map((t) => ({ valor: t, texto: capital(t) })), vino?.tipo, "Elegí el tipo"),
    }),
    anada: campoValidable({
      etiqueta: "Añada", requerido: true,
      control: numero({ min: 1900, max: 2100, step: 1, inputmode: "numeric", value: vino?.anada ?? "", placeholder: "Ej.: 2022" }),
    }),
    presentacion: campoValidable({
      etiqueta: "Presentación", requerido: true,
      control: selector(PRESENTACIONES_ML.map((p) => ({ valor: p, texto: `${p} ml` })), vino?.presentacion_ml, "Elegí la presentación"),
    }),
    graduacion: campoValidable({
      etiqueta: "Graduación alcohólica (%)", requerido: true,
      control: numero({ min: 5, max: 20, step: "0.01", inputmode: "decimal", value: vino?.graduacion_alcoholica ?? "", placeholder: "Ej.: 13.5" }),
      ayuda: "Entre 5 y 20.",
    }),
    precio: campoValidable({
      etiqueta: "Precio de venta ($)", requerido: true,
      control: numero({ min: "0.01", step: "0.01", inputmode: "decimal", value: vino?.precio_venta ?? "", placeholder: "Ej.: 12500" }),
      ayuda: esAlta ? "Mayor que cero." : "Mayor que cero. Si cambia, la base registra la auditoría del precio.",
    }),
    bodega: campoValidable({
      etiqueta: "Bodega", requerido: true, clase: "campo--doble",
      control: selector(bodegas.map((b) => ({ valor: b.id_bodega, texto: b.razon_social })), vino?.id_bodega, "Elegí la bodega"),
    }),
  };

  const composicion = crearComposicion(cepas, (vino?.cepas ?? []).map((c) => ({ id_cepa: c.id_cepa, porcentaje_corte: c.porcentaje_corte })));
  const seleccionMaridajes = crearMaridajes(maridajes, (vino?.maridajes ?? []).map((m) => m.id_maridaje));

  const resumenErrores = h("div", { class: "formulario__resumen", tabindex: "-1" });
  const resultado = h("div", { class: "formulario__resultado", tabindex: "-1" });
  const guardar = h("button", { class: "boton", type: "submit" }, icono("ok"), esAlta ? "Registrar vino" : "Guardar cambios");
  const destinoCancelar = esAlta ? hashCatalogo(busqueda) : hashDetalle(vino.cod_vino, busqueda);
  const cancelar = h("a", { class: "boton boton--secundario", href: destinoCancelar }, "Cancelar");

  const tarjetaDatos = tarjeta({ titulo: "Datos generales" });
  tarjetaDatos.cuerpo.append(h("div", { class: "formulario__campos" }, Object.values(campos).map((c) => c.el)));
  const tarjetaCepas = tarjeta({ titulo: "Composición de cepas" });
  tarjetaCepas.cuerpo.append(h("div", { class: "seccion" }, composicion.el));
  const tarjetaMaridajes = tarjeta({
    titulo: "Maridajes",
    subtitulo: esAlta ? "Opcional. Se guardan después de registrar el vino." : "Opcional. Marcá los recomendados para este vino.",
  });
  tarjetaMaridajes.cuerpo.append(h("div", { class: "seccion" }, seleccionMaridajes.el));

  const grupo = h("fieldset", { class: "formulario__grupo" },
    h("legend", { class: "visualmente-oculto" }, esAlta ? "Datos del vino nuevo" : "Datos del vino"),
    tarjetaDatos.tarjeta, tarjetaCepas.tarjeta, tarjetaMaridajes.tarjeta);

  const formulario = h("form", { class: "formulario", novalidate: true },
    h("p", { class: "formulario__nota" }, "Los campos marcados con * son obligatorios."),
    resumenErrores, grupo, resultado,
    h("div", { class: "formulario__acciones" }, guardar, cancelar));

  // Validación al salir de cada campo, para avisar antes de enviar
  const validacion = { cod: "cod", nombre: "nombre", tipo: "tipo", anada: "anada", presentacion: "presentacion", graduacion: "graduacion", precio: "precio", bodega: "bodega" };
  for (const [clave, regla] of Object.entries(validacion)) {
    const c = campos[clave];
    if (clave === "cod" && !esAlta) continue;
    const revisar = () => c.error(validar[regla](c.control.value.trim()));
    c.control.addEventListener("blur", () => { if (c.control.value !== "") revisar(); });
    c.control.addEventListener("change", revisar);
  }

  function leer() {
    let errores = 0;
    for (const [clave, regla] of Object.entries(validacion)) {
      if (clave === "cod" && !esAlta) continue;
      const msg = validar[regla](campos[clave].control.value.trim());
      campos[clave].error(msg);
      if (msg) errores++;
    }
    const cortes = composicion.leer();
    if (!cortes) errores++;
    if (errores) return null;
    return {
      cod: campos.cod.control.value.trim(),
      ficha: {
        nombre_comercial: campos.nombre.control.value.trim(),
        tipo: campos.tipo.control.value,
        anada: Number(campos.anada.control.value),
        presentacion_ml: Number(campos.presentacion.control.value),
        // Decimales como texto: la API los recibe como Decimal exacto
        graduacion_alcoholica: campos.graduacion.control.value.trim(),
        precio_venta: campos.precio.control.value.trim(),
        id_bodega: Number(campos.bodega.control.value),
      },
      cepas: cortes,
      maridajes: seleccionMaridajes.leer(),
    };
  }

  function ocupado(si) {
    grupo.disabled = si;
    guardar.disabled = si;
    guardar.setAttribute("aria-busy", String(si));
    guardar.replaceChildren(si ? h("span", { class: "spinner spinner--chico", "aria-hidden": "true" }) : icono("ok"),
      si ? "Guardando…" : esAlta ? "Registrar vino" : "Guardar cambios");
  }

  function mostrarResultado(...nodos) {
    resultado.replaceChildren(...nodos);
    resultado.scrollIntoView({ block: "nearest" });
    resultado.focus({ preventScroll: true });
  }

  let enviando = false;
  let bloqueado = false;   // alta registrada a medias: el formulario ya no se reenvía
  formulario.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    if (enviando) return;   // evita envíos duplicados (doble clic, Enter repetido)
    resultado.replaceChildren();
    resumenErrores.replaceChildren();

    const datos = leer();
    if (!datos) {
      resumenErrores.replaceChildren(aviso("Revisá los campos marcados antes de guardar.", "advertencia"));
      (formulario.querySelector("[aria-invalid]") ?? composicion.primerInvalido() ?? resumenErrores).focus();
      return;
    }

    enviando = true;
    ocupado(true);
    try {
      if (esAlta) await registrar(datos);
      else await actualizar(datos);
    } finally {
      if (!bloqueado) {
        enviando = false;
        if (!signal.aborted) ocupado(false);
      }
    }
  });

  // Las peticiones de guardado no se cancelan al salir de la pantalla: una vez
  // enviada, la operación se completa en el servidor; solo se deja de dibujar.
  async function registrar({ cod, ficha, cepas, maridajes }) {
    let creado;
    try {
      creado = await crearVino({ cod_vino: cod, ...ficha, cepas });
      if (!creado || typeof creado !== "object") {
        throw new ApiError("La API devolvió una respuesta con un formato inesperado.", { tipo: "formato" });
      }
    } catch (error) {
      if (!signal.aborted) mostrarResultado(mensajeError(error));
      return;
    }
    const codigo = creado.cod_vino ?? cod;

    if (maridajes.length) {
      try {
        await modificarVino(codigo, { ...ficha, maridajes });
      } catch (error) {
        if (signal.aborted) return;
        // El vino YA existe: no se puede volver a registrar. Se bloquea el
        // formulario y se ofrece completar los maridajes desde la edición.
        bloqueado = true;
        grupo.disabled = true;
        guardar.hidden = true;
        cancelar.hidden = true;
        mostrarResultado(
          aviso(`El vino ${codigo} se creó correctamente, pero los maridajes no se guardaron.`, "advertencia",
            h("div", { class: "aviso__acciones" },
              h("a", { class: "boton", href: hashEdicion(codigo, busqueda) },
                icono("editar"), "Editar vino"),
              h("a", { class: "boton boton--secundario", href: hashDetalle(codigo, busqueda) }, "Ver detalle"))),
          mensajeError(error));
        return;
      }
    }
    if (signal.aborted) return;
    dejarAviso(`Vino ${codigo} registrado correctamente.`);
    location.hash = hashDetalle(codigo, busqueda);
  }

  async function actualizar({ ficha, cepas, maridajes }) {
    try {
      // Se envían las listas completas: la API reemplaza las actuales por estas
      await modificarVino(vino.cod_vino, { ...ficha, cepas, maridajes });
    } catch (error) {
      if (!signal.aborted) mostrarResultado(mensajeError(error));
      return;
    }
    if (signal.aborted) return;
    dejarAviso("Cambios guardados correctamente.");
    location.hash = hashDetalle(vino.cod_vino, busqueda);
  }

  return formulario;
}

// ---------- Vistas ----------

async function cargarYMostrar(contenedor, { titulo, descripcion, volver, cargar, signal, construir }) {
  const cuerpo = h("div", { class: "formulario-vino" });
  contenedor.replaceChildren(encabezadoPagina({ titulo, descripcion, acciones: volver }), cuerpo);

  const intentar = async (forzar = false) => {
    cuerpo.replaceChildren(cargando("Cargando datos del formulario…"));
    let datos;
    try {
      datos = await cargar(forzar);
    } catch (error) {
      if (signal.aborted || error?.name === "AbortError") return;
      const noExiste = error?.estado === 404 && error?.recurso === "el vino";
      cuerpo.replaceChildren(
        h("p", { class: "formulario__nota" }, `No se pudo cargar ${error?.recurso ?? "la información necesaria"}.`),
        mensajeError(error, { onReintentar: noExiste ? null : () => intentar(true) }));
      return;
    }
    if (signal.aborted) return;
    cuerpo.replaceChildren(construir(datos));
  };
  intentar();
}

// Catálogos que necesita el formulario. Sin signal (caché compartida de catalogos.js)
const cargarCatalogos = (forzar) => Promise.all([
  conNombre(obtenerBodegas({ forzar }), "las bodegas"),
  conNombre(obtenerCepas({ forzar }), "las cepas"),
  conNombre(obtenerMaridajes({ forzar }), "los maridajes"),
]).then(([bodegas, cepas, maridajes]) => {
  if (![bodegas, cepas, maridajes].every(Array.isArray)) {
    throw new ApiError("La API devolvió un catálogo con un formato inesperado.", { tipo: "formato" });
  }
  return { bodegas, cepas, maridajes };
});

export function vistaAltaVino(contenedor, { consulta, signal }) {
  const busqueda = leerBusqueda(consulta);
  cargarYMostrar(contenedor, {
    titulo: "Nuevo vino",
    descripcion: "Registrá un vino con su composición de cepas y, si querés, sus maridajes.",
    volver: h("a", { class: "boton boton--secundario", href: hashCatalogo(busqueda) }, icono("anterior"), "Volver al catálogo"),
    signal,
    cargar: cargarCatalogos,
    construir: (catalogos) => formularioVino({ modo: "alta", catalogos, busqueda, signal }),
  });
}

export function vistaEdicionVino(contenedor, { params, consulta, signal }) {
  const busqueda = leerBusqueda(consulta);
  const cod = params.cod;
  cargarYMostrar(contenedor, {
    titulo: "Editar vino",
    descripcion: `Código ${cod}`,
    volver: h("a", { class: "boton boton--secundario", href: hashDetalle(cod, busqueda) }, icono("anterior"), "Volver al detalle"),
    signal,
    cargar: async (forzar) => {
      const [vino, catalogos] = await Promise.all([
        conNombre(obtenerVino(cod, { signal }), "el vino"),
        cargarCatalogos(forzar),
      ]);
      if (!vino || typeof vino !== "object" || !vino.cod_vino) {
        throw Object.assign(new ApiError("La API devolvió una respuesta con un formato inesperado.", { tipo: "formato" }), { recurso: "el vino" });
      }
      return { vino, catalogos };
    },
    construir: ({ vino, catalogos }) => {
      document.title = `Editar ${vino.nombre_comercial ?? cod} · Bodegas del Atuel`;
      return formularioVino({ modo: "edicion", vino, catalogos, busqueda, signal });
    },
  });
}
