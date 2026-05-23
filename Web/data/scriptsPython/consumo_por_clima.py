"""
JSON consumo_por_clima.json
JOIN: Fact + DimClima (JOIN simple, baja cardinalidad en DimClima).
Tiempo esperado: 8–15 segundos.
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

def generar_consumo_por_clima():
    t0 = time.time()
    conn = get_connection()

    query = """
        SELECT
            -- Categorías climáticas de DimClima
            c.condicion_clima,
            c.rango_cobertura_nubosa,
            c.rango_radiacion_solar,

            -- Valores exactos promediados para el scatter
            CAST(AVG(CAST(c.radiacion_solar_wm2  AS FLOAT)) AS FLOAT) AS radiacion_solar_promedio,
            CAST(AVG(CAST(c.temperatura_c        AS FLOAT)) AS FLOAT) AS temperatura_promedio,
            CAST(AVG(CAST(c.cobertura_nubosa_pct AS FLOAT)) AS FLOAT) AS cobertura_nubosa_promedio,

            -- Métricas de la fact table
            CAST(AVG(f.consumo_kwh)             AS FLOAT) AS kwh_promedio,
            CAST(SUM(f.consumo_kwh)             AS FLOAT) AS kwh_total,
            CAST(AVG(f.nivel_lux)               AS FLOAT) AS lux_promedio,

            -- Operación
            CAST(
                SUM(CAST(f.estado_encendido AS INT)) * 100.0 / COUNT(*)
            AS FLOAT)                                                    AS pct_encendidas,

            -- Volumen
            COUNT(*)                                                     AS total_registros,
            SUM(CAST(f.anomalia_flag AS INT))                            AS total_anomalias

        FROM dbo.FactConsumoIluminacion f
        JOIN dbo.DimClima c ON f.clima_id = c.clima_id
        GROUP BY
            c.condicion_clima,
            c.rango_cobertura_nubosa,
            c.rango_radiacion_solar
        ORDER BY radiacion_solar_promedio ASC
    """

    print("Ejecutando consulta consumo_por_clima...")
    df = pd.read_sql(query, conn)
    conn.close()

    print(f"  → {len(df)} perfiles climáticos encontrados")
    print(f"  Condiciones únicas: {df['condicion_clima'].unique().tolist()}")

    # ── Serializar ───────────────────────────────────────────
    registros = []
    for _, row in df.iterrows():
        obj = {
            'condicion_clima':           str(row['condicion_clima']),
            'rango_cobertura_nubosa':    str(row['rango_cobertura_nubosa']),
            'rango_radiacion_solar':     str(row['rango_radiacion_solar']),
            'radiacion_solar_promedio':  round(float(row['radiacion_solar_promedio']), 2),
            'temperatura_promedio':      round(float(row['temperatura_promedio']), 2),
            'cobertura_nubosa_promedio': round(float(row['cobertura_nubosa_promedio']), 2),
            'kwh_promedio':              round(float(row['kwh_promedio']), 6),
            'kwh_total':                 round(float(row['kwh_total']), 2),
            'lux_promedio':              round(float(row['lux_promedio']), 2),
            'pct_encendidas':            round(float(row['pct_encendidas']), 2),
            'total_registros':           int(row['total_registros']),
            'total_anomalias':           int(row['total_anomalias']),
        }
        registros.append(obj)

    guardar_json(registros, 'consumo_por_clima.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"consumo_por_clima.json generado en {t1-t0:.1f} segundos")
    print(f"\nResumen por condición climática:")
    resumen = df.groupby('condicion_clima').agg(
        lux_promedio=('lux_promedio', 'mean'),
        kwh_promedio=('kwh_promedio', 'mean'),
        radiacion_solar_promedio=('radiacion_solar_promedio', 'mean'),
        pct_encendidas=('pct_encendidas', 'mean')
    ).round(2)
    print(resumen.to_string())

    # Verificar hipótesis de correlación negativa radiación-lux
    correlacion = df['radiacion_solar_promedio'].corr(df['lux_promedio'])
    signo = "negativa ✓" if correlacion < -0.3 else "débil o positiva ⚠️"
    print(f"\n  Correlación radiación solar ↔ lux promedio: {correlacion:.3f} ({signo})")
    print(f"{'─'*50}")

if __name__ == '__main__':
    generar_consumo_por_clima()