

"""
JSON 1/3 — kpis_generales.json
Ejecutar primero. No tiene dependencias de otras tablas.
Tiempo esperado: < 5 segundos.
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

def generar_kpis_generales():
    t0 = time.time()
    conn = get_connection()

    query = """
        SELECT
            -- Consumo energético
            CAST(SUM(f.consumo_kwh)              AS FLOAT) AS total_kwh,
            CAST(SUM(ISNULL(f.costo_cop, 0))     AS FLOAT) AS costo_total_cop,

            -- Anomalías
            SUM(CAST(f.anomalia_flag AS INT))               AS total_anomalias,
            CAST(
                SUM(CAST(f.anomalia_flag AS INT)) * 100.0
                / COUNT(*)
            AS FLOAT)                                        AS pct_anomalias,

            -- Ahorro ML (0 mientras lux_optimo_predicho sea NULL)
            CAST(
                SUM(CASE WHEN f.ahorro_kwh_estimado > 0
                         THEN f.ahorro_kwh_estimado ELSE 0 END)
            AS FLOAT)                                        AS ahorro_estimado_kwh,

            -- Operación
            CAST(
                SUM(CAST(f.estado_encendido AS INT)) * 100.0
                / COUNT(*)
            AS FLOAT)                                        AS pct_luminarias_encendidas,

            -- Inventario activo en la fact table
            COUNT(DISTINCT f.sensor_id)                      AS sensores_activos,
            COUNT(DISTINCT f.zona_id)                        AS zonas_monitoreadas,

            -- Calidad de iluminación
            CAST(AVG(f.nivel_lux) AS FLOAT)                  AS lux_promedio_global,

            -- Conteo total de registros (para validación)
            COUNT(*)                                          AS total_registros
        FROM dbo.FactConsumoIluminacion f
    """

    print("Ejecutando consulta kpis_generales...")
    df = pd.read_sql(query, conn)
    conn.close()

    # Convertir la única fila a dict
    row = df.iloc[0].to_dict()

    # Convertir tipos numpy a nativos Python para JSON
    kpis = {k: (int(v) if isinstance(v, (pd.Int64Dtype, int)) else float(v))
            for k, v in row.items()}

    # Redondear para legibilidad (no afecta precisión de análisis)
    kpis['total_kwh']                = round(kpis['total_kwh'], 2)
    kpis['costo_total_cop']          = round(kpis['costo_total_cop'], 2)
    kpis['ahorro_estimado_kwh']      = round(kpis['ahorro_estimado_kwh'], 4)
    kpis['pct_luminarias_encendidas']= round(kpis['pct_luminarias_encendidas'], 2)
    kpis['pct_anomalias']            = round(kpis['pct_anomalias'], 4)
    kpis['lux_promedio_global']      = round(kpis['lux_promedio_global'], 2)

    guardar_json(kpis, 'kpis_generales.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"kpis_generales.json generado en {t1-t0:.1f} segundos")
    print(f"  total_kwh            : {kpis['total_kwh']:,.2f}")
    print(f"  costo_total_cop      : {kpis['costo_total_cop']:,.2f}")
    print(f"  total_anomalias      : {kpis['total_anomalias']:,}")
    print(f"  pct_luminarias_enc.  : {kpis['pct_luminarias_encendidas']:.2f}%")
    print(f"  sensores_activos     : {kpis['sensores_activos']}")
    print(f"  zonas_monitoreadas   : {kpis['zonas_monitoreadas']}")
    print(f"  lux_promedio_global  : {kpis['lux_promedio_global']}")
    print(f"  total_registros      : {kpis['total_registros']:,}  ← verificar que = 1.000.000")
    print(f"{'─'*50}")

if __name__ == '__main__':
    generar_kpis_generales()