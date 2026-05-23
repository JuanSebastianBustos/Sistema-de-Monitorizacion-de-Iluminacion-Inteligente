"""
JSON 2/3 — consumo_por_zona.json
Requiere: JOIN con DimZona y DimTiempo.
Tiempo esperado: 10–30 segundos (GROUP BY sobre 1M filas con 2 JOINs).
Entregar al Integrante 2 apenas esté listo — desbloquea el mapa y la tabla.
"""
import pyodbc, pandas as pd, json, time
from pathlib import Path
from decimal import Decimal

# ─────────────────────────────────────────────────────────────
# CONFIGURACIÓN — ajustar antes de ejecutar
# ─────────────────────────────────────────────────────────────
SERVER   = r'.\SQLDEVELOPER'   # ← copiar de SSMS (barra de conexión)
DATABASE = 'IluminacionBogota_DW'          # ← nombre exacto de tu DW
OUTPUT_DIR = Path('data')                  # ← carpeta destino en el repo web
OUTPUT_DIR.mkdir(exist_ok=True)

# Cadena de conexión — Autenticación Windows (sin usuario/contraseña)
CONN_STR = (
    f'DRIVER={{SQL Server}};'
    f'SERVER={SERVER};'
    f'DATABASE={DATABASE};'
    f'Trusted_Connection=yes;'
)

def get_connection():
    """Abre la conexión al DW. Lanza un error claro si falla."""
    try:
        conn = pyodbc.connect(CONN_STR, timeout=10)
        print(f"✓ Conectado a {SERVER} → {DATABASE}")
        return conn
    except pyodbc.Error as e:
        print(f"✗ Error de conexión: {e}")
        print("  Verifica SERVER y DATABASE en la configuración.")
        raise

def decimal_default(obj):
    """Serializa Decimal a float para json.dumps. pyodbc devuelve DECIMAL como Decimal."""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Tipo no serializable: {type(obj)}")

def guardar_json(data, nombre_archivo):
    """Guarda el objeto como JSON con indentación legible."""
    ruta = OUTPUT_DIR / nombre_archivo
    with open(ruta, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2, default=decimal_default)
    tamanio_kb = ruta.stat().st_size / 1024
    print(f"✓ Guardado: {ruta}  ({tamanio_kb:.1f} KB)")

def generar_consumo_por_zona():
    t0 = time.time()
    conn = get_connection()

    query = """
        SELECT
            -- Identificación geográfica
            z.zona_id,
            z.nombre_zona,
            z.localidad,
            z.tipo_zona,
            CAST(z.latitud   AS FLOAT) AS latitud,
            CAST(z.longitud  AS FLOAT) AS longitud,
            z.poblacion,
            CAST(z.area_km2  AS FLOAT) AS area_km2,

            -- Métricas de consumo
            CAST(SUM(f.consumo_kwh)           AS FLOAT) AS kwh_total,
            CAST(SUM(ISNULL(f.costo_cop, 0))  AS FLOAT) AS costo_cop_total,
            CAST(AVG(f.nivel_lux)             AS FLOAT) AS lux_promedio,

            -- Lux óptimo ML — NULL si modelo no integrado aún
            CAST(AVG(f.lux_optimo_predicho)   AS FLOAT) AS lux_optimo_promedio,

            -- Anomalías
            SUM(CAST(f.anomalia_flag AS INT))            AS total_anomalias,

            -- Métricas de eficiencia normalizadas
            CAST(
                SUM(f.consumo_kwh) / NULLIF(z.poblacion, 0)
            AS FLOAT) AS kwh_por_habitante,
            CAST(
                SUM(f.consumo_kwh) / NULLIF(CAST(z.area_km2 AS FLOAT), 0)
            AS FLOAT) AS kwh_por_km2,

            -- Ahorro potencial ML
            CAST(
                SUM(CASE WHEN f.ahorro_kwh_estimado > 0
                         THEN f.ahorro_kwh_estimado ELSE 0 END)
            AS FLOAT) AS ahorro_kwh_estimado,

            -- Cumplimiento horario (replica DAX % Cumplimiento Horario)
            CAST(
                SUM(CASE WHEN t.es_horario_nocturno = 1
                              AND f.estado_encendido = 1
                         THEN 1.0 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN t.es_horario_nocturno = 1
                                  THEN 1.0 ELSE 0 END), 0)
                * 100
            AS FLOAT) AS pct_cumplimiento_horario,

            -- % encendidas total
            CAST(
                SUM(CAST(f.estado_encendido AS INT)) * 100.0 / COUNT(*)
            AS FLOAT) AS pct_encendidas

        FROM dbo.FactConsumoIluminacion f
        JOIN dbo.DimZona   z ON f.zona_id   = z.zona_id
        JOIN dbo.DimTiempo t ON f.tiempo_id = t.tiempo_id
        GROUP BY
            z.zona_id,
            z.nombre_zona,
            z.localidad,
            z.tipo_zona,
            z.latitud,
            z.longitud,
            z.poblacion,
            z.area_km2
        ORDER BY kwh_total DESC
    """

    print("Ejecutando consulta consumo_por_zona (puede tardar ~15-30 s)...")
    df = pd.read_sql(query, conn)
    conn.close()

    print(f"  → {len(df)} zonas recibidas")

    # ── validación ──────────────────────────────────────────
    if len(df) != 20:
        print(f"⚠️  ATENCIÓN: se esperaban 20 zonas, se recibieron {len(df)}.")
        print("   Verificar que DimZona tiene 20 registros y que todas tienen hechos.")

    campos_nulos = df.isnull().sum()
    campos_criticos = ['nombre_zona', 'kwh_total', 'lux_promedio', 'latitud', 'longitud']
    for campo in campos_criticos:
        if campos_nulos.get(campo, 0) > 0:
            print(f"⚠️  Campo crítico '{campo}' tiene valores NULL — revisar JOIN con DimZona")

    if df['lux_optimo_promedio'].isnull().all():
        print("ℹ️  lux_optimo_promedio es NULL en todas las zonas — normal si ML no está integrado.")
        print("   El campo se enviará como null en el JSON; la web lo manejará con un fallback.")

    # ── serialización ────────────────────────────────────────
    # Convertir numpy types a Python nativos para json.dumps
    registros = []
    for _, row in df.iterrows():
        obj = {}
        for col in df.columns:
            val = row[col]
            if pd.isna(val):
                obj[col] = None
            elif col in ('zona_id', 'poblacion', 'total_anomalias'):
                obj[col] = int(val)
            else:
                obj[col] = round(float(val), 4) if isinstance(val, float) else val
        registros.append(obj)

    guardar_json(registros, 'consumo_por_zona.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"consumo_por_zona.json generado en {t1-t0:.1f} segundos")
    print(f"\nTop 5 zonas por consumo:")
    print(df[['nombre_zona', 'kwh_total', 'costo_cop_total', 'total_anomalias',
              'pct_cumplimiento_horario']].head(5).to_string(index=False))
    print(f"{'─'*50}")
    print("→ NOTIFICAR AL INTEGRANTE 2: consumo_por_zona.json disponible en /data/")

if __name__ == '__main__':
    generar_consumo_por_zona()