# Plan de Desarrollo del Proyecto
## Sistema de Monitorización de Iluminación Inteligente — Bogotá D.C.
**Ciudades Inteligentes: Análisis de Datos para la Sostenibilidad Urbana**

> **Equipo:** 4 integrantes · **Duración:** 2 semanas · **Meta:** ~1 millón de registros listos para Power BI al final de la Semana 1

---

## Tabla de Contenidos

1. [Visión General del Proyecto](#1-visión-general-del-proyecto)
2. [Arquitectura de Datos](#2-arquitectura-de-datos)
3. [Semana 1 — Modelos de BD, Dataset y Carga](#3-semana-1--modelos-de-bd-dataset-y-carga)
   - [Integrante 1 — DBA / ETL Engineer](#integrante-1--dba--etl-engineer)
   - [Integrante 2 — Data Engineer](#integrante-2--data-engineer)
   - [Integrante 3 — Apoyo ETL + Maqueta](#integrante-3--apoyo-etl--maqueta)
   - [Integrante 4 — Documentación](#integrante-4--documentación)
4. [Semana 2 — Power BI, Web, ML y Entrega Final](#4-semana-2--power-bi-web-ml-y-entrega-final)
   - [Integrante 1 — Dashboard Power BI](#integrante-1--dashboard-power-bi)
   - [Integrante 2 — Sistema Web + Maqueta](#integrante-2--sistema-web--maqueta)
   - [Integrante 3 — Modelo ML + Visualización Web](#integrante-3--modelo-ml--visualización-web)
   - [Integrante 4 — Informe Final + Presentación](#integrante-4--informe-final--presentación)
5. [Entregables por Semana](#5-entregables-por-semana)
6. [Stack Tecnológico](#6-stack-tecnológico)
7. [Estructura del Repositorio](#7-estructura-del-repositorio)

---

## 1. Visión General del Proyecto

El proyecto consiste en construir un sistema de análisis Big Data para la red de alumbrado público de **Bogotá D.C.**, que permita identificar patrones de consumo energético ineficiente, detectar anomalías en luminarias y generar recomendaciones de política de iluminación por localidad.

### Flujo general del sistema

```
[Datasets Públicos Bogotá]
          │
          ▼
[Script Python — Generación ~1M registros]
          │
          ▼
[Modelo OLTP — SQL Server]  ◄── Fuente de verdad transaccional
          │
          │  Pipeline ETL (SSIS)
          ▼
[Data Warehouse — Star Schema SQL Server]  ◄── Power BI se conecta aquí
          │
          ├──► Power BI Dashboard
          ├──► Sistema Web (Chart.js + Leaflet)
          └──► Modelo ML (Random Forest) → Página Web de resultados
```

### Regla de oro del flujo de datos
> **Primero se carga TODO al modelo OLTP. Luego, mediante el proceso ETL con SSIS, se transforma y se carga al modelo multidimensional (DW).** El DW nunca recibe datos directamente del CSV.

---

## 2. Arquitectura de Datos

### 2.1 Modelo Transaccional OLTP — SQL Server

El modelo OLTP debe ser lo suficientemente completo para registrar toda la operación real del sistema. A continuación se definen las tablas requeridas:

#### Tablas del modelo OLTP

| Tabla | Propósito | Campos clave |
|---|---|---|
| `Zona` | Zonas/localidades de Bogotá | zona_id, nombre_zona, localidad, tipo_zona, latitud, longitud, poblacion, area_km2 |
| `Sensor` | Sensores instalados en cada luminaria | sensor_id, zona_id (FK), tipo_sensor, modelo, latitud, longitud, fecha_instalacion, estado |
| `Luminaria` | Cada punto de luz de la red | luminaria_id, sensor_id (FK), zona_id (FK), tipo_lampara, potencia_w, estado_actual, fecha_instalacion |
| `LecturaAmbiente` | **Tabla principal — millones de filas** | lectura_id, sensor_id (FK), timestamp, nivel_lux, temperatura_c, condicion_clima, cobertura_nubosa_pct, radiacion_solar_wm2 |
| `ConsumoEnergetico` | Consumo por luminaria y periodo | consumo_id, luminaria_id (FK), lectura_id (FK), fecha_hora, kwh_consumido, estado_encendido, tarifa_cop |
| `EventoAnomalia` | Fallas, consumo anormal | evento_id, luminaria_id (FK), fecha_hora, tipo_anomalia, descripcion, nivel_severidad, resuelto |
| `PoliticaIluminacion` | Reglas de encendido/apagado por zona | politica_id, zona_id (FK), hora_encendido, hora_apagado, nivel_lux_umbral, activa |

> **¿Qué tan amplio debe ser el OLTP?** Las 7 tablas anteriores son suficientes para este proyecto académico. El nivel de normalización es **3FN**. No es necesario ir más allá: el objetivo es que el OLTP registre fielmente la operación y sirva como fuente limpia para el ETL hacia el DW.

---

### 2.2 Modelo Multidimensional OLAP — Data Warehouse (Star Schema)

#### Tabla de Hechos

```
FactConsumoIluminacion
├── hecho_id          (PK)
├── tiempo_id         (FK → DimTiempo)
├── zona_id           (FK → DimZona)
├── sensor_id         (FK → DimSensor)
├── clima_id          (FK → DimClima)
├── politica_id       (FK → DimPolitica)   ← dimensión adicional recomendada
├── nivel_lux
├── consumo_kwh
├── estado_encendido
├── lux_optimo_predicho                    ← se llena en Semana 2 con el modelo ML
├── diferencia_lux                         ← nivel_lux - lux_optimo_predicho
├── ahorro_kwh_estimado
└── anomalia_flag
```

#### Dimensiones

| Dimensión | Campos principales | Para qué sirve en Power BI |
|---|---|---|
| `DimTiempo` | tiempo_id, fecha, anio, semestre, mes, semana, dia, hora, dia_semana, es_festivo | Drill-down temporal (año→mes→día→hora) |
| `DimZona` | zona_id, nombre_zona, localidad, tipo_zona, latitud, longitud, poblacion, area_km2 | Filtrado por localidad y mapa de Bogotá |
| `DimSensor` | sensor_id, tipo_sensor, modelo, fabricante, fecha_instalacion, estado | Análisis por tipo/estado del sensor |
| `DimClima` | clima_id, condicion, cobertura_nubosa_pct, radiacion_wm2, temperatura_c | Correlación clima-consumo |
| `DimPolitica` | politica_id, nombre_politica, hora_encendido, hora_apagado, lux_umbral | Evaluar efectividad de políticas |

> **Nota sobre `DimPolitica`:** Se recomienda agregar esta dimensión para que Power BI pueda comparar el consumo real contra la política de iluminación activa en cada zona, lo que enriquece el análisis considerablemente sin añadir complejidad excesiva.

---

## 3. Semana 1 — Modelos de BD, Dataset y Carga

> **Objetivo de la semana:** Al finalizar el día 7, tener ambos modelos implementados en SQL Server con el millón de registros cargados y disponibles para conectar Power BI en clase.

---

### Integrante 1 — DBA / ETL Engineer

**Rol:** Diseño e implementación de ambos modelos de base de datos + pipeline ETL OLTP → DW.

---

#### Días 1–2: Diseño del Modelo OLTP

- [ ] Diseñar el diagrama ERD completo con las 7 tablas descritas en la sección 2.1
- [ ] Definir todos los tipos de datos, constraints (NOT NULL, CHECK, UNIQUE) y relaciones FK
- [ ] Generar el **script DDL completo** (`modelo_transaccional_DDL.sql`) con:
  - `CREATE DATABASE IluminacionBogota_OLTP`
  - `CREATE TABLE` para las 7 tablas en orden de dependencia (primero las maestras, luego las transaccionales)
  - Índices en `LecturaAmbiente(timestamp)`, `LecturaAmbiente(sensor_id)`, `ConsumoEnergetico(fecha_hora)`
- [ ] Crear el diagrama visual con Draw.io o el Diagram Designer de SSMS
- [ ] Ejecutar el script y verificar que la BD queda vacía pero funcional

**Tip:** Crear la BD con el siguiente orden de tablas evita errores de FK: `Zona → Sensor → Luminaria → PoliticaIluminacion → LecturaAmbiente → ConsumoEnergetico → EventoAnomalia`

---

#### Días 2–3: Diseño del Modelo Multidimensional

- [ ] Diseñar el Star Schema con la tabla de hechos y las 5 dimensiones (sección 2.2)
- [ ] Generar el **script DDL completo** (`modelo_dimensional_DDL.sql`) con:
  - `CREATE DATABASE IluminacionBogota_DW`
  - `CREATE TABLE` para las 5 dimensiones primero, luego `FactConsumoIluminacion`
  - Índices en las FK de la tabla de hechos para optimizar consultas Power BI
- [ ] Documentar el Star Schema con un diagrama visual
- [ ] Ejecutar el script y verificar la BD vacía

---

#### Días 3–4: Preparación para Carga Masiva al OLTP

> En cuanto el Integrante 2 entregue el CSV (~día 4), iniciar la carga.

- [ ] Preparar el script de **carga al OLTP** en este orden:
  1. Poblar `Zona` (20 localidades de Bogotá con datos reales)
  2. Poblar `Sensor` (registros únicos de sensores del dataset)
  3. Poblar `Luminaria` (registros únicos de luminarias)
  4. Poblar `PoliticaIluminacion` (políticas por zona, pueden ser fijas/simuladas)
  5. **Carga masiva de `LecturaAmbiente`** con `BULK INSERT` desde el CSV
  6. Poblar `ConsumoEnergetico` derivando datos de `LecturaAmbiente`
  7. Poblar `EventoAnomalia` filtrando registros con `anomalia_flag = 1`
- [ ] Ejecutar la carga y verificar el conteo de filas en cada tabla

```sql
-- Verificación rápida después de la carga
SELECT 'Zona' AS Tabla, COUNT(*) AS Registros FROM Zona
UNION ALL SELECT 'Sensor', COUNT(*) FROM Sensor
UNION ALL SELECT 'LecturaAmbiente', COUNT(*) FROM LecturaAmbiente
UNION ALL SELECT 'ConsumoEnergetico', COUNT(*) FROM ConsumoEnergetico;
```

---

#### Días 5–6: Pipeline ETL OLTP → Data Warehouse (SSIS)

> Este es el paso más crítico de la semana. El DW solo se alimenta desde el OLTP.

- [ ] Crear el proyecto SSIS en Visual Studio: `ProyectoETL_IluminacionBogota`
- [ ] Implementar el flujo de **carga de dimensiones** (deben cargarse antes que los hechos):

  **Flujo 1 — CargarDimTiempo:**
  - Generar la dimensión de tiempo programáticamente (rango de fechas del dataset)
  - Descomponer cada timestamp en: año, semestre, mes, semana, día, hora, día_semana, es_festivo
  - Cargar a `DimTiempo` en el DW

  **Flujo 2 — CargarDimZona:**
  - Source: tabla `Zona` del OLTP
  - Transformación: renombrar/mapear campos al esquema de la dimensión
  - Destination: `DimZona` en el DW

  **Flujo 3 — CargarDimSensor:**
  - Source: tabla `Sensor` del OLTP
  - Destination: `DimSensor` en el DW

  **Flujo 4 — CargarDimClima:**
  - Source: columnas de clima de `LecturaAmbiente` en el OLTP
  - Transformación: `DISTINCT` para obtener combinaciones únicas de condiciones climáticas
  - Destination: `DimClima` en el DW

  **Flujo 5 — CargarDimPolitica:**
  - Source: tabla `PoliticaIluminacion` del OLTP
  - Destination: `DimPolitica` en el DW

  **Flujo 6 — CargarFactConsumoIluminacion (el más importante):**
  - Source: JOIN entre `LecturaAmbiente`, `ConsumoEnergetico`, `Sensor` y `Luminaria` del OLTP
  - Transformaciones:
    - Lookup de `tiempo_id` en `DimTiempo` por fecha/hora
    - Lookup de `zona_id` en `DimZona`
    - Lookup de `clima_id` en `DimClima`
    - Lookup de `politica_id` en `DimPolitica`
    - Calcular `ahorro_kwh_estimado` = `consumo_real - consumo_optimo_referencia`
  - Destination: `FactConsumoIluminacion` en el DW

- [ ] Ejecutar el paquete SSIS completo y verificar conteo en la tabla de hechos
- [ ] Documentar el pipeline con capturas de cada Data Flow

---

#### Día 7: Validación Final y Documentación

- [ ] Ejecutar queries de validación cruzada OLTP vs DW:
  ```sql
  -- Verificar que el total de hechos coincide con lecturas del OLTP
  SELECT COUNT(*) FROM IluminacionBogota_OLTP.dbo.LecturaAmbiente;
  SELECT COUNT(*) FROM IluminacionBogota_DW.dbo.FactConsumoIluminacion;
  ```
- [ ] Verificar que todas las FK del DW resuelven correctamente (sin huérfanos)
- [ ] Tomar capturas de pantalla de ambos modelos en SSMS para el informe
- [ ] Entregar al equipo: scripts DDL, diagramas y confirmación de BDs listas

> **¿Cómo repartir el ETL con el Integrante 3?** El Integrante 3 se encarga de los Flujos 1 al 5 (dimensiones) y el Integrante 1 se enfoca en el Flujo 6 (tabla de hechos), que es el más complejo. Ver detalle en la sección del Integrante 3.

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 1 Semana 1

- **No intentar cargar todo en un solo día.** La carga masiva del millón de registros puede tardar minutos dependiendo del equipo. Hacer pruebas primero con 10.000 filas.
- **BULK INSERT requiere que el CSV esté en el servidor SQL o en una ruta de red accesible.** Si trabajan en local, usar `OPENROWSET` o importar primero a una tabla staging.
- **Crear una tabla `StagingLecturas`** (copia plana del CSV) antes del OLTP puede simplificar el proceso: primero todo el CSV va a staging, luego se distribuye a las tablas normalizadas.
- **Priorizar tener el DW listo sobre el OLTP perfecto.** Power BI se conecta al DW; si el tiempo aprieta, asegúrate de que el DW tenga datos antes de que el OLTP esté 100% completo.

---

### Integrante 2 — Data Engineer

**Rol:** Obtención/generación del dataset de ~1 millón de registros y entrega limpia al equipo.

---

#### Día 1: Búsqueda de Datasets Públicos

**Opción A — Fuentes primarias de Bogotá (preferidas):**
- [datosabiertos.bogota.gov.co](https://datosabiertos.bogota.gov.co) → buscar: *"alumbrado público"*, *"luminarias"*, *"consumo energético"*
- [datos.gov.co](https://datos.gov.co) → buscar: *"alumbrado"*, *"energía"*, *"Bogotá"*
- IDECA (Infraestructura de Datos Espaciales de Bogotá) → coordenadas de luminarias
- IDEAM → datos climáticos históricos Bogotá (radiación solar, nubosidad por hora)

**Opción B — Respaldo si no se encuentran datos de Bogotá:**
- [UCI ML Repository — Energy datasets](https://archive.ics.uci.edu/datasets) → buscar *"energy"* o *"lighting"*
- [Kaggle — Smart City / Street Lighting datasets](https://www.kaggle.com/datasets) → buscar *"street lighting"*, *"smart city energy"*
- [Open Power System Data](https://open-power-system-data.org) → datos de consumo eléctrico por hora (adaptable)
- [NYC Open Data — Street Lighting](https://opendata.cityofnewyork.us) → estructura similar, se adaptan las zonas a localidades de Bogotá

> **Si se usa la Opción B:** No importa que los datos originales sean de otra ciudad. Lo que interesa es la **estructura y distribución estadística**: niveles de lux por hora, consumo kWh, condiciones climáticas. Luego se asignan zonas/localidades de Bogotá en el script de generación.

- [ ] Descargar al menos 1 dataset de referencia con cualquiera de las dos opciones
- [ ] Identificar: rangos reales de nivel_lux (típico: 5–500 lux en ambiente urbano nocturno), consumo kWh por luminaria, variaciones por hora del día

---

#### Días 2–3: Script Python de Generación del Dataset

El script debe generar un CSV con la estructura exacta que el Integrante 1 necesita para el BULK INSERT.

```python
# Estructura mínima del dataset generado
# Archivo: generar_dataset.py

import pandas as pd
import numpy as np
from faker import Faker
import random
from datetime import datetime, timedelta

# Parámetros
N_REGISTROS    = 1_000_000
N_SENSORES     = 500        # sensores distribuidos en Bogotá
N_ZONAS        = 20         # 20 localidades de Bogotá
FECHA_INICIO   = datetime(2023, 1, 1)
FECHA_FIN      = datetime(2024, 12, 31)

# Localidades reales de Bogotá
LOCALIDADES = [
    "Usaquén", "Chapinero", "Santa Fe", "San Cristóbal", "Usme",
    "Tunjuelito", "Bosa", "Kennedy", "Fontibón", "Engativá",
    "Suba", "Barrios Unidos", "Teusaquillo", "Los Mártires", "Antonio Nariño",
    "Puente Aranda", "La Candelaria", "Rafael Uribe", "Ciudad Bolívar", "Sumapaz"
]

# Lógica de simulación:
# - nivel_lux alto (> 100) durante el día → luminaria apagada
# - nivel_lux bajo (< 20) en la noche → luminaria encendida
# - variación por nubosidad: más nubes → menos lux natural
# - anomalía: ~2% de registros con consumo fuera de rango
```

**Columnas del CSV de salida:**

| Campo | Tipo | Rango / Valores |
|---|---|---|
| `sensor_id` | INT | 1 – 500 |
| `luminaria_id` | INT | sensor_id (relación 1:1 para simplificar) |
| `zona_id` | INT | 1 – 20 |
| `timestamp` | DATETIME | 2023-01-01 a 2024-12-31 |
| `nivel_lux` | FLOAT | 0.5 – 500.0 (varía por hora y clima) |
| `temperatura_c` | FLOAT | 7.0 – 19.0 (rango Bogotá) |
| `condicion_clima` | VARCHAR | Soleado / Nublado / Lluvioso / Despejado Nocturno |
| `cobertura_nubosa_pct` | INT | 0 – 100 |
| `radiacion_solar_wm2` | FLOAT | 0 – 850 |
| `kwh_consumido` | FLOAT | 0.0 – 0.15 (0 si apagada) |
| `estado_encendido` | BIT | 0 / 1 |
| `anomalia_flag` | BIT | 0 (98%) / 1 (2%) |

- [ ] Implementar la lógica de simulación realista (lux depende de hora + clima)
- [ ] Generar el CSV completo con 1.000.000 de filas
- [ ] Validar: sin nulos en campos críticos, rangos coherentes, distribución de anomalías ~2%
- [ ] Exportar también un JSON con los primeros 1000 registros para pruebas rápidas

---

#### Día 4: Entrega del Dataset al Equipo

- [ ] Subir el CSV al repositorio Git (o compartir por Drive si es muy grande)
- [ ] Entregar al Integrante 1 para iniciar la carga al OLTP
- [ ] Documentar brevemente el script: qué datos se usaron de base, qué supuestos se hicieron

---

#### Días 5–7: Apoyo al Proceso de Carga

- [ ] Apoyar al Integrante 1 si hay problemas con el formato del CSV para BULK INSERT
- [ ] Ajustar el script si se detectan inconsistencias en los datos durante la carga
- [ ] Verificar que el CSV tiene el separador correcto, encoding UTF-8 y sin caracteres especiales que rompan la importación

> **Nota importante:** Ya no es necesario cargar datos en MongoDB. El foco es tener SQL Server (OLTP + DW) completamente operativo para Power BI.

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 2 Semana 1

- **El CSV debe tener encabezados que coincidan exactamente con las columnas del OLTP.** Coordinar con el Integrante 1 los nombres exactos de campos antes de generar el archivo final.
- **Para el BULK INSERT:** el CSV debe usar coma como separador, comillas para strings con espacios, y fecha en formato `YYYY-MM-DD HH:MM:SS`.
- **Si el millón de filas hace el CSV muy pesado:** generar primero 100.000 registros para pruebas, y el millón solo cuando el schema esté validado. Evita cargas fallidas repetidas.
- **Guardar el script de generación en el repositorio** con comentarios claros: es parte del entregable técnico.

---

### Integrante 3 — Apoyo ETL + Diseño de Maqueta

**Rol:** Apoyar la carga de dimensiones al DW via SSIS + diseñar y cotizar la maqueta del sensor para compra.

> **Cambio de semana:** El análisis EDA y el modelo ML se trasladan a la Semana 2. Esta semana el foco es dar soporte al proceso ETL y adelantar el diseño de la maqueta física.

---

#### Días 1–2: Familiarización con los Modelos y SSIS

- [ ] Revisar los scripts DDL del Integrante 1 y entender la estructura del OLTP y el DW
- [ ] Instalar y configurar Visual Studio con las extensiones de SSIS (SQL Server Data Tools)
- [ ] Crear el proyecto SSIS conjunto con el Integrante 1 en el repositorio
- [ ] Aprender el flujo básico de un paquete SSIS: Connection Managers, Data Flow Task, transformaciones

---

#### Días 3–5: Implementar Flujos SSIS de Dimensiones (Flujos 1–5)

> El Integrante 1 se encarga del Flujo 6 (tabla de hechos). El Integrante 3 implementa los flujos de dimensiones, que son más directos.

**Flujo 1 — Paquete `CargarDimTiempo.dtsx`:**
- [ ] Generar la dimensión de tiempo con un script C# o SQL dentro del paquete
- [ ] Rango: cubrir todas las fechas/horas del dataset (2023–2024)
- [ ] Descomponer timestamp en todos los atributos de `DimTiempo`
- [ ] Marcar festivos de Colombia (se puede usar una tabla de referencia simple)

**Flujo 2 — Paquete `CargarDimZona.dtsx`:**
- [ ] Source: `SELECT * FROM IluminacionBogota_OLTP.dbo.Zona`
- [ ] Destination: `IluminacionBogota_DW.dbo.DimZona`
- [ ] Verificar que los 20 registros de zonas se copian correctamente

**Flujo 3 — Paquete `CargarDimSensor.dtsx`:**
- [ ] Source: `SELECT * FROM IluminacionBogota_OLTP.dbo.Sensor`
- [ ] Destination: `IluminacionBogota_DW.dbo.DimSensor`

**Flujo 4 — Paquete `CargarDimClima.dtsx`:**
- [ ] Source: `SELECT DISTINCT condicion_clima, cobertura_nubosa_pct, radiacion_solar_wm2, temperatura_c FROM LecturaAmbiente`
- [ ] Agrupar por rangos para crear registros de dimensión únicos (no cargar millón de filas, solo combinaciones distintas)
- [ ] Destination: `IluminacionBogota_DW.dbo.DimClima`

**Flujo 5 — Paquete `CargarDimPolitica.dtsx`:**
- [ ] Source: `SELECT * FROM IluminacionBogota_OLTP.dbo.PoliticaIluminacion`
- [ ] Destination: `IluminacionBogota_DW.dbo.DimPolitica`

- [ ] Ejecutar todos los paquetes y verificar conteos en cada dimensión del DW
- [ ] Documentar con capturas de pantalla de Visual Studio + SSIS

---

#### Días 5–7: Diseño de la Maqueta del Sensor

> El objetivo es tener una lista de materiales y cotización lista para comprar durante o después de la semana 1, de modo que la maqueta esté disponible para armar en la semana 2.

**Componentes sugeridos para la maqueta:**

| Componente | Función | Alternativa económica |
|---|---|---|
| Arduino Uno / Nano | Microcontrolador principal | ESP32 (WiFi incluido) |
| Sensor LDR (fotorresistencia) | Medir nivel de luz ambiental | Módulo BH1750 (más preciso) |
| LED (varios colores) | Simular el encendido de la luminaria | LED RGB |
| Resistencias 10kΩ y 220Ω | Circuito divisor de voltaje para LDR | Incluidas en kit Arduino |
| Breadboard | Montaje sin soldadura | - |
| Cables jumper | Conexiones | - |
| Display LCD 16x2 (opcional) | Mostrar el nivel de lux en tiempo real | OLED 0.96" |

**Diagrama conceptual del circuito:**
```
5V ──── LDR ──── A0 (Arduino)
                  │
                 10kΩ
                  │
                GND

Arduino Pin 9 ──── 220Ω ──── LED (+) ──── GND
```

**Lógica del sketch Arduino:**
- Leer valor analógico del LDR → convertir a lux
- Si lux < umbral (ej: 50 lux) → encender LED (simula luminaria ON)
- Si lux ≥ umbral → apagar LED (simula luminaria OFF)
- Imprimir por Serial: `sensor_id, timestamp, nivel_lux, estado`

- [ ] Elaborar la lista de materiales con precios en tiendas locales (Mercado Libre CO, tiendas electrónica)
- [ ] Proponer el diseño del sketch Arduino básico
- [ ] Verificar disponibilidad de materiales para tenerlos listos en Semana 2

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 3 Semana 1

- **Los paquetes SSIS de dimensiones son más simples que el de hechos.** Son básicamente un Source → (transformación mínima) → Destination. No se necesita mucha lógica.
- **DimTiempo es el más importante de implementar bien**, porque el drill-down temporal en Power BI depende completamente de esta dimensión. Asegúrate de que la columna `hora` va de 0 a 23 y que `dia_semana` usa un estándar consistente (1=Lunes o 1=Domingo, definirlo y documentarlo).
- **Para la maqueta:** no es necesario comprar el módulo BH1750 si el tiempo y presupuesto no dan; el LDR con divisor de voltaje es suficiente para la demostración del concepto.
- **Coordinar constantemente con el Integrante 1** para que los paquetes SSIS trabajen sobre las mismas cadenas de conexión y nombres de BD.

---

### Integrante 4 — Documentación del Proyecto

**Rol:** Documentar todo lo que el equipo va construyendo y redactar las secciones 1–3 del informe técnico.

---

#### Días 1–2: Investigación y Marco Teórico

- [ ] Investigar y redactar la sección de **contexto** del informe:
  - Estadísticas de alumbrado público en Bogotá (gasto anual, número de luminarias, localidades)
  - Qué son las ciudades inteligentes y cómo se relacionan con Big Data
  - Qué son los sistemas de iluminación inteligente (referencia a conceptos IoT/Smart City)
- [ ] Documentar los datasets públicos encontrados por el Integrante 2: fuente, URL, estructura, calidad

---

#### Días 2–4: Documentación de los Modelos de BD

- [ ] Redactar la sección de **arquitectura de datos** del informe:
  - Descripción del modelo OLTP: propósito, tablas, relaciones
  - Incluir el diagrama ERD (provisto por el Integrante 1) con explicación de cada entidad
  - Descripción del modelo multidimensional: propósito, Star Schema, tabla de hechos y dimensiones
  - Incluir el diagrama Star Schema con explicación
- [ ] Documentar el flujo de datos: desde el CSV hasta el DW, pasando por el OLTP

---

#### Días 4–6: Documentación del Dataset y ETL

- [ ] Redactar la sección de **dataset y generación de datos**:
  - Estrategia híbrida: fuentes públicas + simulación Python
  - Descripción del script de generación (Int. 2): supuestos, rangos, lógica de simulación
  - Tabla de campos del CSV con descripción de cada variable
- [ ] Documentar el **proceso ETL** con capturas de SSIS del Integrante 1 y 3:
  - Flujo general del pipeline
  - Descripción de cada paquete/flujo de datos
  - Transformaciones aplicadas

---

#### Día 7: Cierre de Semana y Repositorio

- [ ] Consolidar todo lo avanzado en el informe (secciones 1–3 completas)
- [ ] Actualizar el README del repositorio Git con el estado actual del proyecto
- [ ] Hacer commit de todos los archivos de la semana: scripts SQL, paquetes SSIS, CSV (o link), informe parcial

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 4 Semana 1

- **Estar en contacto constante con los demás integrantes** para documentar a medida que avanzan, no al final. Es más fácil documentar mientras se hace que reconstruir después.
- **Pedir las capturas de pantalla** (SSMS, diagrama ERD, SSIS) durante la semana, no el día 7.
- **El informe debe ser técnico pero legible.** Incluir fragmentos del DDL SQL como referencia es válido y le da solidez al documento.
- **Mantener el repositorio Git organizado** desde el inicio; es mucho más difícil reorganizarlo después con commits desordenados.

---

## 4. Semana 2 — Power BI, Web, ML y Entrega Final

> **Objetivo:** Con los datos ya cargados, construir en paralelo el dashboard Power BI, el sistema web, el modelo ML y consolidar el informe final. Proyecto 100% completo al final del día 14.

---

### Integrante 1 — Dashboard Power BI

**Rol:** Construir el dashboard interactivo de Power BI conectado al Data Warehouse.

---

#### Días 8–9: Conexión y Modelo de Datos en Power BI

- [ ] Conectar Power BI Desktop al DW en SQL Server (`Get Data → SQL Server`)
- [ ] Importar: `FactConsumoIluminacion`, `DimTiempo`, `DimZona`, `DimSensor`, `DimClima`, `DimPolitica`
- [ ] Verificar que Power BI detecta las relaciones automáticamente; ajustar manualmente si es necesario
- [ ] Crear jerarquía de tiempo: `Año → Semestre → Mes → Semana → Día → Hora`
- [ ] Crear medidas DAX base:
  ```dax
  Total kWh = SUM(FactConsumoIluminacion[consumo_kwh])
  Promedio Lux = AVERAGE(FactConsumoIluminacion[nivel_lux])
  % Luminarias Encendidas = DIVIDE(COUNTROWS(FILTER(Fact..., estado_encendido=1)), COUNTROWS(Fact...))
  Ahorro Total kWh = SUM(FactConsumoIluminacion[ahorro_kwh_estimado])
  Total Anomalias = COUNTROWS(FILTER(Fact..., anomalia_flag=1))
  ```

---

#### Días 10–11: Página 1 — Mapa y Resumen General

- [ ] Insertar visual de **Mapa** (ArcGIS Maps o mapa de formas de Bogotá) por localidad
- [ ] Colorear por `consumo_kwh` total → zonas de mayor gasto en rojo
- [ ] Agregar KPI cards: Total kWh consumido, % luminarias activas, Total anomalías, Ahorro estimado
- [ ] Agregar filtros por: rango de fechas, localidad, condición climática
- [ ] Agregar gráfico de barras: consumo por localidad (top 5 zonas más costosas)

---

#### Días 12–13: Página 2 — Análisis Temporal / Página 3 — Anomalías

**Página 2 — Consumo y Tendencias:**
- [ ] Gráfico de línea: consumo kWh por hora del día (promedio)
- [ ] Gráfico de área: evolución mensual del consumo total
- [ ] Gráfico de dispersión: nivel_lux vs consumo_kwh (detectar correlación)
- [ ] Tabla de comparativo: consumo real vs consumo óptimo por zona

**Página 3 — Anomalías y Alertas:**
- [ ] Tabla de las últimas 50 anomalías con zona, tipo y nivel de severidad
- [ ] Gráfico de barras: distribución de anomalías por localidad
- [ ] KPI: % de anomalías resueltas vs pendientes
- [ ] Condicional: filas en rojo cuando `nivel_severidad = 'Alta'`

---

#### Día 14: Revisión Final y Exportación

- [ ] Pulir diseño: paleta de colores consistente, títulos claros, logo del proyecto
- [ ] Exportar el reporte en PDF para incluir en el informe
- [ ] Tomar capturas de pantalla de cada página para la presentación
- [ ] Publicar en Power BI Service (opcional, si hay cuenta disponible)

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 1 Semana 2

- **Power BI puede ser lento con 1M de filas en modo Import.** Considerar usar `DirectQuery` o aplicar una vista SQL que pre-agregue datos por hora y zona antes de importar a Power BI.
- **Las medidas DAX son más potentes que las columnas calculadas** para métricas agregadas. Preferir siempre medidas.
- **El mapa de Bogotá por localidades puede requerir un shapefile GeoJSON.** Buscarlo en IDECA o en el portal de datos abiertos de Bogotá para usar el visual de mapa de formas.

---

### Integrante 2 — Sistema Web + Maqueta Física

**Rol:** Desarrollar la interfaz web del proyecto y construir la maqueta del sensor.

---

#### Días 8–9: Estructura del Sistema Web

- [ ] Definir la estructura de carpetas del proyecto web:
  ```
  /web
    index.html          ← Página de inicio del proyecto
    dashboard.html      ← Panel de visualizaciones
    recomendaciones.html ← Resultados y recomendaciones
    /css
      styles.css
    /js
      charts.js
      map.js
  ```
- [ ] Desarrollar `index.html`: descripción del proyecto, ciudad objetivo (Bogotá), ODS relacionados, tecnologías usadas, equipo de trabajo. Diseño responsivo y limpio.

---

#### Días 10–11: Panel de Visualización

- [ ] Desarrollar `dashboard.html` con:
  - Gráfico de línea con Chart.js: consumo kWh por hora del día (usar datos embebidos del análisis)
  - Gráfico de barras: top 5 localidades de Bogotá con mayor consumo
  - KPI cards: total registros analizados, ahorro estimado, % anomalías detectadas
  - Mapa de Bogotá con Leaflet.js: marcadores por localidad con popup de consumo promedio

---

#### Días 12–13: Sección de Recomendaciones

- [ ] Desarrollar `recomendaciones.html` con:
  - Tabla de hallazgos por localidad (exportar los datos clave del análisis como JSON estático)
  - Gráfico comparativo: consumo real vs consumo óptimo por zona
  - Sección de recomendaciones de política: 3–5 propuestas concretas para Bogotá

---

#### Días 12–14: Construcción de la Maqueta

> Con los componentes adquiridos según el diseño del Integrante 3 en la Semana 1.

- [ ] Armar el circuito en breadboard: LDR + Arduino + LED
- [ ] Cargar el sketch básico: lectura de lux → lógica encendido/apagado
- [ ] Demostrar el concepto: cubrir el sensor con la mano → LED se enciende; iluminar el sensor → LED se apaga
- [ ] (Opcional) Conectar el Arduino a la laptop y capturar lecturas en tiempo real vía Serial → CSV

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 2 Semana 2

- **Los datos del dashboard web pueden ser estáticos** (hardcodeados como JSON en el JS o en archivos `.json`). No es necesario conectar la web a SQL Server en tiempo real para este proyecto académico.
- **Usar Bootstrap o Tailwind CDN** para el diseño responsivo sin necesidad de instalar nada. Un diseño limpio y profesional importa en la presentación.
- **La maqueta no necesita ser perfecta, solo funcional.** Lo importante es demostrar el concepto: el sensor detecta luz → el sistema decide encender o apagar → eso es exactamente lo que hace el sistema a gran escala.

---

### Integrante 3 — Modelo ML + Visualización Web de Resultados

**Rol:** Entrenar el modelo de Machine Learning y exponer sus resultados en una página web del sistema.

> **Cambio de semana:** El EDA básico y el modelo predictivo se realizan esta semana (no en Semana 1). La optimización/validación del DW que estaba asignada al Integrante 3 se delega parcialmente al Integrante 1.

---

#### Días 8–9: Análisis Exploratorio (EDA) Rápido

- [ ] Conectar Jupyter Notebook a SQL Server o cargar el CSV directamente con Pandas
- [ ] Realizar estadísticas descriptivas clave:
  - Distribución de `nivel_lux` por hora del día (promedio por zona)
  - Distribución de `consumo_kwh` por localidad
  - Correlación entre `cobertura_nubosa_pct` y `nivel_lux`
  - Porcentaje de anomalías por zona
- [ ] Generar 4–6 gráficas representativas con Matplotlib/Seaborn
- [ ] Identificar los patrones más relevantes (insumo para la sección de recomendaciones)

---

#### Días 10–12: Entrenamiento del Modelo ML

**Objetivo del modelo:** Predecir el `nivel_lux` óptimo (o el `estado_encendido` ideal) dada la hora, zona y condición climática.

- [ ] Definir el problema ML:
  - **Variable target:** `estado_encendido` (clasificación binaria) **o** `lux_optimo` (regresión)
  - **Features:** `hora`, `zona_id`, `cobertura_nubosa_pct`, `radiacion_solar_wm2`, `temperatura_c`, `dia_semana`, `es_festivo`

- [ ] Preparar los datos:
  ```python
  from sklearn.model_selection import train_test_split
  from sklearn.ensemble import RandomForestClassifier
  from sklearn.metrics import classification_report, accuracy_score

  # Cargar datos desde CSV
  df = pd.read_csv('dataset_1M_registros.csv')
  features = ['hora', 'zona_id', 'cobertura_nubosa_pct', 'radiacion_solar_wm2', 'temperatura_c']
  X = df[features]
  y = df['estado_encendido']

  X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
  ```

- [ ] Entrenar el modelo:
  ```python
  model = RandomForestClassifier(n_estimators=100, random_state=42)
  model.fit(X_train, y_train)
  y_pred = model.predict(X_test)
  print(classification_report(y_test, y_pred))
  ```

- [ ] Evaluar métricas: Accuracy, Precision, Recall, F1-Score
- [ ] Exportar el modelo entrenado con `joblib`:
  ```python
  import joblib
  joblib.dump(model, 'modelo_iluminacion.pkl')
  ```

- [ ] **Generar predicciones para el dataset completo** y guardar en CSV:
  ```python
  df['estado_predicho'] = model.predict(df[features])
  df['correcto'] = (df['estado_encendido'] == df['estado_predicho']).astype(int)
  df.to_csv('predicciones_modelo.csv', index=False)
  ```

> **Nota:** Este modelo es **estático** (entrenado una vez, no en tiempo real). Se usa para evaluar cuántas veces el sistema actual toma la decisión incorrecta de encendido/apagado.

---

#### Días 13–14: Página Web de Resultados del Modelo ML

- [ ] Crear `modelo_ml.html` dentro del sistema web del Integrante 2
- [ ] Incluir en la página:
  - Descripción del modelo: qué predice, qué variables usa, por qué Random Forest
  - Tabla de métricas de evaluación (Accuracy, Precision, Recall, F1)
  - Gráfico de barras: importancia de features (qué variable influye más en la decisión)
  - Gráfico de línea o área: % de predicciones correctas por hora del día
  - Gráfico comparativo por zona: % de decisiones de encendido incorrectas (donde hay desperdicio)
  - Conclusión: cuánto kWh se podría ahorrar si se implementara el modelo

- [ ] Los datos de la página deben ser **JSON estáticos** exportados desde el notebook:
  ```python
  import json
  resultados = {
      "accuracy": round(accuracy_score(y_test, y_pred), 4),
      "feature_importance": dict(zip(features, model.feature_importances_.tolist())),
      "ahorro_estimado_kwh": ...,
  }
  with open('resultados_modelo.json', 'w') as f:
      json.dump(resultados, f)
  ```

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 3 Semana 2

- **El modelo no necesita ser perfecto; necesita ser interpretable.** Un Random Forest con buenas métricas y una explicación clara de qué features importan más es más valioso para el proyecto que un modelo complejo mal explicado.
- **Si el dataset de 1M filas es muy lento para entrenar**, usar una muestra estratificada del 20% (200K registros) para el entrenamiento. La capacidad de generalización no cambia significativamente.
- **La página web de resultados puede ser la más impactante de toda la presentación** si se visualiza bien. Invertir tiempo en las gráficas de importancia de features y ahorro potencial.
- **Coordinarse con el Integrante 2** para que la página `modelo_ml.html` tenga el mismo estilo y navegación que el resto del sistema web.

---

### Integrante 4 — Informe Final + Presentación

**Rol:** Completar el informe técnico, preparar la presentación y consolidar el repositorio final.

---

#### Días 8–10: Completar el Informe Técnico

- [ ] **Sección 4 — ETL y Procesamiento:**
  - Descripción del pipeline SSIS con capturas de Visual Studio
  - Flujos implementados y transformaciones aplicadas
  - Validación de integridad: conteos OLTP vs DW
- [ ] **Sección 5 — Análisis Exploratorio:**
  - Insertar las gráficas generadas por el Integrante 3
  - Descripción de los patrones encontrados: horas pico, zonas críticas, correlaciones
  - Tabla de estadísticas descriptivas clave
- [ ] **Sección 6 — Modelo de Machine Learning:**
  - Descripción del problema ML, features y variable target
  - Resultados del modelo: métricas de evaluación
  - Importancia de variables y su interpretación para la política de iluminación

---

#### Días 11–12: Sección de Conclusiones y Recomendaciones

- [ ] **Sección 7 — Conclusiones:**
  - ¿Qué zonas de Bogotá tienen mayor desperdicio energético?
  - ¿Qué hora del día concentra mayor ineficiencia?
  - ¿Cuánto kWh podría ahorrarse con el modelo ML?
  - Limitaciones del proyecto (datos simulados, escala académica)
- [ ] **Sección 8 — Recomendaciones de Política Urbana:**
  - 3–5 propuestas concretas para el Distrito de Bogotá basadas en el análisis
  - Alineación de cada propuesta con el ODS correspondiente (ODS 7, 11 o 13)
  - Trabajo futuro: qué se necesitaría para escalar el sistema a producción real

---

#### Días 13–14: Presentación y Cierre del Repositorio

- [ ] **Preparar presentación (10–12 diapositivas):**
  1. Portada: nombre del proyecto, Bogotá, equipo, ODS
  2. Contexto del problema: alumbrado público de Bogotá, gasto, ineficiencia
  3. Solución propuesta: arquitectura del sistema
  4. Modelos de BD: ERD y Star Schema (capturas)
  5. Dataset: fuentes y generación (tabla de campos)
  6. ETL: pipeline SSIS (captura del flujo)
  7. Power BI: capturas del dashboard (2 slides)
  8. Sistema Web: capturas de las páginas
  9. Modelo ML: métricas y gráfica de importancia de features
  10. Maqueta: foto/demo del sensor
  11. Conclusiones y ahorro estimado
  12. Recomendaciones y trabajo futuro

- [ ] **Consolidar repositorio Git:**
  - Verificar que todos los archivos están en las carpetas correctas
  - Revisar que el README tiene: descripción, instrucciones de instalación, descripción de cada carpeta
  - Hacer el commit final etiquetado como `v1.0-entrega-final`

---

#### ⚠️ Consideraciones y Recomendaciones — Int. 4 Semana 2

- **Recopilar capturas de pantalla y gráficas del equipo desde el día 8**, no esperar al día 13 para pedirlas.
- **El informe debe tener entre 25 y 40 páginas** para un proyecto de esta envergadura. No rellenar; priorizar profundidad técnica sobre extensión.
- **La presentación debe poder sostenerse en 15–20 minutos.** Practicar una vez antes de la entrega para ajustar el tiempo.
- **El repositorio es un entregable evaluado.** Un repo con commits descriptivos, carpetas ordenadas y README completo proyecta profesionalismo.

---

## 5. Entregables por Semana

### Semana 1 — Entregables para clase de Power BI

| Entregable | Responsable | Formato |
|---|---|---|
| Script DDL modelo OLTP completo | Int. 1 | `.sql` |
| Script DDL modelo multidimensional (Star Schema) | Int. 1 | `.sql` |
| Diagramas ERD y Star Schema | Int. 1 | `.png` / `.drawio` |
| Pipeline SSIS — Flujos de dimensiones | Int. 1 + Int. 3 | `.dtsx` |
| Pipeline SSIS — Flujo de hechos | Int. 1 | `.dtsx` |
| BDs SQL Server con 1M registros cargados | Int. 1 | SQL Server |
| Dataset CSV ~1M registros | Int. 2 | `.csv` |
| Script Python de generación de datos | Int. 2 | `.py` |
| Lista de materiales para maqueta | Int. 3 | `.md` / `.xlsx` |
| Informe técnico secciones 1–3 | Int. 4 | `.docx` |
| README del repositorio actualizado | Int. 4 | `.md` |

### Semana 2 — Entregables finales

| Entregable | Responsable | Formato |
|---|---|---|
| Dashboard Power BI completo (3+ páginas) | Int. 1 | `.pbix` + PDF |
| Sistema web con 3 secciones | Int. 2 | `.html` + `.css` + `.js` |
| Maqueta física del sensor funcional | Int. 2 | Hardware + foto/video |
| Modelo ML entrenado + resultados | Int. 3 | `.pkl` + `.ipynb` |
| Página web de resultados del modelo ML | Int. 3 | `.html` |
| Informe técnico completo (secciones 1–8) | Int. 4 | `.pdf` |
| Presentación final (10–12 slides) | Int. 4 | `.pptx` |
| Repositorio Git consolidado | Int. 4 | GitHub/GitLab |

---

## 6. Stack Tecnológico

| Capa | Tecnología | Versión / Notas |
|---|---|---|
| Base de datos OLTP | SQL Server | 2019 o 2022 |
| Data Warehouse | SQL Server | Misma instancia, BD separada |
| ETL | Visual Studio + SSIS | SQL Server Data Tools (SSDT) |
| Generación de datos | Python + Pandas + NumPy | Python 3.10+ |
| Análisis / ML | Jupyter + Scikit-learn | Pandas, Matplotlib, Seaborn |
| Visualización BI | Power BI Desktop | Versión gratuita suficiente |
| Sistema Web | HTML + CSS + JS | Sin frameworks pesados |
| Gráficos web | Chart.js | CDN |
| Mapa web | Leaflet.js | CDN |
| Maqueta física | Arduino Uno / Nano | Sensor LDR |
| Control de versiones | Git + GitHub/GitLab | — |
| Documentación | Word + PowerPoint | — |

---

## 7. Estructura del Repositorio

```
proyecto-iluminacion-bogota/
│
├── /datos
│   ├── dataset_1M_registros.csv
│   ├── dataset_1M_registros_muestra.json   ← primeros 1000 registros
│   ├── generar_dataset.py                  ← script de generación
│   └── /fuentes_publicas
│       ├── bogota_luminarias.csv           ← dataset descargado
│       └── README_fuentes.md               ← descripción de cada fuente
│
├── /base_datos
│   ├── modelo_transaccional_DDL.sql
│   ├── modelo_dimensional_DDL.sql
│   ├── stored_procedures_carga.sql
│   └── /diagramas
│       ├── ERD_OLTP.png
│       └── StarSchema_DW.png
│
├── /etl
│   ├── /pipeline_ssis
│   │   ├── CargarDimTiempo.dtsx
│   │   ├── CargarDimZona.dtsx
│   │   ├── CargarDimSensor.dtsx
│   │   ├── CargarDimClima.dtsx
│   │   ├── CargarDimPolitica.dtsx
│   │   └── CargarFactConsumo.dtsx
│   └── validacion_cruzada.sql
│
├── /analisis
│   ├── EDA_iluminacion_bogota.ipynb
│   ├── modelo_ml_random_forest.ipynb
│   ├── modelo_iluminacion.pkl
│   └── resultados_modelo.json
│
├── /powerbi
│   ├── dashboard_iluminacion.pbix
│   └── /reportes_pdf
│       └── dashboard_exportado.pdf
│
├── /web
│   ├── index.html
│   ├── dashboard.html
│   ├── recomendaciones.html
│   ├── modelo_ml.html
│   ├── /css
│   │   └── styles.css
│   └── /js
│       ├── charts.js
│       ├── map.js
│       └── ml_results.js
│
├── /maqueta
│   ├── sketch_arduino.ino
│   ├── diagrama_circuito.png
│   └── lista_materiales.md
│
├── /informe
│   └── informe_tecnico_final.pdf
│
├── /presentacion
│   └── presentacion_final.pptx
│
└── README.md
```

---

*Plan de Desarrollo — Sistema de Monitorización de Iluminación Inteligente — Bogotá D.C.*
*Ciudades Inteligentes: Análisis de Datos para la Sostenibilidad Urbana · ODS 7 · ODS 11 · ODS 13*
