# Etapa 1 — Normalización y decisiones de diseño

Este documento completa el DER (`DER_BODEGA-COMPLETO.drawio`), el esquema relacional
(`Esquema_Relacional_-_Bodegas_del_Atuel.docx`) y el diccionario de datos
(`Diccionario_de_Datos.pdf`). Explica por qué el esquema está en 3FN y justifica las
decisiones de diseño que pide la sección 5 de la consigna.

Todo lo que se menciona está implementado en `db/migrations/001_esquema.sql` y
`db/migrations/002_constraints.sql`.

---

## 1. Normalización hasta 3FN

### 1.1 Repaso de las formas normales

| Forma normal | Qué exige | Cómo se rompe |
|---|---|---|
| **1FN** | Cada celda tiene un solo valor (atómico) y no hay grupos repetidos. | Guardar varios teléfonos en una misma columna. |
| **2FN** | 1FN + ningún atributo no clave depende de **una parte** de una clave compuesta. | En `(id_comprobante, id_vino)`, guardar el nombre del vino (depende solo de `id_vino`). |
| **3FN** | 2FN + ningún atributo no clave depende de **otro atributo no clave** (sin dependencias transitivas). | En `cliente`, guardar el % de descuento (depende del tipo de cliente, no del cliente). |

### 1.2 Dependencias funcionales relevantes

| Dependencia funcional | Dónde quedó resuelta |
|---|---|
| `id_localidad → cod_postal, nombre, provincia, id_encargado` | Tabla `localidad` |
| `id_encargado → nombre, apellido, dni` | Tabla `encargado` (separada de la localidad) |
| `id_sala → calle, numero, dia_cierre_semanal, id_localidad` | Tabla `sala_de_ventas` |
| `id_finca → nombre, sup_total_ha, id_departamento` | Tabla `finca` |
| `id_departamento → nombre, provincia` | Tabla `departamento` |
| `(id_finca, num_parcela) → superficie, anio_plantacion, id_cepa` | Tabla `parcela` (entidad débil) |
| `(id_finca, num_parcela, campania) → num_lote, fecha_cosecha, kilos, bodega` | Tabla `lote_de_uva` + UNIQUE |
| `id_vino → cod_vino, nombre, tipo, añada, presentación, graduación, precio, id_bodega` | Tabla `vino` |
| `(id_vino, id_cepa) → porcentaje_corte` | Tabla `vino_cepa` |
| `id_tipo_cliente → nombre, porcentaje_descuento` | Tabla `tipo_cliente` |
| `id_cliente → nombre, documento, dirección, fecha_alta, id_localidad, id_tipo_cliente` | Tabla `cliente` |
| `(id_comprobante, id_vino) → cantidad, precio_unitario_venta, descuento_aplicado, subtotal_renglon` | Tabla `detalle_comprobante` |
| `(id_sala, id_vino) → cantidad` | Tabla `stock_sala` |

### 1.3 Por qué está en 1FN

- Todos los atributos son atómicos. La dirección se separó en `calle` y `numero`.
- El transportista puede tener **varios e-mails y varios teléfonos** (atributos
  multivaluados). En lugar de guardarlos en una columna con comas, se crearon las tablas
  `transportista_email` y `transportista_telefono`, con clave
  `(id_transportista, email)` y `(id_transportista, telefono)`.
- Las relaciones N:M (vino–cepa, vino–maridaje, transportista–localidad) tienen su propia
  tabla. No hay listas dentro de una fila.

### 1.4 Por qué está en 2FN

La 2FN solo se puede romper en tablas con **clave compuesta**. Las revisamos:

| Tabla | Clave | ¿Algún atributo depende de una sola parte? |
|---|---|---|
| `parcela` | `(id_finca, num_parcela)` | No. La superficie, el año y la cepa son de esa parcela; el número solo no identifica nada, porque cada finca empieza su numeración. |
| `vino_cepa` | `(id_vino, id_cepa)` | No. El porcentaje depende del par: el Malbec es 85 % en un vino y 100 % en otro. |
| `detalle_comprobante` | `(id_comprobante, id_vino)` | No. El nombre del vino **no** se guarda acá. El `precio_unitario_venta` parece depender solo del vino, pero no es así: es el precio **en el momento de esa venta**, que puede ser distinto del precio actual. Por eso depende de la clave completa. |
| `stock_sala` | `(id_sala, id_vino)` | No. La cantidad depende de la sala y del vino a la vez. |
| `vino_maridaje`, `transportista_localidad`, `transportista_email`, `transportista_telefono` | Clave = todas las columnas | No tienen atributos no clave. |

El resto de las tablas tiene clave simple (un `id_...`), así que cumplen la 2FN
automáticamente.

### 1.5 Por qué está en 3FN (dependencias transitivas eliminadas)

Estos son los casos donde aparecía una dependencia transitiva y cómo la sacamos:

1. **Localidad → encargado regional.** La consigna dice que el encargado depende de la
   localidad, no de la sala. Si guardáramos los datos del encargado en `sala_de_ventas`,
   tendríamos `id_sala → id_localidad → encargado` (transitiva), y en una localidad con
   dos salas el encargado quedaría repetido y podría quedar inconsistente.
   **Solución:** la sala solo tiene `id_localidad`; la localidad tiene `id_encargado`
   (con UNIQUE, porque cada encargado está a cargo de una sola localidad) y los datos de
   la persona están en `encargado`. Esto cubre **RN-02**.

2. **Tipo de cliente → porcentaje de descuento.** El descuento no depende del cliente,
   depende de su tipo (socio 10 %, distribuidor 20 %, exportador 30 %). Si lo guardáramos
   en `cliente`, habría `id_cliente → tipo → descuento`.
   **Solución:** tabla `tipo_cliente (id_tipo_cliente, nombre, porcentaje_descuento)`; el
   cliente solo guarda `id_tipo_cliente`. La función `fn_descuento_cliente` lo lee de ahí
   (**RN-06**).

3. **Finca → departamento → provincia.** La provincia depende del departamento, no de la
   finca. **Solución:** tabla `departamento (nombre, provincia)` y la finca guarda
   `id_departamento`.

4. **Sala → empleado.** Los datos de la sala no se repiten en `empleado`; el empleado solo
   guarda `id_sala` (FK NOT NULL, **RN-03**).

5. **Vino → bodega.** Los datos de la bodega (CUIT, razón social, domicilio) están en
   `bodega`; el vino solo guarda `id_bodega`.

> ✏️ **Para revisar:** `localidad` guarda la `provincia` como texto y no está vinculada con
> `departamento`. No rompe la 3FN (la provincia depende directamente de la localidad),
> pero si el profe pregunta, la respuesta es que las localidades y los departamentos se
> cargan desde catálogos distintos y la consigna no pide relacionarlos.

---

## 2. Decisiones de diseño

### 2.1 Jerarquía de clientes

La consigna da tres opciones. Comparación:

| Estrategia | Ventajas | Desventajas |
|---|---|---|
| **Tabla única** con columna de tipo | Una sola tabla, consultas simples. | Muchas columnas en NULL (zona y habilitación solo para distribuidores, país solo para exportadores). No se puede poner NOT NULL en esas columnas. |
| **Una tabla por subtipo** (sin supertipo) | Cada tabla tiene solo sus columnas. | Los datos comunes se repiten en tres tablas. Un comprobante tendría que apuntar a tres tablas distintas, lo que no se puede hacer con una sola FK. |
| **Supertipo + subtipos** ✅ | Los datos comunes están una sola vez. Cada subtipo tiene sus columnas con NOT NULL. El comprobante apunta a `cliente` con una FK normal. | Para ver todos los datos de un cliente hay que hacer un JOIN. |

**Elegimos supertipo + subtipos:**

- `cliente`: datos comunes (nombre o razón social, documento, dirección, localidad, fecha
  de alta) y `id_tipo_cliente`.
- `socio`, `distribuidor` y `exportador`: su PK es `id_cliente`, que también es FK a
  `cliente`. `distribuidor` agrega zona y número de habilitación (UNIQUE); `exportador`
  agrega el país de destino.
- `permiso_exportacion` apunta a `exportador` (no a `cliente`). Así la base garantiza que
  solo un exportador puede tener permisos (**RN-07**).

La razón principal es que `comprobante` necesita apuntar a cualquier cliente con una sola
FK, y que los atributos propios de cada subtipo pueden ser obligatorios (NOT NULL).

### 2.2 Claves naturales o subrogadas

**Criterio general:** todas las tablas principales usan una **clave subrogada** (`SERIAL`),
y la clave natural queda como **UNIQUE**.

| Tabla | PK (subrogada) | Clave natural (UNIQUE) | Por qué no usar la natural como PK |
|---|---|---|---|
| `bodega` | `id_bodega` | `cuit` | El CUIT es largo (11 caracteres) y se repetiría en cada vino, ingreso y lote. Si se carga mal, corregirlo obligaría a cambiarlo en todas las tablas hijas. |
| `transportista` | `id_transportista` | `cod_transporte`, `cuit` | Igual que la bodega. |
| `empleado` | `id_empleado` | `cuit` | Igual que la bodega. |
| `vino` | `id_vino` | `cod_vino` y `(nombre_comercial, anada, presentacion_ml)` | El código es texto y lo define la empresa; un entero es más chico y más rápido para los JOIN con los 500.000 renglones de venta. |
| `localidad` | `id_localidad` | — | **El código postal no es único:** en Argentina varias localidades comparten el mismo CP. Por eso no puede ser clave. |
| `cliente` | `id_cliente` | `(tipo_documento, num_documento)` | El documento tiene dos partes (tipo y número); una clave de dos columnas se repetiría en 150.000 comprobantes. |
| `comprobante`, `ingreso`, `transferencia`, `lote_de_uva` | `id_...` | `num_comprobante`, `cod_ingreso`, `num_solicitud`, `num_lote` | El número visible lo maneja el negocio; el id interno no cambia nunca. |

**Excepciones (claves naturales o compuestas a propósito):**

- `parcela (id_finca, num_parcela)`: es una **entidad débil**; la consigna pide que su clave
  incluya la finca.
- Tablas de relación (`vino_cepa`, `vino_maridaje`, `transportista_localidad`,
  `detalle_comprobante`, `stock_sala`): la clave es la combinación de las FK, porque el par
  no se puede repetir (por ejemplo, un vino aparece una sola vez por comprobante).
- `stock_deposito (id_vino)`: hay un solo depósito central, así que el vino solo alcanza
  para identificar la fila.

Como las PK subrogadas no cambian nunca, todas las FK llevan `ON UPDATE RESTRICT`
(ver 2.5).

### 2.3 Tipos de datos

| Dato | Tipo usado | Por qué |
|---|---|---|
| Dinero (precios, salarios, importes) | Dominio `dom_dinero` = `DECIMAL(12,2)` con `CHECK >= 0` | `DECIMAL` es exacto. `FLOAT` redondea en binario (0,1 + 0,2 ≠ 0,3) y en importes eso no se acepta. **Ningún importe usa FLOAT.** |
| Porcentajes | Dominio `dom_porcentaje` = `DECIMAL(5,2)` entre 0 y 100 | Corte de cepas y descuentos. |
| Cantidades y stock | Dominio `dom_cantidad` = `INTEGER >= 0` | Garantiza que el stock nunca sea negativo (**RN-09**). |
| CUIT | Dominio `dom_cuit` = `CHAR(11)`, solo 11 dígitos | Se reutiliza en bodega, transportista y empleado. |
| E-mail | Dominio `dom_email` | Control básico de formato. |
| Fechas | `DATE` (y `TIMESTAMP` en la auditoría) | La auditoría necesita la hora exacta del cambio de precio. |
| Estados de ingreso y transferencia | `ENUM estado_movimiento` (`en_confeccion`, `terminado`, `procesado`) | No es texto libre: no se puede escribir un estado que no existe (**RN-10**, **RN-11**). |
| Otros valores fijos | `ENUM` `tipo_vino`, `tipo_cepa`, `dia_semana`, `tipo_documento` | Mismo motivo. |

Los **dominios** permiten escribir la regla una sola vez y usarla en muchas columnas.

### 2.4 Atributos derivados

Un atributo derivado es uno que se puede calcular a partir de otros. Para cada uno
decidimos si se guarda o se calcula, y cómo se mantiene consistente.

| Atributo | ¿Se guarda? | Cómo se garantiza que esté bien |
|---|---|---|
| `detalle_comprobante.precio_unitario_venta` | Sí | No es realmente derivado: es el precio **histórico**. Si después sube el precio del vino, la venta vieja tiene que seguir mostrando el precio que se cobró. Lo completa el trigger `trg_detalle_validar` copiando el precio vigente del vino; no se carga a mano. |
| `detalle_comprobante.descuento_aplicado` | Sí | Lo completa `trg_detalle_validar` con `fn_descuento_cliente` (**RN-06**). Se guarda para conservar el descuento que tenía el cliente al momento de la venta. |
| `detalle_comprobante.subtotal_renglon` | Sí | Lo calcula `trg_detalle_validar`: cantidad × precio × (1 − descuento/100). |
| `comprobante.subtotal`, `descuento`, `total` | Sí | Los recalcula `trg_comprobante_totales` (usa `fn_total_comprobante`) cada vez que cambia un renglón. Además, `CHECK (total = subtotal - descuento)` (**RN-08**). Se guardan porque los reportes de ventas leen 150.000 comprobantes y recalcularlos cada vez sumando 500.000 renglones sería muy lento. |
| `stock_sala.cantidad`, `stock_deposito.cantidad` | Sí | Solo los modifican los triggers de venta y los procedimientos `sp_procesar_ingreso` y `sp_procesar_transferencia`. El rol de la API **no tiene permiso** de escribir directamente en estas tablas (`007_roles.sql`). |
| Stock total por vino (depósito + salas) | No | Se calcula con la vista `v_stock_total_vino`. |
| Antigüedad del empleado | No | Se calcula con `fn_antiguedad_anios`, porque cambia todos los días. |
| Ventas mensuales por sala | No (vista materializada) | `mv_ventas_mensuales_sala`; se actualiza con `REFRESH`. |

**Criterio:** guardamos lo que hace falta para conservar el historial (precio y descuento
del momento) o para que los reportes sean rápidos, y en esos casos **la base** mantiene la
consistencia con triggers y CHECK. Ni la API ni el front calculan importes.

### 2.5 Acciones referenciales (ON DELETE / ON UPDATE)

Están en `002_constraints.sql`, sección 2.

**ON UPDATE RESTRICT en todas las FK.** Las PK son subrogadas y no deberían cambiar nunca;
si alguien intenta cambiar una, se rechaza.

**ON DELETE RESTRICT** (no se puede borrar el padre si tiene hijos):

| Padre | Hijos que lo bloquean | Motivo |
|---|---|---|
| `vino` | renglones de venta, ingreso y transferencia, stock, auditoría | **RN-14.** Un vino con movimientos no se borra. La auditoría de precios tampoco puede perderse. |
| `bodega` | vinos, ingresos, lotes de uva | **RN-14.** |
| `transportista` | ingresos | **RN-14.** |
| `cliente`, `sala_de_ventas` | comprobantes, empleados, stock, transferencias | No se pierde el historial de ventas. |
| Catálogos (`cepa`, `maridaje`, `localidad`, `departamento`, `encargado`, `tipo_cliente`) | Lo que los use | Un dato de catálogo en uso no se borra. |

**ON DELETE CASCADE** (si se borra el padre, se borran los hijos). Solo donde el hijo no
tiene sentido sin el padre:

| Padre → hijo | Motivo |
|---|---|
| `comprobante` → `detalle_comprobante` | Un renglón no existe sin su comprobante. |
| `ingreso` → `renglon_ingreso`, `transferencia` → `renglon_transferencia` | Igual. |
| `vino` → `vino_cepa`, `vino_maridaje` | La composición y los maridajes son parte de la ficha del vino. |
| `transportista` → e-mails, teléfonos, localidades que cubre | Son atributos del transportista. |
| `cliente` → `socio` / `distribuidor` / `exportador`, y `exportador` → `permiso_exportacion` | El subtipo es parte del mismo cliente. |
| `finca` → `parcela` | La parcela es una entidad débil: no existe sin su finca. |
| `lote_de_uva` → `analisis_calidad` | El análisis pertenece al lote. |

**Ojo:** el CASCADE no sirve para saltarse un RESTRICT. Por ejemplo, borrar un
transportista borraría sus e-mails en cascada, pero si tiene ingresos, el RESTRICT de
`ingreso` frena todo el borrado. Lo mismo pasa con un cliente que tiene comprobantes o
con una parcela que tiene lotes.

---

## 3. Cómo se verifica

- `001_esquema.sql` y `002_constraints.sql` corren de punta a punta sobre una base vacía
  (`DROP SCHEMA IF EXISTS bodegas CASCADE` al principio).
- Cada regla tiene un caso en `tests/db_tests.sql` (ver `docs/etapa2_integridad.md`).
