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

## 3. Tabla comparativa

*(Completar con los datos de `docs/etapa4/antes.txt` y `despues.txt`: tiempo de `Execution Time`, tipo de recorrido y filas leídas de la tabla principal.)*

| Consulta | Tiempo antes | Tiempo después | Recorrido antes | Recorrido después | Filas leídas antes → después |
|---|---|---|---|---|---|
| S3 | | | Seq Scan on comprobante | Bitmap Index Scan (`idx_comprobante_sala_fecha`) | |
| S4 | | | Seq Scan on renglon_transferencia | Bitmap Index Scan (`idx_renglon_transf_vino`) | |
| S8 | | | Seq Scan on comprobante | Index Only Scan (`idx_comprobante_fecha_cubriente`) | |
| S12 | | | Seq Scan on comprobante (una vez por cliente) | Bitmap Index Scan (`idx_comprobante_cliente`) | |

## 4. Índice evaluado y descartado

Se evaluó `cliente (id_tipo_cliente)` y se descartó. La columna tiene solo 3 valores, y la mayoría de los clientes son socios (baja selectividad). Para buscar los socios, el planificador prefiere leer la tabla completa (*Seq Scan*) antes que usar el índice, como muestra `indices_no_usados.txt`. Tenerlo solo agregaría costo a cada alta o modificación de cliente.

## 5. Costo de escritura

`costo_escritura.txt` mide cuánto tarda insertar todos los renglones de venta en una tabla sin índices y en otra con la PK y el índice de la FK.

| Inserción de detalle_comprobante | Tiempo |
|---|---|
| Sin índices | *(completar)* |
| Con PK + índice de FK | *(completar)* |

Cada índice se actualiza en cada INSERT, UPDATE o DELETE, así que la escritura se vuelve más lenta. Por eso se crean solo los índices que mejoran consultas concretas. En una carga masiva conviene crear los índices después de cargar los datos.

## 6. Casos en que el planificador no usa un índice

1. **S5 con el índice parcial.** La tabla `transferencia` es chica y ocupa pocas páginas. Leerla entera es más barato que pasar por el índice, así que el plan muestra *Seq Scan* aunque el índice exista. Cuando la tabla crezca, el planificador lo va a empezar a usar.
2. **S1 con `idx_detalle_vino`.** El ranking suma todos los renglones de venta. Si hay que leer la tabla completa, el índice no ahorra nada y el plan hace *Seq Scan*.
