// Catálogo de vinos (subetapa 2): listado paginado con filtros por tipo, cepa,
// bodega y añada. Filtros y paginación los resuelve la API (GET /vinos); el
// estado de búsqueda vive en la dirección (#/vinos?...), así que aplicar filtros
// o cambiar de página es navegar, y el enrutador cancela la petición anterior.
import { obtenerBodegas, obtenerCepas } from "../api/catalogos.js";
import { ApiError } from "../api/cliente.js";
import { listarVinos, TIPOS_VINO } from "../api/vinos.js";
import { encabezadoPagina, tabla, tarjeta } from "../componentes/contenido.js";
import { cargando, mensajeError, vacio } from "../componentes/estados.js";
import { crearPaginacion } from "../componentes/paginacion.js";
import { campo } from "../componentes/formulario.js";
import { h, icono } from "../dom.js";
import {
  capital, etiquetaTipo, formatoDecimal, formatoPrecio, hashAlta, hashCatalogo, hashDetalle,
  hayFiltros, leerBusqueda, TAMANIOS,
} from "./vinos-comun.js";

/** Navega a la búsqueda indicada; si la dirección no cambia, vuelve a consultar. */
function navegar(busqueda, recargar) {
  const antes = location.hash;
  location.hash = hashCatalogo(busqueda);
  if (location.hash === antes) recargar();
}

// ---------- Filtros ----------

/**
 * Selector cargado desde un catálogo de la API. Mientras carga queda deshabilitado
 * y conserva el valor de la búsqueda; si falla, muestra el error con reintento.
 */
function selectorCatalogo({ nombre, todos, valor, obtener, opcion, textoError, signal }) {
  const select = h("select", { name: nombre, class: "campo__control", disabled: true });
  const ayuda = h("span", { class: "campo__ayuda" });

  const llenar = (filas) => {
    const opciones = filas.map(opcion);   // [{ valor, texto }]
    const valorTexto = String(valor ?? "");
    // Valor de la dirección que no está en el catálogo: se muestra igual, para
    // que el formulario refleje el filtro que realmente se envía a la API.
    if (valorTexto && !opciones.some((o) => String(o.valor) === valorTexto)) {
      opciones.push({ valor: valorTexto, texto: `${valorTexto} (no registrada)` });
    }
    select.replaceChildren(h("option", { value: "" }, todos),
      ...opciones.map((o) => h("option", { value: o.valor }, o.texto)));
    select.value = valorTexto;
  };

  const cargar = (forzar = false) => {
    select.disabled = true;
    select.replaceChildren(h("option", { value: String(valor ?? "") }, "Cargando…"));
    ayuda.replaceChildren();
    obtener({ forzar })
      .then((filas) => {
        if (signal.aborted) return;
        llenar(Array.isArray(filas) ? filas : []);
        select.disabled = false;
      })
      .catch((error) => {
        if (signal.aborted) return;
        llenar([]);
        select.disabled = false;
        ayuda.replaceChildren(
          h("span", { class: "campo__error" }, `${textoError}: ${error.message}`), " ",
          h("button", { class: "enlace", type: "button", onClick: () => cargar(true) }, "Reintentar"));
      });
  };

  cargar();
  return { select, ayuda };
}

function crearFiltros(busqueda, { alAplicar, alLimpiar, signal }) {
  const tipo = h("select", { name: "tipo", class: "campo__control" },
    h("option", { value: "" }, "Todos"),
    TIPOS_VINO.map((t) => h("option", { value: t }, capital(t))));
  tipo.value = busqueda.tipo;

  const cepa = selectorCatalogo({
    nombre: "cepa", todos: "Todas", valor: busqueda.cepa, signal,
    obtener: obtenerCepas, textoError: "No se pudieron cargar las cepas",
    // La API filtra por el NOMBRE de la cepa
    opcion: (c) => ({ valor: c.nombre, texto: c.nombre }),
  });
  const bodega = selectorCatalogo({
    nombre: "bodega", todos: "Todas", valor: busqueda.bodega, signal,
    obtener: obtenerBodegas, textoError: "No se pudieron cargar las bodegas",
    // La API filtra por id_bodega
    opcion: (b) => ({ valor: String(b.id_bodega), texto: b.razon_social }),
  });

  const anada = h("input", {
    name: "anada", class: "campo__control", type: "number", inputmode: "numeric",
    min: 0, max: 32767, step: 1, placeholder: "Ej.: 2020", value: busqueda.anada,
  });

  const tamanio = h("select", { name: "tamanio", class: "campo__control" },
    TAMANIOS.map((t) => h("option", { value: t }, `${t} por página`)));
  tamanio.value = String(busqueda.tamanio);

  const formulario = h("form", { class: "filtros", role: "search", "aria-label": "Filtros del catálogo" },
    h("div", { class: "filtros__campos" },
      campo("Tipo", tipo),
      campo("Cepa", cepa.select, cepa.ayuda),
      campo("Bodega", bodega.select, bodega.ayuda),
      campo("Añada", anada),
      campo("Mostrar", tamanio)),
    h("div", { class: "filtros__acciones" },
      h("button", { class: "boton", type: "submit" }, icono("filtro"), "Aplicar filtros"),
      h("button", { class: "boton boton--secundario", type: "button", onClick: alLimpiar }, "Limpiar filtros")));

  // Los filtros se envían solo al confirmar (botón o Enter), no mientras se completan.
  // La validación de la añada (entero 0..32767) la hace el navegador antes del submit.
  formulario.addEventListener("submit", (evento) => {
    evento.preventDefault();
    alAplicar({
      tipo: tipo.value,
      cepa: cepa.select.disabled ? busqueda.cepa : cepa.select.value,
      bodega: bodega.select.disabled ? busqueda.bodega : bodega.select.value,
      anada: anada.value.trim(),
      pagina: 1,   // cambiar un filtro reinicia la paginación
      tamanio: Number(tamanio.value),
    });
  });

  return formulario;
}

/** Resumen de los filtros que se están aplicando. */
function filtrosActivos(busqueda, signal) {
  if (!hayFiltros(busqueda)) return null;
  const item = (nombre, valor) => h("li", { class: "chip" }, h("span", { class: "chip__nombre" }, `${nombre}:`), " ", valor);
  const nombreBodega = h("span", {}, `N° ${busqueda.bodega}`);
  if (busqueda.bodega !== "") {
    obtenerBodegas().then((bodegas) => {
      if (signal.aborted) return;
      const b = bodegas.find((x) => String(x.id_bodega) === String(busqueda.bodega));
      if (b) nombreBodega.textContent = b.razon_social;
    }).catch(() => {});
  }
  return h("ul", { class: "chips", "aria-label": "Filtros aplicados" },
    busqueda.tipo && item("Tipo", capital(busqueda.tipo)),
    busqueda.cepa && item("Cepa", busqueda.cepa),
    busqueda.bodega !== "" && item("Bodega", nombreBodega),
    busqueda.anada !== "" && item("Añada", String(busqueda.anada)));
}

// ---------- Resultados ----------

function columnas(busqueda) {
  return [
    { titulo: "Código", valor: (v) => v.cod_vino, clase: "mono" },
    { titulo: "Nombre comercial", valor: (v) => v.nombre_comercial },
    { titulo: "Tipo", valor: (v) => etiquetaTipo(v.tipo) },
    { titulo: "Añada", valor: (v) => v.anada, clase: "num" },
    { titulo: "Presentación", valor: (v) => formatoDecimal(v.presentacion_ml, " ml"), clase: "num" },
    { titulo: "Graduación", valor: (v) => formatoDecimal(v.graduacion_alcoholica, " %"), clase: "num" },
    { titulo: "Precio de venta", valor: (v) => formatoPrecio(v.precio_venta), clase: "num" },
    { titulo: "Bodega", valor: (v) => v.bodega },
    {
      titulo: "Acciones", clase: "acciones",
      valor: (v) => h("a", {
        class: "boton boton--secundario boton--chico", href: hashDetalle(v.cod_vino, busqueda),
        "aria-label": `Ver detalle de ${v.nombre_comercial ?? v.cod_vino}`,
      }, "Ver detalle"),
    },
  ];
}

export function vistaVinos(contenedor, { consulta, signal }) {
  const busqueda = leerBusqueda(consulta);
  const ir = (nueva) => navegar(nueva, cargarListado);

  const subtitulo = h("span", { class: "tarjeta__contador", "aria-live": "polite" });
  const { tarjeta: tarjetaResultados, cuerpo } = tarjeta({ titulo: "Vinos", acciones: subtitulo });

  const paginacion = crearPaginacion({ alIr: (pagina) => ir({ ...busqueda, pagina }) });
  const limpiar = () => ir({ tamanio: busqueda.tamanio, pagina: 1 });

  // replaceChildren convierte null en texto: se descartan los bloques ausentes
  contenedor.replaceChildren(...[
    encabezadoPagina({
      titulo: "Catálogo de vinos",
      descripcion: "Consultá los vinos registrados. Filtrá por tipo, cepa, bodega y añada, y abrí el detalle para ver la composición y los maridajes.",
      acciones: h("a", { class: "boton", href: hashAlta(busqueda) }, icono("mas"), "Nuevo vino"),
    }),
    crearFiltros(busqueda, { alAplicar: ir, alLimpiar: limpiar, signal }),
    filtrosActivos(busqueda, signal),
    tarjetaResultados,
    paginacion.el,
  ].filter(Boolean));

  // Cada consulta cancela la anterior y se descarta si llega tarde (secuencia),
  // así una respuesta vieja nunca pisa los resultados de una búsqueda más nueva.
  let secuencia = 0;
  let controlador = null;
  signal.addEventListener("abort", () => controlador?.abort(), { once: true });

  async function cargarListado() {
    const numero = ++secuencia;
    controlador?.abort();
    controlador = new AbortController();
    const local = controlador.signal;
    const vigente = () => numero === secuencia && !signal.aborted;

    cuerpo.replaceChildren(cargando(busqueda.pagina > 1 ? `Cargando la página ${busqueda.pagina}…` : "Cargando vinos…"));
    subtitulo.textContent = "";
    paginacion.ocultar();

    let datos;
    try {
      datos = await listarVinos(busqueda, { signal: local });
      if (!vigente()) return;
      if (!datos || !Array.isArray(datos.vinos)) {
        throw new ApiError("La API devolvió una respuesta con un formato inesperado.", { tipo: "formato" });
      }
    } catch (error) {
      if (!vigente() || error?.name === "AbortError") return;
      cuerpo.replaceChildren(mensajeError(error, { onReintentar: cargarListado }));
      return;
    }

    const pagina = Number(datos.pagina) || busqueda.pagina;
    const tamanio = Number(datos.tamanio) || busqueda.tamanio;
    const { vinos } = datos;

    if (vinos.length === 0) {
      mostrarVacio(pagina);
      return;
    }

    subtitulo.textContent = `Página ${pagina} · ${vinos.length} ${vinos.length === 1 ? "vino" : "vinos"} en esta página`;
    cuerpo.replaceChildren(tabla({ columnas: columnas(busqueda), filas: vinos, descripcion: "Vinos del catálogo" }));

    // Fin de la paginación sin total: si la página vino incompleta es la última.
    // Si vino completa, se pregunta a la API si existe al menos UN registro
    // después: con tamanio=1, la página (pagina*tamanio + 1) empieza exactamente
    // en el registro siguiente al último mostrado (OFFSET = pagina*tamanio).
    if (vinos.length < tamanio) {
      paginacion.actualizar({ pagina, haySiguiente: false });
      return;
    }
    paginacion.actualizar({ pagina, haySiguiente: null });
    try {
      const siguiente = await listarVinos({ ...busqueda, pagina: pagina * tamanio + 1, tamanio: 1 }, { signal: local });
      if (!vigente()) return;
      paginacion.actualizar({ pagina, haySiguiente: Array.isArray(siguiente?.vinos) && siguiente.vinos.length > 0 });
    } catch (error) {
      if (!vigente() || error?.name === "AbortError") return;
      // Si la verificación falla se permite avanzar: una página vacía se maneja abajo.
      paginacion.actualizar({ pagina, haySiguiente: true });
    }
  }

  function mostrarVacio(pagina) {
    if (pagina > 1) {
      // Página sin resultados (por ejemplo, una dirección escrita a mano o datos
      // que cambiaron): se ofrece volver para no dejar al usuario atrapado.
      const estado = vacio(`La página ${pagina} no tiene resultados.`);
      estado.append(h("div", { class: "estado__acciones" },
        h("button", { class: "boton boton--secundario", type: "button", onClick: () => ir({ ...busqueda, pagina: pagina - 1 }) },
          icono("anterior"), "Página anterior"),
        h("button", { class: "boton boton--secundario", type: "button", onClick: () => ir({ ...busqueda, pagina: 1 }) },
          "Ir a la primera página")));
      cuerpo.replaceChildren(estado);
      paginacion.actualizar({ pagina, haySiguiente: false });
      return;
    }
    const filtrado = hayFiltros(busqueda);
    const estado = vacio(filtrado ? "No hay vinos que coincidan con los filtros aplicados." : "No hay vinos registrados.");
    if (filtrado) {
      estado.append(h("div", { class: "estado__acciones" },
        h("button", { class: "boton boton--secundario", type: "button", onClick: limpiar }, "Limpiar filtros")));
    }
    cuerpo.replaceChildren(estado);
  }

  cargarListado();
}
