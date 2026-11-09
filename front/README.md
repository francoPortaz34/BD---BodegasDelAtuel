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
    │   └── catalogos.js  Salas, bodegas, cepas y maridajes (con caché en memoria)
    ├── componentes/      Encabezado, navegación, estados (carga/error/vacío), tarjeta y tabla
    └── vistas/           Inicio, catálogos y pantallas provisorias
```

## Errores

`cliente.js` convierte toda falla en `ApiError` (`tipo`: `red`, `tiempo`, `http`, `formato`;
`estado`, `sqlstate`, `cuerpo`). Los mensajes de reglas de negocio que envía la API
(`{"error": "..."}`) se muestran tal cual, sin reemplazarlos por un texto genérico.
