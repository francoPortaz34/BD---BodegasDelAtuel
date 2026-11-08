# Etapa 3 - Carga masiva de datos

Scripts en [`db/seed/`](../db/seed/) (cómo ejecutarlos: [`db/seed/README.md`](../db/seed/README.md)).

## 1. Catálogos reales (paso 1)

Los catálogos no se generan al azar: se cargan desde CSV.

| Archivo | Filas | Origen |
|---|---:|---|
| `cepas.csv` | 12 | TPI, Anexo B.1 (7 tintas y 5 blancas) |
| `maridajes.csv` | 8 | TPI, Anexo B.2 (con temperatura de servicio) |
| `departamentos.csv` | 18 | Los 18 departamentos de Mendoza (TPI, Anexo B.3) |
| `localidades.csv` | 269 | IDE Mendoza, capa oficial *Localidades*, con datos de Datos Abiertos Mendoza. Se excluyeron 36 localidades sin código postal (quedan listadas en `localidades_excluidas.csv`) |
| `tipos_cliente.csv` | 3 | Socio 10 %, Distribuidor 20 %, Exportador 30 % (RN-06) |

El resto (bodegas, vinos, clientes, empleados, transportistas, encargados, movimientos)
es ficticio y se genera con Faker (`es_AR`) y `random`.

## 2. Orden de carga (paso 2)

Primero las tablas que no dependen de ninguna; después las que apuntan a ellas.

```
1. cepa, maridaje, tipo_cliente, departamento, encargado
2. localidad (-> encargado)
3. sala_de_ventas (-> localidad)            empleado (-> sala)
4. bodega -> vino -> vino_cepa, vino_maridaje
5. finca (-> departamento) -> parcela (-> cepa) -> lote_de_uva (-> bodega) -> analisis_calidad
6. cliente (-> localidad, tipo_cliente) -> socio / distribuidor / exportador -> permiso_exportacion
7. transportista -> transportista_email, transportista_telefono, transportista_localidad
8. Movimientos, mes a mes:
     ingreso + renglon_ingreso          -> CALL sp_procesar_ingreso        (llena stock_deposito)
     transferencia + renglon_transf.    -> CALL sp_procesar_transferencia  (llena stock_sala)
     comprobante + detalle_comprobante  -> los triggers descuentan stock y calculan totales
9. Cambios de precio de 40 vinos       -> el trigger completa auditoria_precio
```

## 3. Script y reproducibilidad (pasos 3 y 4)

`carga_masiva.py` (Python + psycopg + Faker) usa semilla fija (`SEMILLA = 2026`) y una
fecha de fin fija (`FECHA_FIN`), así que dos ejecuciones generan los mismos datos.
Se comprobó cargando dos veces y comparando un hash (md5) de clientes, vinos,
comprobantes, renglones, transferencias y stock: dio igual.

Los datos son coherentes por construcción:
- Historial de ventas de enero de 2021 a noviembre de 2026 (71 meses).
- Cada mes: el día 1 llegan los ingresos al depósito, el día 2 las transferencias a las
  salas y del día 4 en adelante se vende. Las salas piden lo que van a vender en el mes
  (más un margen), y las bodegas mandan lo que las salas van a pedir.
- Un vino se vende recién desde marzo del año siguiente a su añada.
- Solo compran clientes ya dados de alta, y nunca en el día de cierre de la sala.
- Los porcentajes de corte suman 100. El vino 1 es el ejemplo de la consigna
  (Malbec Reserva 2021, 750 ml, $12.500, 85 % Malbec y 15 % Cabernet Sauvignon).
- 20 bodegas con 20 vinos cada una, más la bodega propia de la empresa ("Bodega del Atuel",
  id 21) con 3 vinos clásicos que están en el surtido de todas las salas. Cada sala vende
  esos 3 clásicos y otros 27 vinos elegidos al azar. Así las consultas S2 (vinos vendidos
  en todas las salas) y S12 (clientes que compraron todos los vinos de una bodega) tienen
  resultados para mostrar.
- Quedan 15 documentos sin procesar, para la vista de pendientes y la consulta S5.

## 4. Manejo de los triggers (paso 5)

**Decisión:** los triggers de la etapa 2 quedan **activos** durante la carga. El script no
escribe stock, precios, descuentos, totales ni auditoría: los calcula la base, igual que
en el uso normal. Así los datos cargados respetan las reglas porque la base misma las
controló (por ejemplo, ninguna venta pudo superar el stock de la sala).

**Única excepción:** se desactiva `trg_transferencia_fecha` (RN-11), porque obliga a que la
fecha de confección sea la de hoy y el historial necesita fechas pasadas:

```sql
ALTER TABLE transferencia DISABLE TRIGGER trg_transferencia_fecha;   -- al empezar
ALTER TABLE transferencia ENABLE TRIGGER trg_transferencia_fecha;    -- al terminar
```

**Riesgos y cómo se cubren:**
- Mientras está desactivado, una transferencia podría guardarse con cualquier fecha.
  Toda la carga corre en **una sola transacción**: si algo falla, se deshace todo y el
  trigger vuelve a quedar activo. Además, las consultas de control verifican que no haya
  fechas futuras ni ventas anteriores a la transferencia que abasteció la sala.
- Los id se cargan explícitos, así que al final se ajustan las secuencias con `setval`.

## 5. Carga por lotes y tiempos (paso 6)

Todas las tablas se cargan con `COPY` (por lotes). `medir_insercion.py` compara los métodos
insertando 20.000 filas en `encargado` (y deshace todo al final):

| Método | Tiempo | Filas por segundo |
|---|---:|---:|
| Fila por fila (`INSERT` por fila) | 12,79 s | 1.564 |
| Por lotes (`executemany`) | 0,75 s | 26.622 |
| Por lotes (`COPY`) | 0,11 s | 177.090 |

`COPY` es unas 110 veces más rápido que insertar fila por fila.

Tiempos de la carga completa (PostgreSQL 16 en Docker, notebook del grupo):

| Fase | Tiempo |
|---|---:|
| Catálogos y datos base | 2,0 s |
| Movimientos (ingresos, transferencias y 150.000 ventas) | 467,4 s |
| **Total** | **472 s (unos 8 minutos)** |

Casi todo el tiempo se va en los renglones de venta: cada uno dispara los triggers
de la venta (controlar stock, completar precio y descuento, descontar stock y recalcular
el comprobante). Es el costo de mantener las reglas activas durante la carga.

## 6. Resultado y consultas de control (paso 7)

| Tabla | Filas | | Tabla | Filas |
|---|---:|---|---|---:|
| detalle_comprobante | **510.310** | | analisis_calidad | 4.991 |
| comprobante | **150.000** | | permiso_exportacion | 3.049 |
| renglon_transferencia | 42.894 | | lote_de_uva | 2.499 |
| cliente | 20.000 | | distribuidor | 2.033 |
| renglon_ingreso | 18.213 | | transferencia | 1.785 |
| socio | 16.942 | | ingreso | 1.496 |
| exportador | 1.025 | | vino_maridaje | 762 |
| stock_sala | 750 | | vino_cepa | 570 |
| parcela | 462 | | vino | 403 |
| stock_deposito | 331 | | encargado / localidad | 269 |
| empleado | 123 | | transportista_localidad | 72 |
| finca | 60 | | auditoria_precio | 40 |
| sala_de_ventas | 25 | | bodega | 21 |
| transportista_email | 22 | | transportista_telefono | 25 |
| departamento | 18 | | transportista | 15 |
| cepa | 12 | | maridaje | 8 |
| tipo_cliente | 3 | | | |

Las 34 tablas tienen filas, 6 superan las 10.000 y 2 superan las 100.000.

`validaciones.sql` (se corre al final de la carga) dio **0 inconsistencias** en todos los controles:

| Control | Resultado |
|---|---|
| Filas huérfanas (renglones sin comprobante, comprobantes sin renglones, clientes sin subtipo) | 0 |
| Stock negativo en salas o depósito | 0 |
| Stock del depósito distinto de ingresado - transferido | 0 |
| Stock de sala distinto de transferido - vendido | 0 |
| Comprobantes cuyo total no es la suma de sus renglones | 0 |
| Renglones con descuento distinto del de su tipo de cliente | 0 |
| Ventas anteriores al alta del cliente o a la transferencia que abasteció la sala | 0 |
| Movimientos con fecha futura | 0 |
| Vinos cuyas cepas no suman 100 | 0 |

## 7. Volcado (paso 8)

`dump_completo.sql.gz` (7,5 MB) en la raíz del repositorio, generado con:

```sh
docker exec bodegas_atuel_db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip' > dump_completo.sql.gz
```

Se probó restaurarlo en una base nueva y los conteos y las sumas coinciden con la original
(150.000 comprobantes, 510.310 renglones, mismo total vendido y mismo stock):

```sh
createdb bodegas_restore
gunzip -c dump_completo.sql.gz | psql -d bodegas_restore
```

Nota: el contenedor necesita `shm_size: 256mb` (ya está en `docker-compose.yml`). Con los
64 MB que Docker da por defecto, las consultas en paralelo sobre las tablas grandes fallan.
