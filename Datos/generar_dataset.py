"""
generar_dataset.py
==================
Script de generación del dataset de ~1.000.000 de registros para el
Sistema de Monitorización de Iluminación Inteligente — Bogotá D.C.

Genera dos archivos CSV alineados con el DDL del modelo OLTP:
  1. lecturas_ambiente.csv  → BULK INSERT en operativo.LecturaAmbiente
  2. consumos_energeticos.csv → carga derivada en operativo.ConsumoEnergetico

También genera tablas maestras (Zona, Sensor, Luminaria, PoliticaIluminacion)
como CSV separados para que el Integrante 1 pueda poblarlas antes del BULK INSERT.

Además exporta:
  - lecturas_muestra_1000.json  → primeros 1000 registros para pruebas rápidas

Supuestos de simulación
------------------------
- Rango temporal  : 2023-01-01 a 2024-12-31 (2 años)
- Sensores        : 500 unidades distribuidas en las 20 localidades de Bogotá
- Luminarias      : 500 (relación 1:1 con sensores, simplificación académica)
- Frecuencia      : ~1 lectura/hora por sensor (no todas las horas tienen datos
                     para llegar exactamente a 1M sin desbordar memoria)
- Clima de Bogotá : temperatura 7–19°C, alta nubosidad, lluvia frecuente
- Anomalías       : ~2% de registros (anomalia_flag = 1)
- IDs de catálogo : coinciden exactamente con los INSERT del DDL del Int. 1
                     (CondicionClima: 1=Soleado, 2=Nublado, 3=Lluvioso, 4=Despejado Nocturno)
                     (TipoSensor   : 1=BH1750, 2=TSL2561, 3=GL5528, 4=VEML7700)
                     (TipoLampara  : 1=LED, 2=Sodio, 3=Haluro, 4=Mercurio, 5=Inducción)
                     (EstadoSensor : 1=Activo, 2=Inactivo, 3=Mantenimiento, 4=Baja)
                     (EstadoLuminaria: 1=Operativa, 2=Averiada, 3=Reemplazo, 4=Baja)
                     (TipoZona     : 1=Residencial, 2=Comercial, 3=Industrial, 4=Mixta, 5=Rural)

Autor     : Integrante 2 — Data Engineer
Proyecto  : Ciudades Inteligentes · ODS 7 · ODS 11 · ODS 13
"""

import pandas as pd
import numpy as np
import json
import os
from datetime import datetime, timedelta

# ─────────────────────────────────────────────────────────────
# PARÁMETROS GLOBALES
# ─────────────────────────────────────────────────────────────
SEED           = 42
N_SENSORES     = 500
N_ZONAS        = 20
N_REGISTROS    = 1_000_000
FECHA_INICIO   = datetime(2023, 1, 1)
FECHA_FIN      = datetime(2024, 12, 31, 23, 0, 0)
OUTPUT_DIR     = "."                # carpeta de salida (ajustar según repo)

np.random.seed(SEED)

print("=" * 60)
print("  GENERADOR DE DATASET — Iluminación Inteligente Bogotá")
print("=" * 60)

# ─────────────────────────────────────────────────────────────
# 1. TABLAS MAESTRAS — Zona
#    zona_id se asigna implícitamente por IDENTITY, pero el CSV
#    lleva un id_sugerido para que el INT. 1 sepa qué valor
#    quedará tras el INSERT (insertar en orden 1-20).
# ─────────────────────────────────────────────────────────────
print("\n[1/6] Generando maestro.Zona ...")

LOCALIDADES = [
    # (nombre_zona, localidad, tipo_zona_id, lat, lon, poblacion, area_km2)
    ("Usaquén",          "Usaquén",        2, 4.701443, -74.031189,  500000,  65.31),
    ("Chapinero",        "Chapinero",      2, 4.644723, -74.059753,  139701,  38.15),
    ("Santa Fe",         "Santa Fe",       4, 4.596524, -74.073839,  107044,  45.17),
    ("San Cristóbal",    "San Cristóbal",  1, 4.564890, -74.089571,  406374,  49.84),
    ("Usme",             "Usme",           5, 4.478000, -74.134000,  432724, 215.06),
    ("Tunjuelito",       "Tunjuelito",     1, 4.572000, -74.131000,  201843,  10.60),
    ("Bosa",             "Bosa",           1, 4.628000, -74.197000,  715836,  24.24),
    ("Kennedy",          "Kennedy",        1, 4.627000, -74.164000, 1230539,  38.73),
    ("Fontibón",         "Fontibón",       3, 4.673000, -74.146000,  422367,  33.35),
    ("Engativá",         "Engativá",       1, 4.702000, -74.112000,  887080,  35.88),
    ("Suba",             "Suba",           4, 4.742000, -74.083000, 1315509,  87.98),
    ("Barrios Unidos",   "Barrios Unidos", 1, 4.665000, -74.071000,  243219,   9.19),
    ("Teusaquillo",      "Teusaquillo",    2, 4.651000, -74.085000,  147318,  14.38),
    ("Los Mártires",     "Los Mártires",   4, 4.609000, -74.086000,   97257,   6.53),
    ("Antonio Nariño",   "Antonio Nariño", 1, 4.594000, -74.108000,  109193,   4.88),
    ("Puente Aranda",    "Puente Aranda",  3, 4.621000, -74.109000,  258441,  17.36),
    ("La Candelaria",    "La Candelaria",  4, 4.597000, -74.074000,   23680,   1.83),
    ("Rafael Uribe",     "Rafael Uribe",   1, 4.560000, -74.113000,  377836,  13.85),
    ("Ciudad Bolívar",   "Ciudad Bolívar", 5, 4.509000, -74.160000,  739140, 132.99),
    ("Sumapaz",          "Sumapaz",        5, 4.213000, -74.357000,    6815, 780.00),
]

df_zona = pd.DataFrame(LOCALIDADES, columns=[
    "nombre_zona", "localidad", "tipo_zona_id",
    "latitud", "longitud", "poblacion", "area_km2"
])
df_zona.index = df_zona.index + 1          # zona_id 1-20 (refleja IDENTITY)
df_zona.index.name = "zona_id_sugerido"
df_zona.to_csv(os.path.join(OUTPUT_DIR, "maestro_zona.csv"), index=True)
print(f"   → maestro_zona.csv  ({len(df_zona)} filas)")


# ─────────────────────────────────────────────────────────────
# 2. TABLAS MAESTRAS — Sensor
# ─────────────────────────────────────────────────────────────
print("\n[2/6] Generando maestro.Sensor ...")

# Distribución de sensores por zona proporcional a la población
poblaciones = np.array([z[6] for z in LOCALIDADES], dtype=float)
prob_zona   = poblaciones / poblaciones.sum()
zona_ids    = np.random.choice(np.arange(1, N_ZONAS + 1), size=N_SENSORES, p=prob_zona)

# Cada sensor hereda lat/lon de su zona con pequeña variación
zona_coords = {i+1: (LOCALIDADES[i][3], LOCALIDADES[i][4]) for i in range(N_ZONAS)}

sensores = []
for sid in range(1, N_SENSORES + 1):
    zid        = int(zona_ids[sid - 1])
    lat_base, lon_base = zona_coords[zid]
    lat        = round(lat_base + np.random.uniform(-0.02, 0.02), 6)
    lon        = round(lon_base + np.random.uniform(-0.02, 0.02), 6)
    tipo_s     = int(np.random.choice([1, 2, 3, 4], p=[0.40, 0.25, 0.25, 0.10]))
    estado_s   = int(np.random.choice([1, 2, 3, 4], p=[0.92, 0.04, 0.03, 0.01]))
    f_inst     = FECHA_INICIO - timedelta(days=int(np.random.randint(180, 1825)))
    f_mant     = f_inst + timedelta(days=int(np.random.randint(30, 365))) if np.random.random() > 0.3 else None

    sensores.append({
        "sensor_id"                 : sid,
        "zona_id"                   : zid,
        "tipo_sensor_id"            : tipo_s,
        "estado_sensor_id"          : estado_s,
        "codigo_externo"            : f"SEN-BOG-{sid:05d}",
        "latitud"                   : lat,
        "longitud"                  : lon,
        "fecha_instalacion"         : f_inst.strftime("%Y-%m-%d"),
        "fecha_ultimo_mantenimiento": f_mant.strftime("%Y-%m-%d") if f_mant else "",
        "observaciones"             : "",
    })

df_sensor = pd.DataFrame(sensores)
df_sensor.to_csv(os.path.join(OUTPUT_DIR, "maestro_sensor.csv"), index=False)
print(f"   → maestro_sensor.csv  ({len(df_sensor)} filas)")


# ─────────────────────────────────────────────────────────────
# 3. TABLAS MAESTRAS — Luminaria  (relación 1:1 con Sensor)
# ─────────────────────────────────────────────────────────────
print("\n[3/6] Generando maestro.Luminaria ...")

# Potencias típicas según tipo de lámpara
POTENCIAS = {1: 100.0, 2: 250.0, 3: 150.0, 4: 125.0, 5: 120.0}

luminarias = []
for sid in range(1, N_SENSORES + 1):
    sensor    = sensores[sid - 1]
    tipo_lamp = int(np.random.choice([1, 2, 3, 4, 5], p=[0.55, 0.25, 0.10, 0.05, 0.05]))
    estado_l  = int(np.random.choice([1, 2, 3, 4], p=[0.90, 0.05, 0.03, 0.02]))
    potencia  = POTENCIAS[tipo_lamp] + round(np.random.uniform(-10, 10), 2)
    f_inst    = datetime.strptime(sensor["fecha_instalacion"], "%Y-%m-%d")
    horas_op  = int((FECHA_FIN - f_inst).days * 12)   # promedio 12 h/día

    luminarias.append({
        "luminaria_id"             : sid,
        "sensor_id"                : sid,
        "zona_id"                  : sensor["zona_id"],
        "tipo_lampara_id"          : tipo_lamp,
        "estado_luminaria_id"      : estado_l,
        "potencia_w"               : round(potencia, 2),
        "altura_poste_m"           : round(np.random.uniform(6.0, 12.0), 2),
        "codigo_poste"             : f"POL-BOG-{sid:05d}",
        "latitud"                  : sensor["latitud"],
        "longitud"                 : sensor["longitud"],
        "fecha_instalacion"        : sensor["fecha_instalacion"],
        "horas_operacion_acumuladas": horas_op,
    })

df_luminaria = pd.DataFrame(luminarias)
df_luminaria.to_csv(os.path.join(OUTPUT_DIR, "maestro_luminaria.csv"), index=False)
print(f"   → maestro_luminaria.csv  ({len(df_luminaria)} filas)")


# ─────────────────────────────────────────────────────────────
# 4. TABLAS MAESTRAS — PoliticaIluminacion (1 política por zona)
# ─────────────────────────────────────────────────────────────
print("\n[4/6] Generando control.PoliticaIluminacion ...")

politicas = []
for zid in range(1, N_ZONAS + 1):
    # Zonas comerciales/mixtas se encienden antes; rurales, más tarde
    tipo_z    = LOCALIDADES[zid - 1][2]
    h_enc     = "17:30:00" if tipo_z in (2, 4) else "18:00:00"
    h_apg     = "05:30:00" if tipo_z in (2, 4) else "05:00:00"
    lux_umbr  = 30.0 if tipo_z == 5 else 40.0    # rural necesita menos lux mínimo

    politicas.append({
        "politica_id"                 : zid,
        "zona_id"                     : zid,
        "nombre_politica"             : f"Politica Zona {LOCALIDADES[zid-1][0]}",
        "hora_encendido"              : h_enc,
        "hora_apagado"                : h_apg,
        "nivel_lux_umbral"            : lux_umbr,
        "nivel_potencia_reduccion_pct": 80,
        "aplica_fines_semana"         : 1,
        "aplica_festivos"             : 1,
        "fecha_vigencia_desde"        : "2023-01-01",
        "fecha_vigencia_hasta"        : "",
        "activa"                      : 1,
        "descripcion"                 : "Política estándar de alumbrado público nocturno",
    })

df_politica = pd.DataFrame(politicas)
df_politica.to_csv(os.path.join(OUTPUT_DIR, "control_politica_iluminacion.csv"), index=False)
print(f"   → control_politica_iluminacion.csv  ({len(df_politica)} filas)")


# ─────────────────────────────────────────────────────────────
# 5. LECTURA AMBIENTE — 1.000.000 de registros
#    Columnas exactas para BULK INSERT en operativo.LecturaAmbiente:
#      sensor_id | condicion_clima_id | timestamp_lectura |
#      nivel_lux | temperatura_c | cobertura_nubosa_pct |
#      radiacion_solar_wm2 | anomalia_flag
# ─────────────────────────────────────────────────────────────
print("\n[5/6] Generando operativo.LecturaAmbiente (1.000.000 filas) ...")
print("      Esto puede tardar 30-90 segundos según el equipo...")

# ── Mapa zona → política (para saber hora de encendido/apagado) ──
hora_encendido_map = {}
hora_apagado_map   = {}
for p in politicas:
    zid = p["zona_id"]
    h_enc_h, h_enc_m, _ = map(int, p["hora_encendido"].split(":"))
    h_apg_h, h_apg_m, _ = map(int, p["hora_apagado"].split(":"))
    hora_encendido_map[zid] = h_enc_h + h_enc_m / 60.0
    hora_apagado_map[zid]   = h_apg_h + h_apg_m / 60.0

# Zona de cada sensor (array indexado por sensor_id 1-based)
zona_por_sensor = np.array([0] + [s["zona_id"] for s in sensores])   # índice 0 no se usa

# ── Generar timestamps distribuidos uniformemente en el rango ──
total_segundos  = int((FECHA_FIN - FECHA_INICIO).total_seconds())
offsets_seg     = np.sort(np.random.randint(0, total_segundos, size=N_REGISTROS))
# Redondear al minuto más cercano en múltiplos de 15 min
offsets_15min   = (offsets_seg // 900) * 900
timestamps_dt   = np.array([FECHA_INICIO + timedelta(seconds=int(o)) for o in offsets_15min])

# Extraer hora del día (float) para toda la serie de una sola vez
horas_dia       = np.array([ts.hour + ts.minute / 60.0 for ts in timestamps_dt])

# ── Asignar sensor_id ──
sensor_ids = np.random.randint(1, N_SENSORES + 1, size=N_REGISTROS)
zona_ids_l = zona_por_sensor[sensor_ids]       # zona correspondiente a cada lectura

# ── Calcular condición climática ──
# Bogotá: más lluvia en abril-mayo y oct-nov; más sol en dic-feb
meses = np.array([ts.month for ts in timestamps_dt])
# Probabilidades base por mes (Soleado, Nublado, Lluvioso, Despejado Nocturno)
PROB_CLIMA_DIA   = np.array([0.30, 0.40, 0.20, 0.10])   # día
PROB_CLIMA_NOCHE = np.array([0.00, 0.10, 0.15, 0.75])   # noche

es_dia_mask = (horas_dia >= 6) & (horas_dia < 18)

# Asignar clima vectorizado en bloque
condicion_clima_ids = np.empty(N_REGISTROS, dtype=np.int8)
# Meses lluviosos → aumentar prob lluvia
temporada_lluvia = np.isin(meses, [4, 5, 10, 11])

prob_dia_seca   = np.array([0.45, 0.35, 0.10, 0.10])
prob_dia_lluvia = np.array([0.10, 0.35, 0.45, 0.10])
prob_noc_seca   = np.array([0.00, 0.10, 0.10, 0.80])
prob_noc_lluvia = np.array([0.00, 0.10, 0.25, 0.65])

CLIMA_IDS = [1, 2, 3, 4]   # Soleado=1, Nublado=2, Lluvioso=3, Despejado Nocturno=4

for i in range(N_REGISTROS):
    if es_dia_mask[i]:
        prob = prob_dia_lluvia if temporada_lluvia[i] else prob_dia_seca
    else:
        prob = prob_noc_lluvia if temporada_lluvia[i] else prob_noc_seca
    condicion_clima_ids[i] = np.random.choice(CLIMA_IDS, p=prob)

# ── Calcular cobertura nubosa y radiación solar ──
cobertura_nubosa_pct = np.empty(N_REGISTROS, dtype=np.int8)
radiacion_solar_wm2  = np.empty(N_REGISTROS, dtype=np.float32)

mask_soleado  = condicion_clima_ids == 1
mask_nublado  = condicion_clima_ids == 2
mask_lluvioso = condicion_clima_ids == 3
mask_noct     = condicion_clima_ids == 4

cobertura_nubosa_pct[mask_soleado]  = np.random.randint(0,  20, mask_soleado.sum())
cobertura_nubosa_pct[mask_nublado]  = np.random.randint(40, 80, mask_nublado.sum())
cobertura_nubosa_pct[mask_lluvioso] = np.random.randint(75, 100, mask_lluvioso.sum())
cobertura_nubosa_pct[mask_noct]     = np.random.randint(0,  60, mask_noct.sum())

# Radiación solar solo existe de día y disminuye con nubosidad
rad_base = np.where(es_dia_mask,
                    700 * np.sin(np.pi * (horas_dia - 6) / 12).clip(0, 1),
                    0.0)
factor_nub = 1.0 - cobertura_nubosa_pct / 100.0 * 0.85
radiacion_solar_wm2 = (rad_base * factor_nub + np.random.normal(0, 15, N_REGISTROS)).clip(0, 850)

# ── Calcular nivel_lux ──
# Lux ambiente: combinación de luz solar (día) y luz artificial + luna (noche)
nivel_lux = np.empty(N_REGISTROS, dtype=np.float32)

# Día: entre 1000 y 50000 lux en pleno sol; baja con nubes
lux_solar   = radiacion_solar_wm2 * 120 * factor_nub
lux_dia     = (lux_solar + np.random.normal(0, 200, N_REGISTROS)).clip(50, 80000)

# Noche: solo luz artificial y ambiental (0.5–50 lux en ciudad)
lux_noche   = np.random.exponential(scale=12, size=N_REGISTROS).clip(0.5, 50)
# Un poco más de luz en zonas comerciales por contaminación lumínica
factor_zona = np.where(np.isin(zona_ids_l, [1, 2, 11, 13]), 1.5, 1.0)   # Usaquén, Chapinero, Suba, Teusaquillo

nivel_lux   = np.where(es_dia_mask, lux_dia, lux_noche * factor_zona)
nivel_lux   = nivel_lux.clip(0.5, 80000).round(2)

# ── Temperatura Bogotá: 7–19 °C con variación horaria ──
temp_base = np.random.uniform(11, 16, N_REGISTROS)      # media diaria aleatoria
temp_hora = np.sin(np.pi * (horas_dia - 6) / 12) * 3   # +3°C al mediodía
temperatura_c = (temp_base + temp_hora).clip(7.0, 19.0).round(2)

# ── Anomalia_flag (~2%) ──
anomalia_flag = (np.random.random(N_REGISTROS) < 0.02).astype(np.int8)

# ── Formatear timestamps ──
timestamps_str = np.array([ts.strftime("%Y-%m-%d %H:%M:%S") for ts in timestamps_dt])

# ── Construir DataFrame y exportar ──
df_lectura = pd.DataFrame({
    "sensor_id"             : sensor_ids.astype(np.int32),
    "condicion_clima_id"    : condicion_clima_ids.astype(np.int8),
    "timestamp_lectura"     : timestamps_str,
    "nivel_lux"             : nivel_lux.astype(np.float32).round(2),
    "temperatura_c"         : temperatura_c.astype(np.float32).round(2),
    "cobertura_nubosa_pct"  : cobertura_nubosa_pct.astype(np.int16).clip(0, 100),
    "radiacion_solar_wm2"   : radiacion_solar_wm2.astype(np.float32).round(2),
    "anomalia_flag"         : anomalia_flag.astype(np.int8),
})

# Verificación de rangos antes de exportar
print(f"   Verificando rangos ...")
assert df_lectura["sensor_id"].between(1, N_SENSORES).all(),         "ERROR: sensor_id fuera de rango"
assert df_lectura["condicion_clima_id"].between(1, 4).all(),         "ERROR: condicion_clima_id fuera de rango"
assert df_lectura["nivel_lux"].between(0.5, 80001).all(),            "ERROR: nivel_lux fuera de rango"
assert df_lectura["temperatura_c"].between(7.0, 19.0).all(),         "ERROR: temperatura_c fuera de rango"
assert df_lectura["cobertura_nubosa_pct"].between(0, 100).all(),     "ERROR: cobertura_nubosa_pct fuera de rango"
assert df_lectura["radiacion_solar_wm2"].between(0, 851).all(),      "ERROR: radiacion_solar_wm2 fuera de rango"
assert df_lectura["anomalia_flag"].isin([0, 1]).all(),                "ERROR: anomalia_flag con valores inválidos"
assert df_lectura.isnull().sum().sum() == 0,                         "ERROR: hay valores nulos"

anomalia_pct = df_lectura["anomalia_flag"].mean() * 100
print(f"   Anomalías: {anomalia_pct:.2f}%  (esperado ~2%)")
print(f"   Registros totales: {len(df_lectura):,}")

df_lectura.to_csv(
    os.path.join(OUTPUT_DIR, "lecturas_ambiente.csv"),
    index=False,
    sep=",",
    encoding="utf-8",
    date_format="%Y-%m-%d %H:%M:%S",
)
print(f"   → lecturas_ambiente.csv  ({len(df_lectura):,} filas)")


# ─────────────────────────────────────────────────────────────
# 6. CONSUMO ENERGÉTICO — derivado de LecturaAmbiente
#    Columnas exactas para operativo.ConsumoEnergetico:
#      luminaria_id | lectura_id (posición en CSV = fila +1) |
#      fecha_hora | kwh_consumido | estado_encendido |
#      potencia_activa_w | tarifa_cop_kwh
#
#    NOTA: lectura_id en el CSV corresponde a la posición de la
#    fila en lecturas_ambiente.csv (IDENTITY 1-based en SQL Server).
#    El Int. 1 deberá hacer un JOIN o usar el número de fila al
#    cargar en staging.
# ─────────────────────────────────────────────────────────────
print("\n[6/6] Generando operativo.ConsumoEnergetico (derivado) ...")

# Hora de encendido/apagado por zona
enc_por_zona = np.array([0.0] + [hora_encendido_map[z] for z in range(1, N_ZONAS + 1)])
apg_por_zona = np.array([0.0] + [hora_apagado_map[z]   for z in range(1, N_ZONAS + 1)])

h_enc_arr = enc_por_zona[zona_ids_l]    # hora encendido para cada lectura
h_apg_arr = apg_por_zona[zona_ids_l]    # hora apagado  para cada lectura

# Luminaria encendida si: es de noche (hora >= encendido O hora < apagado) Y sensor activo
es_noche_op = (horas_dia >= h_enc_arr) | (horas_dia < h_apg_arr)
estado_enc   = es_noche_op.astype(np.int8)

# Potencia nominal según tipo de lámpara (array luminaria_id → potencia)
pot_por_lum = np.array([0.0] + [l["potencia_w"] for l in luminarias])
luminaria_ids = sensor_ids     # relación 1:1
potencia_nominal = pot_por_lum[luminaria_ids]

# kWh consumidos en intervalo de 15 min (0.25 h)
# Si está encendida: P(W) * 0.25h / 1000 + pequeña variación
# Si está apagada : 0 (puede haber consumo residual mínimo)
ruido_kwh    = np.random.normal(0, 0.001, N_REGISTROS)
kwh_consumido = np.where(
    estado_enc == 1,
    (potencia_nominal * 0.25 / 1000) + ruido_kwh,
    np.random.uniform(0.0, 0.0005, N_REGISTROS)    # consumo residual mínimo
).clip(0.0, 0.15).round(4)

# Tarifa COP/kWh — Bogotá 2023-2024 aprox. 700-900 COP/kWh
tarifa_cop_kwh = np.random.uniform(700, 900, N_REGISTROS).round(2)

# lectura_id = posición 1-based de la fila en lecturas_ambiente.csv
lectura_ids = np.arange(1, N_REGISTROS + 1, dtype=np.int64)

df_consumo = pd.DataFrame({
    "luminaria_id"   : luminaria_ids.astype(np.int32),
    "lectura_id"     : lectura_ids,
    "fecha_hora"     : timestamps_str,
    "kwh_consumido"  : kwh_consumido,
    "estado_encendido": estado_enc.astype(np.int8),
    "potencia_activa_w": np.where(estado_enc == 1, potencia_nominal, 0.0).round(2),
    "tarifa_cop_kwh" : tarifa_cop_kwh,
})

df_consumo.to_csv(
    os.path.join(OUTPUT_DIR, "consumos_energeticos.csv"),
    index=False,
    sep=",",
    encoding="utf-8",
)
print(f"   → consumos_energeticos.csv  ({len(df_consumo):,} filas)")


# ─────────────────────────────────────────────────────────────
# 7. JSON MUESTRA — primeros 1000 registros de LecturaAmbiente
# ─────────────────────────────────────────────────────────────
muestra = df_lectura.head(1000).copy()
muestra_json = muestra.to_dict(orient="records")
with open(os.path.join(OUTPUT_DIR, "lecturas_muestra_1000.json"), "w", encoding="utf-8") as f:
    json.dump(muestra_json, f, ensure_ascii=False, indent=2)
print("\n   → lecturas_muestra_1000.json  (1 000 registros de muestra)")


# ─────────────────────────────────────────────────────────────
# 8. RESUMEN ESTADÍSTICO
# ─────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("  RESUMEN DEL DATASET GENERADO")
print("=" * 60)
print(f"\n  Archivos generados en: {os.path.abspath(OUTPUT_DIR)}/")
print(f"    maestro_zona.csv                  {len(df_zona):>10,} filas")
print(f"    maestro_sensor.csv                {len(df_sensor):>10,} filas")
print(f"    maestro_luminaria.csv             {len(df_luminaria):>10,} filas")
print(f"    control_politica_iluminacion.csv  {len(df_politica):>10,} filas")
print(f"    lecturas_ambiente.csv             {len(df_lectura):>10,} filas  ← BULK INSERT principal")
print(f"    consumos_energeticos.csv          {len(df_consumo):>10,} filas")
print(f"    lecturas_muestra_1000.json        {'1,000':>10} registros")

print("\n  Estadísticas de lecturas_ambiente.csv:")
print(f"    Rango temporal  : {df_lectura['timestamp_lectura'].min()} a {df_lectura['timestamp_lectura'].max()}")
print(f"    Sensores únicos : {df_lectura['sensor_id'].nunique()}")
print(f"    Nivel lux (med) : {df_lectura['nivel_lux'].median():.2f}  lux")
print(f"    Temperatura med : {df_lectura['temperatura_c'].median():.2f} °C")
print(f"    Anomalías       : {df_lectura['anomalia_flag'].sum():,} registros ({anomalia_pct:.2f}%)")
print(f"\n  Distribución condición climática:")
for cid, nombre in [(1,"Soleado"),(2,"Nublado"),(3,"Lluvioso"),(4,"Despejado Noct.")]:
    n = (df_lectura["condicion_clima_id"] == cid).sum()
    print(f"    {nombre:<20}: {n:>8,}  ({n/N_REGISTROS*100:.1f}%)")

print(f"\n  Estado encendido en ConsumoEnergetico:")
enc_pct = df_consumo["estado_encendido"].mean() * 100
print(f"    Encendidas : {enc_pct:.1f}%   Apagadas: {100-enc_pct:.1f}%")

print("\n" + "=" * 60)
print("  INSTRUCCIONES PARA EL INTEGRANTE 1 — BULK INSERT")
print("=" * 60)
print("""
  Orden de carga recomendado en SQL Server:

  1. Cargar catalogo.* (ya poblado por el DDL con datos semilla)
  2. BULK INSERT maestro_zona.csv          → maestro.Zona
  3. BULK INSERT maestro_sensor.csv        → maestro.Sensor
  4. BULK INSERT maestro_luminaria.csv     → maestro.Luminaria
  5. BULK INSERT control_politica...csv    → control.PoliticaIluminacion
  6. BULK INSERT lecturas_ambiente.csv     → operativo.LecturaAmbiente
     ─ Primero a tabla staging plana, luego INSERT SELECT hacia OLTP
  7. INSERT SELECT derivado de LecturaAmbiente → operativo.ConsumoEnergetico
     (o BULK INSERT consumos_energeticos.csv si se prefiere)
  8. INSERT SELECT WHERE anomalia_flag=1   → operativo.EventoAnomalia

  Parámetros del CSV:
    Separador   : coma (,)
    Encoding    : UTF-8
    Encabezados : primera fila (FIRSTROW = 2 en BULK INSERT)
    Fechas      : YYYY-MM-DD HH:MM:SS
    Nulos       : cadena vacía ('')
""")
print("  Script completado exitosamente.")
