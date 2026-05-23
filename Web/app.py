import os
from flask import Flask, send_from_directory

app = Flask(__name__, static_folder='.', static_url_path='')


@app.route('/')
def index():
    return send_from_directory('.','index.html')


# Captura cualquier ruta y sirve el archivo desde web/
# Esto permite que /dashboard.html, /css/styles.css, /data/consumo_por_zona.json
# se resuelvan correctamente sin rutas explícitas por cada archivo.
@app.route('/<path:filename>')
def serve_file(filename):
    return send_from_directory('.',filename)


if __name__ == '__main__':
    # PORT es inyectado por Render en producción.
    # En local corre en 5000 si PORT no está definida.
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_ENV') != 'production'
    app.run(host='0.0.0.0', port=port, debug=debug)