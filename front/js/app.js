// Punto de entrada: arma el encabezado, la navegación y el enrutador.
import { crearEncabezado } from "./componentes/encabezado.js";
import { crearNavegacion } from "./componentes/navegacion.js";
import { crearRouter } from "./router.js";
import { rutas } from "./rutas.js";

crearEncabezado(document.getElementById("encabezado"));
const navegacion = crearNavegacion(document.getElementById("navegacion"), rutas);

crearRouter({
  rutas,
  contenedor: document.getElementById("contenido"),
  alCambiar: ({ camino }) => navegacion.marcarActiva(camino),
}).iniciar();
