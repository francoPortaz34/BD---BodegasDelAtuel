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
    │   └── vinos.js      GET /vinos (filtros y paginación) y GET /vinos/{cod}
    ├── componentes/      Encabezado, navegación, estados (carga/error/vacío), tarjeta, tabla y paginación
    └── vistas/           Inicio, catálogos, catálogo y detalle de vinos, pantallas provisorias
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

## Errores

`cliente.js` convierte toda falla en `ApiError` (`tipo`: `red`, `tiempo`, `http`, `formato`;
`estado`, `sqlstate`, `cuerpo`). Los mensajes de reglas de negocio que envía la API
(`{"error": "..."}`) se muestran tal cual, sin reemplazarlos por un texto genérico.
