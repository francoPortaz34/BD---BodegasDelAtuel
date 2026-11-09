// Secciones de la aplicación. Para implementar una pantalla nueva basta con
// reemplazar su vista acá (las subetapas 2 a 5 cambian solo esta tabla y
// agregan su archivo en js/vistas/).
import { vistaCatalogos } from "./vistas/catalogos.js";
import { vistaInicio } from "./vistas/inicio.js";
import { vistaNoEncontrada, vistaPendiente } from "./vistas/pendiente.js";
import { vistaTablero } from "./vistas/tablero.js";
import { vistaDetalleTransferencia } from "./vistas/transferencia-detalle.js";
import { vistaNuevaTransferencia, vistaTransferencias } from "./vistas/transferencias.js";
import { vistaDetalleVenta } from "./vistas/venta-detalle.js";
import { vistaNuevaVenta } from "./vistas/venta-nueva.js";
import { vistaVentas } from "./vistas/ventas.js";
import { vistaDetalleVino } from "./vistas/vino-detalle.js";
import { vistaAltaVino, vistaEdicionVino } from "./vistas/vino-formulario.js";
import { vistaVinos } from "./vistas/vinos.js";

export const rutas = [
  {
    ruta: "/", titulo: "Inicio", menu: "Inicio", icono: "inicio",
    vista: vistaInicio,
  },
  {
    ruta: "/vinos", titulo: "Catálogo de vinos", menu: "Vinos", icono: "vinos",
    descripcion: "Listado paginado con filtros por tipo, cepa, bodega y añada; detalle, alta y edición con composición de cepas y maridajes.",
    vista: vistaVinos,
  },
  // Alta, edición y detalle (sin entrada en el menú: la navegación marca "Vinos").
  // "/vinos/nuevo" va antes que "/vinos/:cod": el enrutador usa la primera que coincide.
  { ruta: "/vinos/nuevo", titulo: "Nuevo vino", vista: vistaAltaVino },
  { ruta: "/vinos/:cod/editar", titulo: "Editar vino", vista: vistaEdicionVino },
  { ruta: "/vinos/:cod", titulo: "Detalle del vino", vista: vistaDetalleVino },
  {
    ruta: "/ventas", titulo: "Ventas", menu: "Ventas", icono: "ventas",
    descripcion: "Registro de ventas (cliente, sala y vinos) y consulta de comprobantes por número, con importes calculados por la base.",
    vista: vistaVentas,
  },
  // "/ventas/nueva" va antes que "/ventas/:nro" (el enrutador usa la primera que coincide)
  { ruta: "/ventas/nueva", titulo: "Nueva venta", vista: vistaNuevaVenta },
  { ruta: "/ventas/:nro", titulo: "Detalle de la venta", vista: vistaDetalleVenta },
  {
    ruta: "/transferencias", titulo: "Transferencias", menu: "Transferencias", icono: "transferencias",
    descripcion: "Transferencias del depósito central a las salas: alta, carga de vinos, terminar y procesar.",
    vista: vistaTransferencias,
  },
  // "/transferencias/nueva" va antes que "/transferencias/:nro"
  { ruta: "/transferencias/nueva", titulo: "Nueva transferencia", vista: vistaNuevaTransferencia },
  { ruta: "/transferencias/:nro", titulo: "Detalle de la transferencia", vista: vistaDetalleTransferencia },
  {
    ruta: "/tablero", titulo: "Tablero", menu: "Tablero", icono: "tablero",
    descripcion: "Vinos más vendidos, ventas por sala del último trimestre, transportista más activo, vinos sin stock por sala y trazabilidad.",
    vista: vistaTablero,
  },
  {
    ruta: "/catalogos", titulo: "Catálogos", menu: "Catálogos", icono: "catalogos",
    descripcion: "Salas de venta, bodegas, cepas y maridajes registrados.",
    vista: vistaCatalogos,
  },
  { ruta: "*", titulo: "Página no encontrada", vista: vistaNoEncontrada },
].map((r) => ({ ...r, vista: r.vista ?? vistaPendiente(r) }));
