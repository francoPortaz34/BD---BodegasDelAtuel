"""Servidor de desarrollo del front de Bodegas del Atuel (Etapa 7).

- Sirve los archivos estáticos de esta carpeta.
- Reenvía las peticiones /api/* a la API REST (proxy), así el navegador habla
con un único origen y la API no necesita habilitar CORS.

Solo usa la biblioteca estándar de Python (no hay que instalar nada).

Uso:
    python front/servidor.py      (desde la raíz del repositorio)
    python servidor.py            (desde front/)
Variables de entorno opcionales:
    API_URL     URL de la API          (por defecto http://127.0.0.1:8000)
    FRONT_HOST  dirección de escucha   (por defecto 127.0.0.1; 0.0.0.0 en Docker)
    FRONT_PORT  puerto del front       (por defecto 5173)
"""

import http.server
import json
import os
import urllib.error
import urllib.request
from functools import partial
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
API_URL = os.environ.get("API_URL", "http://127.0.0.1:8000").rstrip("/")
HOST = os.environ.get("FRONT_HOST", "127.0.0.1")
PUERTO = int(os.environ.get("FRONT_PORT", "5173"))
PREFIJO = "/api"

# Tipos MIME fijos: en Windows el registro puede asociar .js a text/plain y el
# navegador rechaza los módulos ES servidos con ese tipo.
TIPOS = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".svg": "image/svg+xml",
    ".json": "application/json",
}


class Manejador(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, **TIPOS}

    def end_headers(self):
        # En desarrollo no se cachea: cada recarga trae los archivos actuales
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        if self._es_api():
            self._reenviar()
        else:
            super().do_GET()

    def do_POST(self):
        self._solo_api()

    def do_PUT(self):
        self._solo_api()

    def do_DELETE(self):
        self._solo_api()

    def _es_api(self):
        return self.path == PREFIJO or self.path.startswith(PREFIJO + "/") \
            or self.path.startswith(PREFIJO + "?")

    def _solo_api(self):
        if self._es_api():
            self._reenviar()
        else:
            self._json(405, {"error": "Método no permitido"})

    def _reenviar(self):
        destino = API_URL + (self.path[len(PREFIJO):] or "/")
        largo = int(self.headers.get("Content-Length") or 0)
        cuerpo = self.rfile.read(largo) if largo else None

        peticion = urllib.request.Request(destino, data=cuerpo, method=self.command)
        peticion.add_header("Accept", "application/json")
        if self.headers.get("Content-Type"):
            peticion.add_header("Content-Type", self.headers["Content-Type"])

        try:
            with urllib.request.urlopen(peticion, timeout=30) as r:
                estado, tipo, datos = r.status, r.headers.get("Content-Type"), r.read()
        except urllib.error.HTTPError as e:
            # 4xx/5xx de la API: se devuelven tal cual (mensaje de la regla incluido)
            estado, tipo, datos = e.code, e.headers.get("Content-Type"), e.read()
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            self._json(502, {"error": f"No se pudo conectar con la API en {API_URL}"})
            return

        self.send_response(estado)
        self.send_header("Content-Type", tipo or "application/json")
        self.send_header("Content-Length", str(len(datos)))
        self.end_headers()
        self.wfile.write(datos)

    def _json(self, estado, contenido):
        datos = json.dumps(contenido, ensure_ascii=False).encode("utf-8")
        self.send_response(estado)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(datos)))
        self.end_headers()
        self.wfile.write(datos)


def main():
    manejador = partial(Manejador, directory=str(CARPETA))
    with http.server.ThreadingHTTPServer((HOST, PUERTO), manejador) as servidor:
        print(f"Front:  http://{HOST}:{PUERTO}", flush=True)
        print(f"Proxy:  {PREFIJO}/* -> {API_URL}/*", flush=True)
        try:
            servidor.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
