
# Front de Bodegas del Atuel (Etapa 8): archivos estáticos + proxy /api.
# servidor.py usa solo la biblioteca estándar: no hay dependencias que instalar.
FROM python:3.12-slim

WORKDIR /app
COPY . .

# Sin búfer para que los logs aparezcan en "docker compose logs" al instante.
ENV PYTHONUNBUFFERED=1 \
    FRONT_HOST=0.0.0.0 \
    FRONT_PORT=5173 \
    API_URL=http://api:8000

EXPOSE 5173

CMD ["python", "servidor.py"]
