# Etapa 5 - Consultas SQL

Las 30 consignas de la sección 8 están en [`consultas/`](../consultas/), cada una con su
código, el enunciado y la estrategia en un comentario.

| Archivo | Consignas |
|---|---|
| `select.sql` | S1 a S12 |
| `update.sql` | U1 a U6 |
| `insert.sql` | I1 a I6 |
| `delete.sql` | D1 a D6 |

Cómo ejecutar un archivo (desde la raíz del repo, con la base cargada):

```sh
docker exec -i bodegas_atuel_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < consultas/select.sql
```

## Criterios

- **Modificaciones en transacción:** cada UPDATE, INSERT y DELETE corre entre `BEGIN` y
  `ROLLBACK`, con una consulta de control antes y otra después. Se ve el efecto y la base
  queda como estaba.
- **Fechas relativas:** "la última semana", "el último trimestre", etc. se calculan desde
  `CURRENT_DATE`. Los datos llegan hasta el 06/11/2026, así que esas consultas dan resultados
  si se ejecutan cerca de esa fecha. Para otra fecha, se recarga la base cambiando `FECHA_FIN`
  en `db/seed/carga_masiva.py`.
- **Parámetros:** se usan valores reales de los datos y están marcados con `<- parámetro`.

## Herramientas usadas

| Herramienta | Consignas |
|---|---|
| JOIN, GROUP BY, ORDER BY, LIMIT | S1, S3, S4, S8 |
| LEFT JOIN (para contar también los ceros) | S5, I1 |
| HAVING con subconsulta (para mostrar empates) | S7 |
| Subconsultas con IN, escalares y correlacionadas | S9, S10, U3, U5, U6, D1, D3 a D6 |
| NOT EXISTS (anti-join) | S6, S12b, D2, D4, D6 |
| Doble NOT EXISTS (división relacional) | S2, S12a |
| CTE (`WITH`) | S10 |
| Funciones de ventana (`RANK() OVER`, `SUM() OVER`) | S11 |
| Funciones de la etapa 2 | U1, U2, D3 (`fn_total_comprobante`, `fn_antiguedad_anios`), I3 |

## Decisiones y lo que se observó

| Consigna | Qué pasa |
|---|---|
| U1 | Los triggers ya mantienen los totales al día: hay 0 comprobantes mal calculados antes y después. Además, el trigger del comprobante recalcula subtotal y descuento en cada UPDATE (RN-08) |
| U3, U5 | Cada cambio de precio dispara el trigger de auditoría (RN-13): en U3, 20 vinos generan 20 filas nuevas en `auditoria_precio` |
| U4 | Un solo UPDATE con CASE: el UPDATE evalúa todas las filas con los valores de antes, así que una sala que pasa de lunes a miércoles no vuelve a cambiar |
| U5 | Se toman los 10 menos vendidos entre los vinos que tuvieron ventas (los que nunca se vendieron empatan en 0) |
| U6 | El descuento está en `tipo_cliente`, no en cada cliente. Se crea el tipo "Exportador Premium" (35 %) y se pasa a ese tipo a los exportadores con más de 3 permisos; desde ahí el trigger de venta les aplica el 35 % |
| I3 | Los renglones se insertan con precio, descuento y subtotal en 0: el trigger de la venta los completa y otro calcula el total, que coincide con `fn_total_comprobante` |
| D1, D5 | Los renglones se borran por ON DELETE CASCADE. El stock no cambia: borrar un documento entero es depurar historial, no una devolución |
| D2 | Con los datos cargados todas las cepas se usan; para ver el efecto se agrega una cepa sin uso dentro de la transacción |
| S12a | Si la bodega no tuviera vinos, la división devolvería a todos los clientes ("no existe un vino que no hayan comprado" es verdadero cuando no hay vinos) |
