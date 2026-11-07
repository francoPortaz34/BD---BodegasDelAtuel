# Etapa 3 – Catálogo de localidades de Mendoza

Preparación de los datos de carga para la tabla `localidad` y de sus
encargados auxiliares. Este documento registra las fuentes, los criterios
aprobados, las normalizaciones aplicadas y los datos faltantes.

> Estado: archivos CSV preparados. **Todavía no existe script de carga** y no
> se modificó el esquema ni la base de datos.

## 1. Archivos

| Archivo | Filas | Contenido |
|---|---|---|
| `db/seed/csv/localidades.csv` | 269 | Localidades a cargar en `localidad` |
| `db/seed/csv/encargados_auxiliares.csv` | 269 | Un encargado ficticio por localidad |
| `db/seed/csv/localidades_excluidas.csv` | 36 | Localidades sin código postal (no se cargan) |

Todos los archivos están en UTF-8 sin BOM, con fin de línea LF, separador `,` y
encabezado en la primera fila.

### 1.1 `localidades.csv`

```
cod_postal,nombre,provincia,departamento
```

- `cod_postal`, `nombre` y `provincia` se corresponden con las columnas de la tabla `localidad`.
- `departamento` es una **columna auxiliar** para documentar y validar. **No
  existe en la tabla `localidad`** y no se inserta.
- `provincia` vale siempre `Mendoza`.
- Orden: por departamento y luego por nombre de localidad, sin distinguir tildes.

### 1.2 `encargados_auxiliares.csv`

```
dni,nombre,apellido,localidad,cod_postal
```

- `dni`: `AUX-0001` … `AUX-0269`. `nombre`: `Encargado`. `apellido`: `Auxiliar 0001` … `Auxiliar 0269`.
- Columnas que se insertan en la tabla `encargado`: **`dni`, `nombre`, `apellido`**.
- `localidad` y `cod_postal` son **columnas auxiliares**. Sirven solo para
  relacionar cada encargado con su localidad y **no se insertan en la tabla
  `encargado`**, que no tiene esas columnas. La pareja (`localidad`, `cod_postal`)
  se compara con (`nombre`, `cod_postal`) de `localidades.csv`. Ese par es único
  en el catálogo, incluso para *Villa Seca*.
- La relación entre encargados y localidades **no depende del orden de las
  filas**: se resuelve únicamente por esa clave. Que la numeración AUX siga el
  orden de `localidades.csv` es solo informativo.
- Son datos **ficticios**, con un formato elegido para que no puedan
  confundirse con personas ni documentos reales.

**Verificación del esquema** (`db/migrations/001_esquema.sql`):

| Columna | Definición | Compatibilidad |
|---|---|---|
| `encargado.id_encargado` | `SERIAL NOT NULL`, PK | Entero autogenerado. **No admite** `AUX-0001`, por eso no figura en el CSV y la generará la base. |
| `encargado.dni` | `VARCHAR(50) NOT NULL`, `UNIQUE (uq_encargado_dni)` | Admite identificadores alfanuméricos. Aquí va `AUX-NNNN` (8 caracteres). |
| `encargado.nombre` / `apellido` | `VARCHAR(50) NOT NULL` | `Encargado` / `Auxiliar NNNN` entran sin problema. |
| `localidad.id_encargado` | `INTEGER NOT NULL`, `UNIQUE (uq_localidad_encargado)`, FK a `encargado` | Exige un encargado distinto por localidad: 269 encargados para 269 localidades. |

No hay CHECK ni triggers sobre `encargado` (revisado en las migraciones 002 a 007).
La futura carga deberá insertar primero los encargados y luego resolver
`localidad.id_encargado` buscando por `dni`.

### 1.3 `localidades_excluidas.csv`

```
nombre,departamento,distrito,c_postal_fuente,fid_ide,fuente,motivo
```

Contiene las 36 localidades de IDE Mendoza con `c_postal = 0`. No pueden
cargarse porque `localidad.cod_postal` es `CHAR(4) NOT NULL` y **no se inventan
ni se aproximan códigos postales**.

## 2. Fuentes

Fecha de consulta: **06/11/2026**.

### 2.1 IDE Mendoza (fuente principal)

- Capa: `Localidades` (Feature Layer, ArcGIS REST).
- URL: <https://ide.mendoza.gov.ar/server/rest/services/Hosted/Localidades/FeatureServer/0>
- Consulta utilizada:
  ```
  /query?where=1=1&outFields=fid,id,localidad,distrito,depto,c_postal,dist_mza&returnGeometry=false&f=json
  ```
- Última edición de la capa (`editingInfo.lastEditDate`): 17/01/2025.
- Total: **303 registros**: 267 con código postal y 36 sin código postal.
- `c_postal` es un campo entero. Los faltantes figuran como `0`, no como `NULL`.

### 2.2 Datos Abiertos Mendoza (fuente complementaria)

- Dataset: *Localidades de la Provincia de Mendoza*, publicado por la
  Secretaría de Ambiente y Ordenamiento Territorial con licencia ODbL 1.0.
- Recurso: <https://datosabiertos.mendoza.gov.ar/dataset/0b4c6950-fd01-4fdd-9748-2a706bbc1d99/archivo/206ac3e7-f8fa-4658-ac01-5c32edfe6538>
  (`localidades-5.csv`). Fue publicado el 27/10/2022 y su descripción indica
  "Date Time: 16-04-2018".
- Total: **305 registros**, 36 de ellos sin código postal.
- El archivo `localidades-5.csv` tiene la codificación dañada (por ejemplo,
  `RÃ­o` en lugar de `Río`). El otro recurso del mismo dataset,
  *Localidades y población* (`localidades-4.csv`), tiene la codificación
  correcta y, corregida la codificación, el mismo contenido en las columnas
  de interés. Para la comparación se usó esa versión.

## 3. Comparación entre fuentes

Después de normalizar espacios, las dos fuentes coinciden en nombre,
departamento y código postal, salvo por estos registros:

| Datos Abiertos (2018) | IDE Mendoza (2025) | Tratamiento |
|---|---|---|
| Barrancas (Mal), Malargüe, 5613 | no existe | **Incluida** como registro complementario |
| Minacar, Malargüe, 5613 | no existe | **Incluida** como registro complementario |
| `Las loicas` | `Las Loicas` | Se usa el nombre de IDE |
| `Punta de Agua` (San Rafael) | `Punta del Agua` | Se usa el nombre de IDE |

## 4. Criterios aplicados

1. **Fuente principal:** IDE Mendoza.
2. **Incluidas:** las 266 localidades de IDE con un código postal del rango
   de Mendoza, más *Media Luna* y las 2 complementarias, lo que da
   **269 localidades**.
3. **Excluidas:** las 36 localidades sin código postal, documentadas en
   `localidades_excluidas.csv`.
4. Los códigos postales se usan **tal como vienen en la fuente**, sin corregirlos ni completarlos.
5. Los nombres de localidad **no se modificaron**, salvo la limpieza de espacios repetidos.

### 4.1 Registros con observaciones

| Localidad | Departamento | CP | Observación |
|---|---|---|---|
| Media Luna | General Alvear | 6279 | **Anomalía.** El código está fuera del rango usado en Mendoza (55xx–56xx) y pertenece a otra provincia. Las dos fuentes lo informan igual. Se carga tal cual, sin corregir. |
| Barrancas (Mal) | Malargüe | 5613 | Registro complementario tomado de Datos Abiertos (datos de 2018). No figura en la capa actual de IDE. |
| Minacar | Malargüe | 5613 | Registro complementario tomado de Datos Abiertos (datos de 2018). No figura en la capa actual de IDE. |
| Villa Seca | Maipú | 5517 | Hay dos localidades con el mismo nombre. Se distinguen por código postal y departamento. |
| Villa Seca | Tunuyán | 5563 | Ver la fila anterior. |

Otras observaciones:

- *Capital* y *Godoy Cruz* tienen una sola localidad cada uno en la fuente,
  que representa toda la ciudad.
- Algunos nombres de la fuente llevan sufijos para desambiguar, como
  `San José (T)` o `Barrancas (Mal)`. Se conservan sin cambios.
- Varias localidades comparten código postal. La tabla lo permite, porque no
  hay UNIQUE sobre `cod_postal`. Hay 72 códigos distintos en total.

## 5. Normalizaciones

| Normalización | Detalle |
|---|---|
| Nombres de departamento | La capa IDE trae 22 grafías distintas. **24 registros**, todos dentro del rango fid 268–304 (aunque no todos los registros de ese rango), usan `Junin`, `Maipu`, `Malargue` y `San Martin`. Se unificaron a `Junín`, `Maipú`, `Malargüe` y `San Martín`. Resultado: 18 departamentos. |
| Espacios repetidos o en los extremos | Se eliminaron en todos los campos de texto. En los nombres de localidad, el único caso fue `Colonia  Forestal Forrajera`, que quedó como `Colonia Forestal Forrajera`. |
| Denominación de Luján de Cuyo | La capa IDE nombra el departamento `Luján`. Se usa la denominación del TPI (Anexo B.3), `Luján de Cuyo`, en `departamentos.csv` y en la columna `departamento` de `localidades.csv` (19 localidades) y de `localidades_excluidas.csv` (3). El nombre de la localidad `Ciudad de Luján` no cambia: es el dato de la fuente. |
| Distrito vacío | Los fid 297 (*El Vivoron*, Maipú) y 299 (*Carapacho*, Malargüe) traen en la fuente `distrito = " "` (un solo espacio). Al limpiar los espacios, el distrito quedó vacío. Los dos registros están en la lista de excluidas porque no tienen código postal, así que el campo no afecta la carga. |
| Nombres de localidad | Sin otros cambios. Se mantienen mayúsculas, tildes y sufijos de la fuente. |
| Códigos postales | Sin cambios. Se convirtieron a texto de 4 dígitos para `CHAR(4)`. |

## 6. Resumen por departamento

| Departamento | IDE total | IDE con CP | Sin CP (excluidas) | Complementarias | **En `localidades.csv`** |
|---|---|---|---|---|---|
| Capital | 1 | 1 | 0 | 0 | **1** |
| General Alvear | 19 | 19 | 0 | 0 | **19** (incluye Media Luna) |
| Godoy Cruz | 1 | 1 | 0 | 0 | **1** |
| Guaymallén | 21 | 21 | 0 | 0 | **21** |
| Junín | 10 | 9 | 1 | 0 | **9** |
| La Paz | 7 | 7 | 0 | 0 | **7** |
| Las Heras | 22 | 20 | 2 | 0 | **20** |
| Lavalle | 23 | 23 | 0 | 0 | **23** |
| Luján de Cuyo | 22 | 19 | 3 | 0 | **19** |
| Maipú | 16 | 14 | 2 | 0 | **14** |
| Malargüe | 41 | 20 | 21 | 2 | **22** |
| Rivadavia | 15 | 15 | 0 | 0 | **15** |
| San Carlos | 11 | 11 | 0 | 0 | **11** |
| San Martín | 18 | 17 | 1 | 0 | **17** |
| San Rafael | 45 | 41 | 4 | 0 | **41** |
| Santa Rosa | 9 | 7 | 2 | 0 | **7** |
| Tunuyán | 12 | 12 | 0 | 0 | **12** |
| Tupungato | 10 | 10 | 0 | 0 | **10** |
| **Total** | **303** | **267** | **36** | **2** | **269** |

## 7. Validaciones realizadas

- Los encabezados son los esperados y todas las filas tienen la misma cantidad de columnas que el encabezado.
- `localidades.csv` tiene 269 filas, `encargados_auxiliares.csv` 269 y `localidades_excluidas.csv` 36.
- Todas las localidades tienen un `cod_postal` de 4 dígitos.
- No hay duplicados por (`nombre`, `departamento`) ni por (`nombre`, `cod_postal`).
- Aparecen los 18 departamentos.
- `nombre` mide como máximo 80 caracteres y los campos del encargado, como máximo 50.
- Hay 269 `dni` distintos y 269 `apellido` distintos. La relación entre encargados y localidades es 1 a 1 por la clave (`localidad`, `cod_postal`) y se verificó también con las filas mezcladas al azar, sin depender del orden.
- Ninguna localidad excluida figura en el CSV de carga.

## 8. Pendiente

- Script de carga de encargados y localidades, que **no** forma parte de esta entrega.
- Si en el futuro aparece una fuente oficial con los códigos postales de las
  36 localidades excluidas, podrán incorporarse.
- Confirmar con una fuente postal oficial el código de *Media Luna* (6279).
