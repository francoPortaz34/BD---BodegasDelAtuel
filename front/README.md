# Front — Bodegas del Atuel (Etapa 7)

HTML, CSS y JavaScript nativos (módulos ES). Sin dependencias ni paso de build.
Consume únicamente la API REST y no calcula totales, descuentos ni stock.

## Ejecutar en desarrollo

Con la API levantada (`docker compose up`, queda en `http://127.0.0.1:8000`):

```sh
python front/servidor.py      # desde la raíz del repositorio
python servidor.py            # o desde front/
```

Abrir <http://127.0.0.1:5173>.

`servidor.py` (solo biblioteca estándar) sirve los archivos y reenvía `/api/*` a la API,
así el navegador usa un único origen y la API no necesita CORS.

| Variable | Por defecto | Uso |
|---|---|---|
| `API_URL` | `http://127.0.0.1:8000` | Dirección de la API a la que reenvía `/api` |
| `FRONT_PORT` | `5173` | Puerto del front |

## Configuración de la URL de la API

Único lugar: [`config.js`](config.js) (`window.BODEGAS_CONFIG.apiUrl`, por defecto `/api`).
Todas las llamadas pasan por [`js/api/cliente.js`](js/api/cliente.js).

## Estructura

```text
front/
├── index.html            Estructura base (encabezado, navegación, contenido)
├── config.js             URL de la API y tiempo máximo de espera
├── servidor.py           Servidor de desarrollo + proxy /api
├── css/estilos.css
└── js/
    ├── app.js            Punto de entrada
    ├── config.js         Lee config.js y completa valores por defecto
    ├── router.js         Enrutador por hash (#/ruta, #/ruta/:param, ?consulta)
    ├── rutas.js          Secciones y su vista (las subetapas reemplazan las provisorias)
    ├── dom.js            h() para crear elementos sin innerHTML, íconos
    ├── api/
    │   ├── cliente.js    Cliente HTTP único y ApiError
    │   ├── catalogos.js  Salas, bodegas, cepas y maridajes (con caché en memoria)
    │   ├── vinos.js      GET/POST /vinos, GET/PUT /vinos/{cod}
    │   ├── ventas.js     POST /comprobantes, GET /comprobantes/{nro}
    │   └── clientes.js   GET /clientes (búsqueda paginada)
    ├── componentes/      Encabezado, navegación, estados, tarjeta, tabla, paginación, campos y avisos
    └── vistas/           Inicio, catálogos, vinos (catálogo, detalle, alta, edición), ventas, provisorias
```

## Catálogo de vinos (`#/vinos`)

- **Filtros** (se envían a la API solo al pulsar *Aplicar filtros*): tipo (`tinto`, `blanco`,
  `rosado`, `espumante`), cepa (por **nombre**, opciones de `GET /cepas`), bodega (por
  **`id_bodega`**, opciones de `GET /bodegas`) y añada. *Limpiar filtros* los quita todos.
- **Estado en la dirección**: `#/vinos?tipo=tinto&cepa=Malbec&bodega=3&anada=2020&pagina=2&tamanio=20`.
  Cambiar un filtro vuelve a la página 1; cambiar de página conserva los filtros.
- **Paginación** con `pagina` y `tamanio` (20 por defecto). La API no informa el total: si la
  página llega incompleta es la última; si llega completa, se consulta un único registro
  (`tamanio=1`, `pagina=pagina*tamanio+1`, es decir el OFFSET siguiente) para saber si hay más.
  Una página vacía (p. ej. escrita a mano) ofrece volver a la anterior o a la primera.
- **Detalle** (`#/vinos/{cod}?...`): ficha, composición de cepas y maridajes tal como los
  devuelve `GET /vinos/{cod}`. *Volver al catálogo* restaura filtros y página. 404 → "Vino no encontrado".

## Alta y edición de vinos

- **Alta** (`#/vinos/nuevo`, botón *Nuevo vino* del catálogo) y **edición** (`#/vinos/{cod}/editar`,
  botón *Editar* del detalle). Bodegas, cepas y maridajes se cargan de la API; tipo y presentación
  usan los valores admitidos por la base (ENUM `tipo_vino` y CHECK `ck_vino_presentacion`).
- **Cepas**: filas con cepa y porcentaje; una cepa elegida no se puede repetir. La suma 100 (RN-05)
  **no** se calcula en el front: la controla la base y su mensaje se muestra tal cual.
- **Maridajes**: casillas (sin duplicados). `POST /vinos` no los admite: en el alta, si se eligieron,
  se envía después `PUT /vinos/{cod}` con la misma ficha y los maridajes. No es atómico: si ese PUT
  falla, el vino queda registrado sin maridajes y se ofrece completarlos desde *Editar*.
- **Edición**: el código no se modifica (va en la URL). Se envían la ficha y las listas completas
  de cepas y maridajes, que la API reemplaza en una sola transacción.
- Validación de formato antes de enviar (obligatorios, largos, rangos de los CHECK de `vino`);
  el botón se deshabilita mientras se guarda (sin envíos duplicados). Al guardar se vuelve al
  detalle con un aviso de éxito, conservando la búsqueda del catálogo.

## Ventas (`#/ventas`)

- La API solo permite **registrar** una venta (`POST /comprobantes`) y **consultar** una por su
  número (`GET /comprobantes/{nro}`): **no existe un listado de comprobantes**. La pantalla ofrece
  un buscador por número y una lista de las ventas registradas *desde este navegador*
  (`localStorage`), que **no es el listado completo** de la base.
- **Nueva venta** (`#/ventas/nueva`): número de comprobante (la API no lo asigna), sala (`GET /salas`),
  cliente (búsqueda paginada en `GET /clientes` por nombre o documento) y renglones vino + cantidad.
  Los códigos se eligen de `GET /vinos` (páginas de 100); el `id_vino` de cada vino elegido se
  obtiene con `GET /vinos/{cod}`. Un vino no se repite en la venta.
- La fecha, los precios, descuentos, subtotales, totales y el stock los resuelve la base (RN-01,
  RN-06, RN-08, RN-09); el front no calcula ni decide nada de eso. Si la base rechaza la venta
  (por ejemplo "Stock insuficiente… (RN-09)"), se muestra su mensaje y no se registra nada.
- **Detalle** (`#/ventas/{nro}`): datos del comprobante y renglones con los importes de la base.

## Errores

`cliente.js` convierte toda falla en `ApiError` (`tipo`: `red`, `tiempo`, `http`, `formato`;
`estado`, `sqlstate`, `cuerpo`). Los mensajes de reglas de negocio que envía la API
(`{"error": "..."}`) se muestran tal cual, sin reemplazarlos por un texto genérico.
