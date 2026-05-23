"""
JSON 3/3 — consumo_por_hora.json
Requiere: JOIN con DimTiempo únicamente.
Tiempo esperado: 8–20 segundos.
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

def generar_consumo_por_hora():
    t0 = time.time()
    conn = get_connection()

    query = """
        SELECT
            -- Identificación temporal
            t.hora,
            t.dia_semana,
            t.nombre_dia,
            -- BIT → convertir explícitamente para evitar problemas de serialización
            CAST(t.es_horario_nocturno AS INT) AS es_horario_nocturno,
            CAST(t.es_fin_semana       AS INT) AS es_fin_semana,

            -- Métricas de consumo
            CAST(AVG(f.consumo_kwh)          AS FLOAT) AS kwh_promedio,
            CAST(SUM(f.consumo_kwh)          AS FLOAT) AS kwh_total,

            -- Calidad de iluminación
            CAST(AVG(f.nivel_lux)            AS FLOAT) AS lux_promedio,

            -- Lux óptimo ML (NULL si no integrado aún)
            CAST(AVG(f.lux_optimo_predicho)  AS FLOAT) AS lux_optimo_promedio,

            -- Operación
            CAST(
                SUM(CAST(f.estado_encendido AS INT)) * 100.0 / COUNT(*)
            AS FLOAT) AS pct_encendidas,

            -- Anomalías en esa franja
            SUM(CAST(f.anomalia_flag AS INT))           AS total_anomalias,

            -- Total de registros para verificación
            COUNT(*)                                     AS total_registros

        FROM dbo.FactConsumoIluminacion f
        JOIN dbo.DimTiempo t ON f.tiempo_id = t.tiempo_id
        GROUP BY
            t.hora,
            t.dia_semana,
            t.nombre_dia,
            t.es_horario_nocturno,
            t.es_fin_semana
        ORDER BY
            t.dia_semana,
            t.hora
    """

    print("Ejecutando consulta consumo_por_hora (puede tardar ~10-20 s)...")
    df = pd.read_sql(query, conn)
    conn.close()

    print(f"  → {len(df)} combinaciones hora×día recibidas")

    # ── validación ──────────────────────────────────────────
    filas_esperadas = 24 * 7  # = 168
    if len(df) != filas_esperadas:
        print(f"⚠️  ATENCIÓN: se esperaban {filas_esperadas} filas (24h × 7 días), "
              f"se recibieron {len(df)}.")
        print("   Si el dataset no cubre los 7 días de semana, "
              "puede haber menos combinaciones.")

    if df['lux_optimo_promedio'].isnull().all():
        print("ℹ️  lux_optimo_promedio es NULL — normal si ML no está integrado aún.")
        print("   Se enviará como null en el JSON. La web usará solo lux_promedio por ahora.")

    # ── convertir BIT a bool para JSON ──────────────────────
    df['es_horario_nocturno'] = df['es_horario_nocturno'].astype(bool)
    df['es_fin_semana']       = df['es_fin_semana'].astype(bool)

    # ── serialización ────────────────────────────────────────
    registros = []
    for _, row in df.iterrows():
        obj = {}
        for col in df.columns:
            val = row[col]
            if pd.isna(val):
                obj[col] = None
            elif col in ('hora', 'dia_semana', 'total_anomalias', 'total_registros'):
                obj[col] = int(val)
            elif col in ('es_horario_nocturno', 'es_fin_semana'):
                obj[col] = bool(val)
            elif col == 'nombre_dia':
                obj[col] = str(val)
            else:
                obj[col] = round(float(val), 4)
        registros.append(obj)

    guardar_json(registros, 'consumo_por_hora.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"consumo_por_hora.json generado en {t1-t0:.1f} segundos")

    # Resumen por período del día
    df['periodo'] = pd.cut(df['hora'],
                           bins=[-1, 5, 11, 17, 23],
                           labels=['Madrugada (0-5)', 'Mañana (6-11)',
                                   'Tarde (12-17)',   'Noche (18-23)'])
    resumen = df.groupby('periodo', observed=True).agg(
        kwh_promedio=('kwh_promedio', 'mean'),
        pct_encendidas=('pct_encendidas', 'mean')
    ).round(3)
    print("\nConsumo promedio por período del día:")
    print(resumen.to_string())
    print(f"\nHora de mayor consumo promedio: "
          f"{df.loc[df['kwh_promedio'].idxmax(), 'hora']}:00")
    print(f"Hora de menor consumo promedio: "
          f"{df.loc[df['kwh_promedio'].idxmin(), 'hora']}:00")
    print(f"{'─'*50}")

if __name__ == '__main__':
    generar_consumo_por_hora()