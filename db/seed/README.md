# db/seed - Carga masiva (Etapa 3)

Llena la base con datos coherentes: catálogos reales desde CSV y el resto generado
con Faker, con semilla fija (dos ejecuciones dan los mismos datos).
Las decisiones y los resultados están en [`docs/etapa3_carga_masiva.md`](../../docs/etapa3_carga_masiva.md).

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `carga_masiva.py` | Genera los datos y los carga en la base. Al final corre `validaciones.sql` |
| `validaciones.sql` | Consultas de control: conteos, huérfanas, stock, totales y fechas |
| `medir_insercion.py` | Compara insertar fila por fila contra insertar por lotes |
| `csv/` | Catálogos reales: cepas, maridajes, departamentos, localidades de Mendoza y tipos de cliente |
| `csv/localidades_excluidas.csv` | Solo documentación: las 36 localidades sin código postal que no se cargan |

## Cómo ejecutarlo

Requisitos: Docker con el contenedor levantado (`docker compose up -d`), el archivo `.env`
(copiado de `.env.example`) y [uv](https://docs.astral.sh/uv/) para las dependencias de Python.

```sh
# 1. Dependencias de Python (psycopg y Faker, versiones fijas en pyproject.toml)
uv sync

# 2. Base vacía con las migraciones 001 a 007 (001 borra y recrea el esquema)
for f in db/migrations/00*.sql; do
  docker exec -i bodegas_atuel_db sh -c 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "$f"
done

# 3. Carga completa (unos minutos). Para una prueba rápida: ... carga_masiva.py 2000
uv run python db/seed/carga_masiva.py

# 4. Comparar inserción fila por fila contra lotes (no deja datos)
uv run python db/seed/medir_insercion.py

# 5. Volcado de la base cargada
docker exec bodegas_atuel_db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip' > dump_completo.sql.gz
```

El script se conecta con los datos del `.env` (host `localhost`, puerto `POSTGRES_PORT`).
Para usar otra base: `POSTGRES_DB=otra_base uv run python db/seed/carga_masiva.py`.
Si la base ya tiene datos, el script no hace nada: hay que recrearla con las migraciones.
