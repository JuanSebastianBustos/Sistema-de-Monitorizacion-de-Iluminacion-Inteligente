"""
JSON serie_temporal.json
JOIN: solo DimTiempo (el más rápido).
Tiempo esperado: 5–10 segundos.
Estructura de salida: objeto anidado por año, no array plano.
"""
import pyodbc, pandas as pd, json, time
from pathlib import Path

SERVER   = r'.\SQLDEVELOPER'   # ← copiar de SSMS (barra de conexión)
DATABASE = 'IluminacionBogota_DW'          # ← nombre exacto de tu DW
OUTPUT_DIR = Path('data')                  # ← carpeta destino en el repo web
OUTPUT_DIR.mkdir(exist_ok=True)


CONN_STR = (
    f'DRIVER={{SQL Server}};'
    f'SERVER={SERVER};'
    f'DATABASE={DATABASE};'
    f'Trusted_Connection=yes;'
)

def get_connection():
    try:
        conn = pyodbc.connect(CONN_STR, timeout=10)
        print(f"✓ Conectado a {SERVER} → {DATABASE}")
        return conn
    except pyodbc.Error as e:
        print(f"✗ Error de conexión: {e}")
        raise

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Tipo no serializable: {type(obj)}")

def guardar_json(data, nombre_archivo):
    ruta = OUTPUT_DIR / nombre_archivo
    with open(ruta, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2, default=decimal_default)
    tamanio_kb = ruta.stat().st_size / 1024
    print(f"✓ Guardado: {ruta}  ({tamanio_kb:.1f} KB)")

def generar_serie_temporal():
    t0 = time.time()
    conn = get_connection()

    query = """
        SELECT
            t.anio,
            t.mes,
            t.nombre_mes,

            -- Consumo mensual
            CAST(SUM(f.consumo_kwh)                              AS FLOAT) AS kwh_total,
            CAST(SUM(ISNULL(f.costo_cop, 0))                    AS FLOAT) AS costo_cop_total,

            -- Anomalías
            SUM(CAST(f.anomalia_flag AS INT))                               AS total_anomalias,

            -- Ahorro ML
            CAST(
                SUM(CASE WHEN f.ahorro_kwh_estimado > 0
                         THEN f.ahorro_kwh_estimado ELSE 0 END)
            AS FLOAT)                                                        AS ahorro_kwh_estimado,

            -- Calidad de iluminación
            CAST(AVG(f.nivel_lux)                               AS FLOAT) AS lux_promedio,

            -- Operación
            CAST(
                SUM(CAST(f.estado_encendido AS INT)) * 100.0 / COUNT(*)
            AS FLOAT)                                                        AS pct_encendidas,

            -- Volumen del mes
            COUNT(*)                                                         AS total_registros

        FROM dbo.FactConsumoIluminacion f
        JOIN dbo.DimTiempo t ON f.tiempo_id = t.tiempo_id
        GROUP BY t.anio, t.mes, t.nombre_mes
        ORDER BY t.anio, t.mes
    """

    print("Ejecutando consulta serie_temporal...")
    df = pd.read_sql(query, conn)
    conn.close()

    print(f"  → {len(df)} combinaciones año×mes recibidas")

    # ── validación ──────────────────────────────────────────
    anos_encontrados = sorted(df['anio'].unique())
    print(f"  Años en el dataset: {anos_encontrados}")
    for anio in anos_encontrados:
        meses_anio = len(df[df['anio'] == anio])
        if meses_anio < 12:
            print(f"  ⚠️  Año {anio} tiene solo {meses_anio} meses — "
                  f"normal si el dataset no cubre el año completo")

    # ── construir estructura anidada por año ─────────────────
    serie = {}
    for _, row in df.iterrows():
        anio_str = str(int(row['anio']))
        if anio_str not in serie:
            serie[anio_str] = []

        serie[anio_str].append({
            'mes':                  int(row['mes']),
            'nombre_mes':           str(row['nombre_mes']),
            'kwh_total':            round(float(row['kwh_total']), 2),
            'costo_cop_total':      round(float(row['costo_cop_total']), 2),
            'total_anomalias':      int(row['total_anomalias']),
            'ahorro_kwh_estimado':  round(float(row['ahorro_kwh_estimado']), 4),
            'lux_promedio':         round(float(row['lux_promedio']), 2),
            'pct_encendidas':       round(float(row['pct_encendidas']), 2),
            'total_registros':      int(row['total_registros']),
        })

    guardar_json(serie, 'serie_temporal.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"serie_temporal.json generado en {t1-t0:.1f} segundos")
    print(f"\nResumen por año:")
    resumen = df.groupby('anio').agg(
        kwh_total=('kwh_total', 'sum'),
        total_anomalias=('total_anomalias', 'sum'),
        meses=('mes', 'count')
    ).round(2)
    print(resumen.to_string())
    print(f"{'─'*50}")

if __name__ == '__main__':
    generar_serie_temporal()