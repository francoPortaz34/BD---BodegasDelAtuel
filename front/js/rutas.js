// Secciones de la aplicación. Para implementar una pantalla nueva basta con
// reemplazar su vista acá (las subetapas 2 a 5 cambian solo esta tabla y
// agregan su archivo en js/vistas/).
import { vistaCatalogos } from "./vistas/catalogos.js";
import { vistaInicio } from "./vistas/inicio.js";
import { vistaNoEncontrada, vistaPendiente } from "./vistas/pendiente.js";
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
    ruta: "/ventas", titulo: "Ventas", menu: "Ventas", icono: "ventas", subetapa: 4,
    descripcion: "Nueva venta: cliente, sala y vinos, con el total calculado por la base.",
  },
  {
    ruta: "/transferencias", titulo: "Transferencias", menu: "Transferencias", icono: "transferencias", subetapa: 5,
    descripcion: "Alta, carga de renglones y cambio de estado de las transferencias del depósito a las salas.",
  },
  {
    ruta: "/tablero", titulo: "Tablero", menu: "Tablero", icono: "tablero", subetapa: 5,
    descripcion: "Ranking de vinos más vendidos, ventas por sala del último trimestre y vinos sin stock por sala.",
  },
  {
    ruta: "/catalogos", titulo: "Catálogos", menu: "Catálogos", icono: "catalogos",
    descripcion: "Salas de venta, bodegas, cepas y maridajes registrados.",
    vista: vistaCatalogos,
  },
  { ruta: "*", titulo: "Página no encontrada", vista: vistaNoEncontrada },
].map((r) => ({ ...r, vista: r.vista ?? vistaPendiente(r) }));
