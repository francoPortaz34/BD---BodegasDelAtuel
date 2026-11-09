// Ayudas mínimas para crear elementos del DOM sin librerías.
// Todo texto se inserta como nodo de texto (nunca como HTML), así los datos que
// vienen de la API no pueden inyectar marcado.

/**
 * h("button", { class: "boton", onClick: fn }, "Texto", otroNodo)
 * - class -> className; on<Evento> -> addEventListener; dataset -> data-*
 * - true agrega el atributo vacío; null/undefined/false lo omiten.
 */
export function h(etiqueta, propiedades = {}, ...hijos) {
  const el = document.createElement(etiqueta);
  for (const [clave, valor] of Object.entries(propiedades ?? {})) {
    if (valor === null || valor === undefined || valor === false) continue;
    if (clave === "class") el.className = valor;
    else if (clave === "dataset") Object.assign(el.dataset, valor);
    else if (clave.startsWith("on") && typeof valor === "function") {
      el.addEventListener(clave.slice(2).toLowerCase(), valor);
    } else el.setAttribute(clave, valor === true ? "" : String(valor));
  }
  for (const hijo of hijos.flat(Infinity)) {
    if (hijo === null || hijo === undefined || hijo === false) continue;
    el.append(hijo instanceof Node ? hijo : String(hijo));
  }
  return el;
}

// Íconos SVG estáticos (constantes del código, no datos de la API).
const ICONOS = {
  copa: '<path d="M7 3h10c0 5.5-2 9.5-5 9.5S7 8.5 7 3Z"/><path d="M12 12.5V20M8 21h8"/>',
  inicio: '<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v10h13V10"/>',
  vinos: '<path d="M9 3h6v4.5c1.8.9 3 2.8 3 5V21H6v-8.5c0-2.2 1.2-4.1 3-5Z"/><path d="M6 14h12"/>',
  catalogos: '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 10h16M10 10v10"/>',
  ventas: '<path d="M4 5h2l2 10h10l2-7H7"/><circle cx="10" cy="19" r="1.3"/><circle cx="17" cy="19" r="1.3"/>',
  transferencias: '<path d="M4 8h13l-3-3M20 16H7l3 3"/>',
  tablero: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  reintentar: '<path d="M20 12a8 8 0 1 1-2.3-5.7L20 8.5"/><path d="M20 3.5v5h-5"/>',
  alerta: '<path d="M12 4 2.5 20h19Z"/><path d="M12 10v4.5M12 17.5v.5"/>',
  vacio: '<path d="M3 13h5l1.5 2.5h5L16 13h5"/><path d="M5.5 6h13L21 13v6H3v-6Z"/>',
  reloj: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  anterior: '<path d="m15 5-7 7 7 7"/>',
  siguiente: '<path d="m9 5 7 7-7 7"/>',
  filtro: '<path d="M4 5h16l-6 7.5V19l-4 1.5v-8Z"/>',
  mas: '<path d="M12 5v14M5 12h14"/>',
  quitar: '<path d="M6 6l12 12M18 6 6 18"/>',
  editar: '<path d="M4 20h4L19 9l-4-4L4 16Z"/><path d="m13.5 6.5 4 4"/>',
  ok: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
};

export function icono(nombre, clase = "icono") {
  const span = document.createElement("span");
  span.className = clase;
  span.setAttribute("aria-hidden", "true");
  span.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONOS[nombre] ?? ""}</svg>`;
  return span;
}
