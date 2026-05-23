"""
JSON estado_sensores.json
Estrategia: CTE para calcular métricas en la fact table,
luego JOIN limpio con DimSensor y DimZona.
Esto evita el problema de usar funciones de agregación
dentro de un CASE en la misma query.
Tiempo esperado: 10–20 segundos.
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

def generar_estado_sensores():
    t0 = time.time()
    conn = get_connection()

    query = """
        -- CTE: calcular métricas de la fact table por sensor
        WITH MetricasSensor AS (
            SELECT
                f.sensor_id,
                SUM(CAST(f.anomalia_flag AS INT))  AS total_anomalias,
                COUNT(*)                            AS total_lecturas,
                CAST(
                    SUM(CAST(f.anomalia_flag AS INT)) * 100.0
                    / NULLIF(COUNT(*), 0)
                AS FLOAT)                           AS pct_anomalias
            FROM dbo.FactConsumoIluminacion f
            GROUP BY f.sensor_id
        )

        -- JOIN con dimensiones para obtener atributos del sensor
        SELECT
            s.sensor_id,
            z.nombre_zona,

            -- Coordenadas exactas del sensor (no del centroide de zona)
            CAST(s.latitud  AS FLOAT) AS latitud,
            CAST(s.longitud AS FLOAT) AS longitud,

            -- Perfil técnico
            s.tipo_sensor,
            s.modelo,
            s.fabricante,
            s.estado_sensor,
            CAST(ISNULL(s.precision_pct, 0) AS FLOAT) AS precision_pct,

            -- Mantenimiento
            CASE
                WHEN s.fecha_ultimo_mantenimiento IS NULL THEN NULL
                ELSE DATEDIFF(DAY, s.fecha_ultimo_mantenimiento, GETDATE())
            END AS dias_sin_mantenimiento,

            -- Métricas de la CTE
            ms.total_anomalias,
            ms.total_lecturas,
            CAST(ms.pct_anomalias AS FLOAT) AS pct_anomalias

        FROM dbo.DimSensor s
        JOIN dbo.DimZona z  ON s.zona_id  = z.zona_id
        JOIN MetricasSensor ms ON s.sensor_id = ms.sensor_id
        ORDER BY ms.pct_anomalias DESC
    """

    print("Ejecutando consulta estado_sensores (CTE + JOIN doble)...")
    df = pd.read_sql(query, conn)
    conn.close()

    print(f"  → {len(df)} sensores recibidos")

    # ── calcular estado_criticidad en Python ──────────────────
    # (más claro y mantenible que un CASE anidado en SQL)
    estados_inactivos = {'Inactivo', 'Dado de baja'}

    def calcular_criticidad(row):
        if row['estado_sensor'] in estados_inactivos:
            return 'INACTIVO'
        pct = row['pct_anomalias'] if pd.notna(row['pct_anomalias']) else 0
        if pct >= 15:
            return 'CRITICO'
        if pct >= 5:
            return 'ALERTA'
        return 'NORMAL'

    df['estado_criticidad'] = df.apply(calcular_criticidad, axis=1)

    # ── validación ──────────────────────────────────────────
    dist_criticidad = df['estado_criticidad'].value_counts().to_dict()
    print(f"  Distribución de criticidad: {dist_criticidad}")

    sensores_sin_coords = df[df['latitud'].isna() | df['longitud'].isna()]
    if not sensores_sin_coords.empty:
        print(f"  ⚠️  {len(sensores_sin_coords)} sensores sin coordenadas — "
              f"no aparecerán en el mapa de burbujas")

    sensores_sin_mantenimiento = df[df['dias_sin_mantenimiento'].isna()]
    if not sensores_sin_mantenimiento.empty:
        print(f"  ℹ️  {len(sensores_sin_mantenimiento)} sensores sin registro de mantenimiento "
              f"(fecha_ultimo_mantenimiento NULL en DimSensor)")

    # ── Serializar ───────────────────────────────────────────
    registros = []
    for _, row in df.iterrows():
        obj = {
            'sensor_id':              int(row['sensor_id']),
            'nombre_zona':            str(row['nombre_zona']),
            'latitud':                float(row['latitud'])     if pd.notna(row['latitud'])  else None,
            'longitud':               float(row['longitud'])    if pd.notna(row['longitud']) else None,
            'tipo_sensor':            str(row['tipo_sensor']),
            'modelo':                 str(row['modelo']),
            'fabricante':             str(row['fabricante']),
            'estado_sensor':          str(row['estado_sensor']),
            'precision_pct':          round(float(row['precision_pct']), 2),
            'dias_sin_mantenimiento': int(row['dias_sin_mantenimiento'])
                                      if pd.notna(row['dias_sin_mantenimiento']) else None,
            'total_anomalias':        int(row['total_anomalias']),
            'total_lecturas':         int(row['total_lecturas']),
            'pct_anomalias':          round(float(row['pct_anomalias']), 4)
                                      if pd.notna(row['pct_anomalias']) else 0.0,
            'estado_criticidad':      str(row['estado_criticidad']),
        }
        registros.append(obj)

    guardar_json(registros, 'estado_sensores.json')

    t1 = time.time()
    print(f"\n{'─'*50}")
    print(f"estado_sensores.json generado en {t1-t0:.1f} segundos")
    print(f"\nTop 5 sensores más críticos:")
    top5 = df[['sensor_id', 'nombre_zona', 'modelo',
               'pct_anomalias', 'dias_sin_mantenimiento',
               'estado_criticidad']].head(5)
    print(top5.to_string(index=False))
    print(f"\n→ TODOS LOS JSONs GENERADOS. Hacer git push completo.")
    print(f"{'─'*50}")

if __name__ == '__main__':
    generar_estado_sensores()