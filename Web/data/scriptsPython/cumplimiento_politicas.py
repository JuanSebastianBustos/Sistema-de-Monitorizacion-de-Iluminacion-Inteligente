"""
JSON cumplimiento_politicas.json
Joins: Fact + DimZona + DimTiempo + DimPolitica.
Tiempo esperado: 20–45 segundos (4 tablas en el JOIN).
Si tarda más de 60 s: revisar que DW tiene índices sobre tiempo_id, zona_id, politica_id.
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

QUERY_GLOBAL = """
    SELECT
        -- Cumplimiento horario global
        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 1 AND f.estado_encendido = 1
                     THEN 1.0 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN t.es_horario_nocturno = 1
                              THEN 1.0 ELSE 0 END), 0) * 100
        AS FLOAT) AS pct_cumplimiento_horario,

        -- Cumplimiento lux global
        -- Universo: nocturnos encendidos. Cumple: nivel_lux >= umbral de la política
        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 1
                          AND f.estado_encendido = 1
                          AND f.nivel_lux >= p.nivel_lux_umbral
                     THEN 1.0 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN t.es_horario_nocturno = 1
                                   AND f.estado_encendido = 1
                              THEN 1.0 ELSE 0 END), 0) * 100
        AS FLOAT) AS pct_cumplimiento_lux,

        -- Desperdicio diurno
        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 0 AND f.estado_encendido = 1
                     THEN f.consumo_kwh ELSE 0 END)
        AS FLOAT) AS kwh_desperdiciados,

        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 0 AND f.estado_encendido = 1
                     THEN ISNULL(f.costo_cop, 0) ELSE 0 END)
        AS FLOAT) AS costo_desperdicio_cop,

        -- Sin servicio nocturno
        SUM(CASE WHEN t.es_horario_nocturno = 1 AND f.estado_encendido = 0
                 THEN 1 ELSE 0 END) AS registros_sin_servicio,

        -- Desperdicio diurno (conteo de registros)
        SUM(CASE WHEN t.es_horario_nocturno = 0 AND f.estado_encendido = 1
                 THEN 1 ELSE 0 END) AS registros_desperdicio_diurno,

        -- Umbral promedio del sistema
        CAST(AVG(CAST(p.nivel_lux_umbral AS FLOAT)) AS FLOAT) AS lux_umbral_promedio_sistema

    FROM dbo.FactConsumoIluminacion f
    JOIN dbo.DimTiempo   t ON f.tiempo_id   = t.tiempo_id
    JOIN dbo.DimPolitica p ON f.politica_id = p.politica_id
"""

QUERY_POR_ZONA = """
    SELECT
        z.zona_id,
        z.nombre_zona,
        CAST(z.latitud  AS FLOAT) AS latitud,
        CAST(z.longitud AS FLOAT) AS longitud,

        -- Cumplimiento horario por zona
        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 1 AND f.estado_encendido = 1
                     THEN 1.0 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN t.es_horario_nocturno = 1
                              THEN 1.0 ELSE 0 END), 0) * 100
        AS FLOAT) AS pct_cumplimiento_horario,

        -- Cumplimiento lux por zona
        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 1
                          AND f.estado_encendido = 1
                          AND f.nivel_lux >= p.nivel_lux_umbral
                     THEN 1.0 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN t.es_horario_nocturno = 1
                                   AND f.estado_encendido = 1
                              THEN 1.0 ELSE 0 END), 0) * 100
        AS FLOAT) AS pct_cumplimiento_lux,

        -- Desperdicio por zona
        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 0 AND f.estado_encendido = 1
                     THEN f.consumo_kwh ELSE 0 END)
        AS FLOAT) AS kwh_desperdiciados,

        CAST(
            SUM(CASE WHEN t.es_horario_nocturno = 0 AND f.estado_encendido = 1
                     THEN ISNULL(f.costo_cop, 0) ELSE 0 END)
        AS FLOAT) AS costo_desperdicio_cop,

        -- Sin servicio nocturno en esta zona
        SUM(CASE WHEN t.es_horario_nocturno = 1 AND f.estado_encendido = 0
                 THEN 1 ELSE 0 END) AS registros_sin_servicio,

        -- Referencia del umbral de política de esa zona
        CAST(AVG(CAST(p.nivel_lux_umbral AS FLOAT)) AS FLOAT) AS lux_umbral_politica,

        -- Brecha lux: positivo = sobreiluminación, negativo = subiluminación
        CAST(
            AVG(CASE WHEN t.es_horario_nocturno = 1 AND f.estado_encendido = 1
                     THEN f.nivel_lux - CAST(p.nivel_lux_umbral AS FLOAT) END)
        AS FLOAT) AS brecha_lux_promedio

    FROM dbo.FactConsumoIluminacion f
    JOIN dbo.DimZona     z ON f.zona_id     = z.zona_id
    JOIN dbo.DimTiempo   t ON f.tiempo_id   = t.tiempo_id
    JOIN dbo.DimPolitica p ON f.politica_id = p.politica_id
    GROUP BY z.zona_id, z.nombre_zona, z.latitud, z.longitud
    ORDER BY pct_cumplimiento_horario ASC
"""

def generar_cumplimiento_politicas():
    t0 = time.time()
    conn = get_connection()

    # ── Query global ─────────────────────────────────────────
    print("Ejecutando consulta global de cumplimiento...")
    df_global = pd.read_sql(QUERY_GLOBAL, conn)
    row_g = df_global.iloc[0]

    globales = {
        'pct_cumplimiento_horario':     round(float(row_g['pct_cumplimiento_horario']), 2),
        'pct_cumplimiento_lux':         round(float(row_g['pct_cumplimiento_lux']), 2),
        'kwh_desperdiciados':           round(float(row_g['kwh_desperdiciados']), 2),
        'costo_desperdicio_cop':        round(float(row_g['costo_desperdicio_cop']), 2),
        'registros_sin_servicio':       int(row_g['registros_sin_servicio']),
        'registros_desperdicio_diurno': int(row_g['registros_desperdicio_diurno']),
        'lux_umbral_promedio_sistema':  round(float(row_g['lux_umbral_promedio_sistema']), 2),
    }
    print(f"  Cumplimiento horario global: {globales['pct_cumplimiento_horario']:.1f}%")
    print(f"  Cumplimiento lux global:     {globales['pct_cumplimiento_lux']:.1f}%")
    print(f"  kWh desperdiciados:          {globales['kwh_desperdiciados']:,.2f}")

    # ── Query por zona ───────────────────────────────────────
    print("Ejecutando consulta por zona de cumplimiento (puede tardar ~30 s)...")
    df_zona = pd.read_sql(QUERY_POR_ZONA, conn)
    conn.close()

    print(f"  → {len(df_zona)} zonas recibidas")
    if len(df_zona) != 20:
        print(f"  ⚠️  Se esperaban 20 zonas, llegaron {len(df_zona)}")

    # ── Serializar por_zona ──────────────────────────────────
    por_zona = []
    for _, row in df_zona.iterrows():
        obj = {
            'zona_id':                  int(row['zona_id']),
            'nombre_zona':              str(row['nombre_zona']),
            'latitud':                  float(row['latitud']),
            'longitud':                 float(row['longitud']),
            'pct_cumplimiento_horario': round(float(row['pct_cumplimiento_horario']), 2)
                                        if pd.notna(row['pct_cumplimiento_horario']) else None,
            'pct_cumplimiento_lux':     round(float(row['pct_cumplimiento_lux']), 2)
                                        if pd.notna(row['pct_cumplimiento_lux']) else None,
            'kwh_desperdiciados':       round(float(row['kwh_desperdiciados']), 2),
            'costo_desperdicio_cop':    round(float(row['costo_desperdicio_cop']), 2),
            'registros_sin_servicio':   int(row['registros_sin_servicio']),
            'lux_umbral_politica':      round(float(row['lux_umbral_politica']), 2)
                                        if pd.notna(row['lux_umbral_politica']) else None,
            'brecha_lux_promedio':      round(float(row['brecha_lux_promedio']), 2)
                                        if pd.notna(row['brecha_lux_promedio']) else None,
        }
        por_zona.append(obj)

    # ── Estructura final ─────────────────────────────────────
    resultado = {
        'globales':  globales,
        'por_zona':  por_zona,
    }

    guardar_json(resultado, 'cumplimiento_politicas.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"cumplimiento_politicas.json generado en {t1-t0:.1f} segundos")
    print(f"\nZonas con menor cumplimiento horario (top 5):")
    print(df_zona[['nombre_zona', 'pct_cumplimiento_horario',
                   'kwh_desperdiciados', 'pct_cumplimiento_lux']].head(5).to_string(index=False))
    print(f"{'─'*50}")

if __name__ == '__main__':
    generar_cumplimiento_politicas()