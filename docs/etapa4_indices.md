# Etapa 4 – Índices y rendimiento

## 1. Cómo se reproducen las mediciones

Con el contenedor levantado y la carga masiva de la etapa 3 hecha, desde la carpeta del repositorio (Git Bash):

```
bash db/rendimiento/etapa4.sh
```

El script hace todo en orden y deja los planes completos en `docs/etapa4/` (anexo):

| Paso | Qué hace | Archivo de resultado |
|---|---|---|
| 2 | Borra los índices de la etapa 4 (si existían), ejecuta `VACUUM ANALYZE` y mide las consultas solo con los índices de PK y UNIQUE | `antes.txt` |
| 4 | Crea los índices (`db/migrations/008_indices.sql`) y vuelve a ejecutar `ANALYZE` | — |
| 5 | Repite las mismas mediciones | `despues.txt` |
| 6 y 8 | Casos en que el planificador no usa un índice, e índice descartado | `indices_no_usados.txt` |
| 7 | Costo de escritura con y sin índices | `costo_escritura.txt` |

Las consultas medidas están en `db/rendimiento/medir.sql` (S3, S4, S8 y S12 de la sección 8), todas con `EXPLAIN (ANALYZE, BUFFERS)`.

## 2. Índices creados (`008_indices.sql`)

| Índice | Tipo pedido | Consulta | Justificación |
|---|---|---|---|
| `idx_comprobante_cliente (id_cliente)` | Clave foránea | S12 | S12 busca, para cada cliente, sus comprobantes. Sin índice, recorre todos los comprobantes una vez por cliente. |
| `idx_detalle_vino (id_vino)` | Clave foránea | Borrado de vinos, consultas por vino | La PK `(id_comprobante, id_vino)` permite buscar por comprobante, pero no por vino. Al borrar un vino, la FK debe comprobar que no tenga ventas. |
| `idx_comprobante_sala_fecha (id_sala, fecha)` | Compuesto | S3 | Filtra por una sala (igualdad) y un período (rango). |
| `idx_comprobante_fecha_cubriente (fecha) INCLUDE (id_sala, total)` | Variante con `INCLUDE` | S8 | S8 solo usa fecha, sala y total. Como están todas en el índice, se resuelve sin leer la tabla (*Index Only Scan*). |
| `idx_transferencia_pendiente (id_sala) WHERE estado <> 'procesado'` | Parcial | S5 | Solo indexa las transferencias pendientes, que son pocas y las que se consultan seguido. No crece con el historial. |
| `idx_renglon_transf_vino (id_vino)` | Clave foránea | S4 | S4 filtra los renglones de transferencia por vino. |

**Orden de las columnas del índice compuesto.** Va primero `id_sala`, que se compara por igualdad, y después `fecha`, que se compara por rango. Así el índice entra directo a las ventas de esa sala y dentro de ella recorre solo las fechas pedidas. Con el orden inverso `(fecha, id_sala)`, recorrería todas las ventas del período, de todas las salas, y recién después filtraría la sala. Cuanto más largo es el período, más diferencia hay.

**Cuándo se usa el compuesto.** En S3, que pide solo la última semana, el planificador prefiere `idx_comprobante_fecha_cubriente`: la fecha sola ya deja pocas filas (2.112 de 150.000) y después filtra la sala. Con un período largo, en cambio, usa el compuesto. Por ejemplo, las ventas de la sala 3 en el último año se resuelven con *Index Only Scan* sobre `idx_comprobante_sala_fecha` en 0,32 ms. El planificador elige el índice según cuántas filas espera leer.

## 3. Tabla comparativa

Datos de `docs/etapa4/antes.txt` y `despues.txt` (base con 150.000 comprobantes y 510.310 renglones; mediciones del 08/11/2026).

| Consulta | Tiempo antes | Tiempo después | Recorrido antes | Recorrido después | Filas leídas antes → después |
|---|---:|---:|---|---|---|
| S3 | 12,3 ms | 0,9 ms | Parallel Seq Scan on comprobante | Index Scan (`idx_comprobante_fecha_cubriente`) | 150.000 → 2.112 |
| S4 | 0,36 ms | 0,55 ms | Index Scan (`uq_renglon_transferencia_vino`), una vez por cada una de las 35 transferencias recientes | Bitmap Index Scan (`idx_renglon_transf_vino`) | 35 búsquedas → 66 filas |
| S8 | 17,1 ms | 2,3 ms | Parallel Seq Scan on comprobante | Index Only Scan (`idx_comprobante_fecha_cubriente`), sin leer la tabla | 150.000 → 8.136 |
| S12 | 202.404 ms (3 min 22 s) | 499 ms | Seq Scan on comprobante, repetido 20.930 veces | Bitmap Index Scan (`idx_comprobante_cliente`), 20.930 veces | unas 3.100 millones → unas 167.000 |

Mejoran S3, S8 y S12. La diferencia más grande está en S12 (unas 400 veces más rápida): sin índice sobre la clave foránea `comprobante.id_cliente`, por cada cliente se recorren los 150.000 comprobantes; con el índice se va directo a los pocos comprobantes de ese cliente.

**S4 no mejora.** En S4 el filtro que más descarta es la fecha: en los últimos 15 días hubo solo 35 transferencias. Sin el índice nuevo, la base ya lo resolvía bien buscando el vino en esas 35 transferencias con el índice UNIQUE `(id_transferencia, id_vino)` de la etapa 2. Con `idx_renglon_transf_vino`, el planificador prefiere leer todas las transferencias del vino (66 renglones) y después filtrar la fecha, que resulta apenas más lento (0,2 ms de diferencia). El índice igual se mantiene porque `id_vino` es clave foránea: al borrar un vino, la base tiene que comprobar que no tenga transferencias (RN-14), y sin este índice recorrería toda la tabla.

## 4. Índice evaluado y descartado

Se evaluó `cliente (id_tipo_cliente)` y se descartó. La columna tiene solo 3 valores, y la mayoría de los clientes son socios (baja selectividad). Para buscar los socios, el planificador prefiere leer la tabla completa (*Seq Scan*) antes que usar el índice, como muestra `indices_no_usados.txt`. Tenerlo solo agregaría costo a cada alta o modificación de cliente.

## 5. Costo de escritura

`costo_escritura.txt` mide cuánto tarda insertar todos los renglones de venta en una tabla sin índices y en otra con la PK y el índice de la FK.

| Inserción de los 510.310 renglones de detalle_comprobante | Tiempo |
|---|---:|
| Sin índices | 0,93 s |
| Con PK + índice de FK | 2,69 s |

Con dos índices, la misma inserción tarda casi tres veces más. Cada índice se actualiza en cada INSERT, UPDATE o DELETE, así que la escritura se vuelve más lenta. Por eso se crean solo los índices que mejoran consultas concretas. En una carga masiva conviene crear los índices después de cargar los datos.

## 6. Casos en que el planificador no usa un índice

Resultados en `docs/etapa4/indices_no_usados.txt`.

1. **S1 con `idx_detalle_vino`.** El ranking suma todos los renglones de venta. Como hay que leer la tabla completa, el índice no ahorra nada y el plan hace *Parallel Seq Scan* sobre los 510.310 renglones (78 ms), aunque el índice exista.
2. **El índice descartado `cliente (id_tipo_cliente)`.** Buscando los socios, el plan hace *Seq Scan* aunque el índice exista: los socios son 16.942 de 20.000 clientes (85 %), así que leer la tabla entera es más barato (baja selectividad).
3. **S3 y el índice compuesto** (ver sección 2): para la última semana el planificador prefiere el índice de `fecha`, que deja menos filas.
4. **S4** (ver sección 3): el índice se usa, pero no conviene, porque el filtro por fecha ya deja muy pocas filas.

En cambio, el índice parcial **sí se usa** en S5 (*Bitmap Index Scan* sobre `idx_transferencia_pendiente`): de 1.785 transferencias, solo 10 están pendientes, así que el índice es chico y muy selectivo. Es el caso de uso típico de un índice parcial.
