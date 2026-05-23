"""
JSON consumo_por_tecnologia.json
JOIN: Fact + DimLuminaria (un solo JOIN adicional).
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

def generar_consumo_por_tecnologia():
    t0 = time.time()
    conn = get_connection()

    query = """
        SELECT
            l.tipo_lampara,

            -- Inventario
            COUNT(DISTINCT f.luminaria_id)             AS total_luminarias,

            -- Consumo
            CAST(SUM(f.consumo_kwh)            AS FLOAT) AS kwh_total,
            CAST(SUM(ISNULL(f.costo_cop, 0))   AS FLOAT) AS costo_cop_total,

            -- Calidad lumínica
            CAST(AVG(f.nivel_lux)              AS FLOAT) AS lux_promedio,

            -- Anomalías
            SUM(CAST(f.anomalia_flag AS INT))            AS total_anomalias,

            -- Eficiencia (lux producido por kWh — KPI central del scatter)
            -- AVG(lux) / AVG(kwh): lux/kWh promedio de esa tecnología
            CAST(
                AVG(f.nivel_lux)
                / NULLIF(AVG(f.consumo_kwh), 0)
            AS FLOAT) AS eficiencia_lux_kwh,

            -- Participación porcentual en el consumo total
            CAST(
                SUM(f.consumo_kwh) * 100.0
                / SUM(SUM(f.consumo_kwh)) OVER ()
            AS FLOAT) AS pct_participacion,

            -- Especificaciones del catálogo (DimLuminaria)
            CAST(AVG(ISNULL(l.eficiencia_lm_w, 0))      AS FLOAT) AS eficiencia_lm_w_nominal,
            CAST(AVG(l.potencia_nominal_w)               AS FLOAT) AS potencia_nominal_promedio,
            AVG(ISNULL(l.vida_util_horas, 0))            AS vida_util_horas_promedio

        FROM dbo.FactConsumoIluminacion f
        JOIN dbo.DimLuminaria l ON f.luminaria_id = l.luminaria_id
        GROUP BY l.tipo_lampara
        ORDER BY kwh_total DESC
    """

    print("Ejecutando consulta consumo_por_tecnologia...")
    df = pd.read_sql(query, conn)
    conn.close()

    print(f"  → {len(df)} tipos de lámpara encontrados: {df['tipo_lampara'].tolist()}")

    # ── derivar kwh_promedio_por_luminaria y es_led ──────────
    registros = []
    for _, row in df.iterrows():
        kwh_total_row = float(row['kwh_total'])
        total_lum     = int(row['total_luminarias'])

        obj = {
            'tipo_lampara':              str(row['tipo_lampara']),
            'total_luminarias':          total_lum,
            'kwh_total':                 round(kwh_total_row, 2),
            'kwh_promedio_por_luminaria': round(kwh_total_row / total_lum, 6)
                                          if total_lum > 0 else 0,
            'costo_cop_total':           round(float(row['costo_cop_total']), 2),
            'lux_promedio':              round(float(row['lux_promedio']), 2),
            'eficiencia_lux_kwh':        round(float(row['eficiencia_lux_kwh']), 2)
                                         if pd.notna(row['eficiencia_lux_kwh']) else 0,
            'pct_participacion':         round(float(row['pct_participacion']), 2),
            'total_anomalias':           int(row['total_anomalias']),
            'eficiencia_lm_w_nominal':   round(float(row['eficiencia_lm_w_nominal']), 2),
            'potencia_nominal_promedio':  round(float(row['potencia_nominal_promedio']), 2),
            'vida_util_horas_promedio':   int(row['vida_util_horas_promedio']),
            # Campo helper para filtros rápidos en JavaScript
            'es_led':                    'LED' in str(row['tipo_lampara']).upper(),
        }
        registros.append(obj)

    guardar_json(registros, 'consumo_por_tecnologia.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"consumo_por_tecnologia.json generado en {t1-t0:.1f} segundos")
    print(f"\nComparativo de eficiencia por tecnología:")
    print(df[['tipo_lampara', 'lux_promedio', 'eficiencia_lux_kwh',
              'pct_participacion']].round(2).to_string(index=False))

    # Verificación clave: LED debe tener mayor eficiencia_lux_kwh
    led_rows = df[df['tipo_lampara'].str.upper().str.contains('LED')]
    if not led_rows.empty:
        led_eficiencia = led_rows['eficiencia_lux_kwh'].max()
        no_led_max = df[~df['tipo_lampara'].str.upper().str.contains('LED')]['eficiencia_lux_kwh'].max()
        if led_eficiencia > no_led_max:
            print(f"\n✓ LED más eficiente ({led_eficiencia:.1f} lux/kWh) "
                  f"que el resto ({no_led_max:.1f} lux/kWh) — coherente")
        else:
            print(f"\n⚠️  LED no es el más eficiente — revisar datos del dataset")
    print(f"{'─'*50}")

if __name__ == '__main__':
    generar_consumo_por_tecnologia()