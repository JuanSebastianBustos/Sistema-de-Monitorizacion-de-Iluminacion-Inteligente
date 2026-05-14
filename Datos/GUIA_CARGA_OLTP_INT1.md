# Guía de Carga OLTP — Integrante 1
## Sistema de Monitorización de Iluminación Inteligente — Bogotá D.C.

> **Preparada por:** Integrante 2 — Data Engineer  
> **Estado:** OLTP probado y funcional con 1.000.000 de registros cargados  
> **Motor:** SQL Server 2019 / 2022  
> **Base de datos:** `IluminacionBogota_OLTP`

---

## Archivos entregados

| Archivo | Destino en OLTP | Filas |
|---|---|---|
| `carga_zona.csv` | `maestro.Zona` | 20 |
| `carga_sensor.csv` | `maestro.Sensor` | 500 |
| `carga_luminaria.csv` | `maestro.Luminaria` | 500 |
| `carga_politica.csv` | `control.PoliticaIluminacion` | 20 |
| `lecturas_ambiente.csv` | `operativo.LecturaAmbiente` | 1.000.000 |
| `consumos_energeticos.csv` | `operativo.ConsumoEnergetico` | 1.000.000 |
| `generar_dataset.py` | — (script fuente, entregable técnico) | — |
| `lecturas_muestra_1000.json` | — (pruebas rápidas) | 1.000 |

---

## Prerequisitos

1. Tener ejecutado el script `modelo_transaccional_DDL.sql` completo — crea la BD, los esquemas y las tablas de catálogo con datos semilla.
2. Guardar todos los CSV en una carpeta local accesible desde SQL Server, por ejemplo `C:\Proyecto\Datos\`.
3. Tener SSMS abierto y conectado a la instancia local con la BD `IluminacionBogota_OLTP` seleccionada.

---

## Notas importantes antes de empezar

- El `BULK INSERT` en SQL Server **no acepta lista de columnas entre paréntesis** como el `INSERT` normal. Se resuelve usando una **tabla staging** intermedia.
- Las tablas con `IDENTITY` (`Sensor`, `Luminaria`, `PoliticaIluminacion`) requieren `SET IDENTITY_INSERT ON` para respetar los IDs del CSV, ya que otras tablas los referencian como FK.
- El campo `anomalia_flag` debe recibirse como `TINYINT` en el staging (no `BIT`) y convertirse al insertar en el OLTP.
- El separador es **coma (`,`)**, encoding **UTF-8**, terminador de línea **`\n`** (Unix).
- Las fechas vienen en formato `YYYY-MM-DD` y los timestamps en `YYYY-MM-DD HH:MM:SS`.

---

## Paso 0 — Verificar que el DDL corrió bien

```sql
USE IluminacionBogota_OLTP;
GO

SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name IN ('catalogo','maestro','operativo','control')
ORDER BY s.name, t.name;
```

Debes ver **14 tablas**. Si no las ves todas, vuelve a ejecutar el DDL.

---

## Paso 1 — Crear esquema staging

```sql
USE IluminacionBogota_OLTP;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging AUTHORIZATION dbo');
GO
```

---

## Paso 2 — Cargar maestro.Zona (20 filas)

```sql
DROP TABLE IF EXISTS staging.ZonaPlana;
CREATE TABLE staging.ZonaPlana (
    nombre_zona   VARCHAR(100),
    localidad     VARCHAR(100),
    tipo_zona_id  TINYINT,
    latitud       DECIMAL(9,6),
    longitud      DECIMAL(9,6),
    poblacion     INT,
    area_km2      DECIMAL(8,2)
);
GO

BULK INSERT staging.ZonaPlana
FROM 'C:\Proyecto\Datos\carga_zona.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');
GO

INSERT INTO maestro.Zona (nombre_zona, localidad, tipo_zona_id, latitud, longitud, poblacion, area_km2)
SELECT nombre_zona, localidad, tipo_zona_id, latitud, longitud, poblacion, area_km2
FROM staging.ZonaPlana;
GO

SELECT COUNT(*) AS zonas_cargadas FROM maestro.Zona; -- esperado: 20
```

---

## Paso 3 — Cargar maestro.Sensor (500 filas)

```sql
DROP TABLE IF EXISTS staging.SensorPlana;
CREATE TABLE staging.SensorPlana (
    sensor_id                  INT,
    zona_id                    INT,
    tipo_sensor_id             INT,
    estado_sensor_id           TINYINT,
    codigo_externo             VARCHAR(50),
    latitud                    DECIMAL(9,6),
    longitud                   DECIMAL(9,6),
    fecha_instalacion          VARCHAR(20),
    fecha_ultimo_mantenimiento VARCHAR(20),
    observaciones              VARCHAR(255)
);
GO

BULK INSERT staging.SensorPlana
FROM 'C:\Proyecto\Datos\carga_sensor.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');
GO

SET IDENTITY_INSERT maestro.Sensor ON;
INSERT INTO maestro.Sensor (sensor_id, zona_id, tipo_sensor_id, estado_sensor_id,
    codigo_externo, latitud, longitud, fecha_instalacion,
    fecha_ultimo_mantenimiento, observaciones)
SELECT sensor_id, zona_id, tipo_sensor_id, estado_sensor_id,
    codigo_externo, latitud, longitud,
    CAST(fecha_instalacion AS DATE),
    NULLIF(CAST(NULLIF(fecha_ultimo_mantenimiento,'') AS DATE), NULL),
    NULLIF(observaciones,'')
FROM staging.SensorPlana;
SET IDENTITY_INSERT maestro.Sensor OFF;
GO

SELECT COUNT(*) AS sensores_cargados FROM maestro.Sensor; -- esperado: 500
```

---

## Paso 4 — Cargar maestro.Luminaria (500 filas)

```sql
DROP TABLE IF EXISTS staging.LuminariaPlana;
CREATE TABLE staging.LuminariaPlana (
    luminaria_id               INT,
    sensor_id                  INT,
    zona_id                    INT,
    tipo_lampara_id            INT,
    estado_luminaria_id        TINYINT,
    potencia_w                 DECIMAL(6,2),
    altura_poste_m             DECIMAL(5,2),
    codigo_poste               VARCHAR(50),
    latitud                    DECIMAL(9,6),
    longitud                   DECIMAL(9,6),
    fecha_instalacion          VARCHAR(20),
    horas_operacion_acumuladas INT
);
GO

BULK INSERT staging.LuminariaPlana
FROM 'C:\Proyecto\Datos\carga_luminaria.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');
GO

SET IDENTITY_INSERT maestro.Luminaria ON;
INSERT INTO maestro.Luminaria (luminaria_id, sensor_id, zona_id, tipo_lampara_id,
    estado_luminaria_id, potencia_w, altura_poste_m, codigo_poste,
    latitud, longitud, fecha_instalacion, horas_operacion_acumuladas)
SELECT luminaria_id, sensor_id, zona_id, tipo_lampara_id,
    estado_luminaria_id, potencia_w, altura_poste_m, codigo_poste,
    latitud, longitud,
    CAST(fecha_instalacion AS DATE),
    horas_operacion_acumuladas
FROM staging.LuminariaPlana;
SET IDENTITY_INSERT maestro.Luminaria OFF;
GO

SELECT COUNT(*) AS luminarias_cargadas FROM maestro.Luminaria; -- esperado: 500
```

---

## Paso 5 — Cargar control.PoliticaIluminacion (20 filas)

```sql
DROP TABLE IF EXISTS staging.PoliticaPlana;
CREATE TABLE staging.PoliticaPlana (
    politica_id                  INT,
    zona_id                      INT,
    nombre_politica              VARCHAR(100),
    hora_encendido               VARCHAR(10),
    hora_apagado                 VARCHAR(10),
    nivel_lux_umbral             DECIMAL(6,2),
    nivel_potencia_reduccion_pct TINYINT,
    aplica_fines_semana          BIT,
    aplica_festivos              BIT,
    fecha_vigencia_desde         VARCHAR(20),
    fecha_vigencia_hasta         VARCHAR(20),
    activa                       BIT,
    descripcion                  VARCHAR(255)
);
GO

BULK INSERT staging.PoliticaPlana
FROM 'C:\Proyecto\Datos\carga_politica.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');
GO

SET IDENTITY_INSERT control.PoliticaIluminacion ON;
INSERT INTO control.PoliticaIluminacion (politica_id, zona_id, nombre_politica,
    hora_encendido, hora_apagado, nivel_lux_umbral, nivel_potencia_reduccion_pct,
    aplica_fines_semana, aplica_festivos, fecha_vigencia_desde,
    fecha_vigencia_hasta, activa, descripcion)
SELECT politica_id, zona_id, nombre_politica,
    CAST(hora_encendido AS TIME(0)),
    CAST(hora_apagado   AS TIME(0)),
    nivel_lux_umbral, nivel_potencia_reduccion_pct,
    aplica_fines_semana, aplica_festivos,
    CAST(fecha_vigencia_desde AS DATE),
    NULLIF(CAST(NULLIF(fecha_vigencia_hasta,'') AS DATE), NULL),
    activa,
    NULLIF(descripcion,'')
FROM staging.PoliticaPlana;
SET IDENTITY_INSERT control.PoliticaIluminacion OFF;
GO

SELECT COUNT(*) AS politicas_cargadas FROM control.PoliticaIluminacion; -- esperado: 20
```

---

## Paso 6 — Cargar operativo.LecturaAmbiente (1.000.000 filas)

> Este paso puede tardar entre 2 y 5 minutos. No cerrar SSMS mientras corre.

```sql
DROP TABLE IF EXISTS staging.LecturaAmbientePlana;
CREATE TABLE staging.LecturaAmbientePlana (
    sensor_id              INT,
    condicion_clima_id     TINYINT,
    timestamp_lectura      VARCHAR(20),
    nivel_lux              DECIMAL(8,2),
    temperatura_c          DECIMAL(5,2),
    cobertura_nubosa_pct   TINYINT,
    radiacion_solar_wm2    DECIMAL(7,2),
    anomalia_flag          TINYINT    -- TINYINT, no BIT (BULK INSERT no acepta BIT directo)
);
GO

BULK INSERT staging.LecturaAmbientePlana
FROM 'C:\Proyecto\Datos\lecturas_ambiente.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');
GO

SELECT COUNT(*) AS filas_staging FROM staging.LecturaAmbientePlana; -- esperado: 1.000.000

INSERT INTO operativo.LecturaAmbiente
    (sensor_id, condicion_clima_id, timestamp_lectura,
     nivel_lux, temperatura_c, cobertura_nubosa_pct,
     radiacion_solar_wm2, anomalia_flag)
SELECT
    sensor_id,
    condicion_clima_id,
    CAST(timestamp_lectura AS DATETIME2(0)),
    nivel_lux,
    temperatura_c,
    cobertura_nubosa_pct,
    radiacion_solar_wm2,
    CAST(anomalia_flag AS BIT)
FROM staging.LecturaAmbientePlana;
GO

SELECT COUNT(*) AS lecturas_cargadas FROM operativo.LecturaAmbiente; -- esperado: 1.000.000
```

---

## Paso 7 — Cargar operativo.ConsumoEnergetico (1.000.000 filas)

> El CSV `consumos_energeticos.csv` está derivado de `lecturas_ambiente.csv`.
> El campo `lectura_id` corresponde a la posición 1-based de cada fila en `lecturas_ambiente.csv`,
> que coincide con el `IDENTITY` generado en el paso anterior si se cargó en orden.

```sql
DROP TABLE IF EXISTS staging.ConsumoPlana;
CREATE TABLE staging.ConsumoPlana (
    luminaria_id      INT,
    lectura_id        BIGINT,
    fecha_hora        VARCHAR(20),
    kwh_consumido     DECIMAL(8,4),
    estado_encendido  TINYINT,
    potencia_activa_w DECIMAL(6,2),
    tarifa_cop_kwh    DECIMAL(10,2)
);
GO

BULK INSERT staging.ConsumoPlana
FROM 'C:\Proyecto\Datos\consumos_energeticos.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '\n', CODEPAGE = '65001');
GO

SELECT COUNT(*) AS filas_staging FROM staging.ConsumoPlana; -- esperado: 1.000.000

INSERT INTO operativo.ConsumoEnergetico
    (luminaria_id, lectura_id, fecha_hora, kwh_consumido,
     estado_encendido, potencia_activa_w, tarifa_cop_kwh)
SELECT
    luminaria_id,
    lectura_id,
    CAST(fecha_hora AS DATETIME2(0)),
    kwh_consumido,
    CAST(estado_encendido AS BIT),
    potencia_activa_w,
    tarifa_cop_kwh
FROM staging.ConsumoPlana;
GO

SELECT COUNT(*) AS consumos_cargados FROM operativo.ConsumoEnergetico; -- esperado: 1.000.000
```

---

## Paso 8 — Poblar operativo.EventoAnomalia

> Esta tabla se deriva de `LecturaAmbiente` filtrando los registros con `anomalia_flag = 1` (~20.000 filas).
> Se asigna un `tipo_anomalia_id` aleatorio entre los 6 definidos en el catálogo.

```sql
INSERT INTO operativo.EventoAnomalia
    (luminaria_id, lectura_id, tipo_anomalia_id, fecha_hora, descripcion, resuelto)
SELECT
    c.luminaria_id,
    l.lectura_id,
    -- Distribuir aleatoriamente entre los 6 tipos de anomalía del catálogo
    CAST((ABS(CHECKSUM(NEWID())) % 6) + 1 AS TINYINT),
    l.timestamp_lectura,
    'Anomalía detectada automáticamente por umbral de sensor',
    CAST((ABS(CHECKSUM(NEWID())) % 2) AS BIT)   -- 50% resueltas
FROM operativo.LecturaAmbiente l
JOIN operativo.ConsumoEnergetico c ON l.lectura_id = c.lectura_id
WHERE l.anomalia_flag = 1;
GO

SELECT COUNT(*) AS anomalias_cargadas FROM operativo.EventoAnomalia; -- esperado: ~20.000
```

---

## Paso 9 — Verificación final completa

```sql
SELECT 'catalogo.CondicionClima'         AS Tabla, COUNT(*) AS Filas FROM catalogo.CondicionClima
UNION ALL SELECT 'catalogo.TipoZona',              COUNT(*) FROM catalogo.TipoZona
UNION ALL SELECT 'catalogo.TipoSensor',            COUNT(*) FROM catalogo.TipoSensor
UNION ALL SELECT 'catalogo.TipoLampara',           COUNT(*) FROM catalogo.TipoLampara
UNION ALL SELECT 'catalogo.TipoAnomalia',          COUNT(*) FROM catalogo.TipoAnomalia
UNION ALL SELECT 'catalogo.EstadoSensor',          COUNT(*) FROM catalogo.EstadoSensor
UNION ALL SELECT 'catalogo.EstadoLuminaria',       COUNT(*) FROM catalogo.EstadoLuminaria
UNION ALL SELECT 'maestro.Zona',                   COUNT(*) FROM maestro.Zona
UNION ALL SELECT 'maestro.Sensor',                 COUNT(*) FROM maestro.Sensor
UNION ALL SELECT 'maestro.Luminaria',              COUNT(*) FROM maestro.Luminaria
UNION ALL SELECT 'control.PoliticaIluminacion',    COUNT(*) FROM control.PoliticaIluminacion
UNION ALL SELECT 'operativo.LecturaAmbiente',      COUNT(*) FROM operativo.LecturaAmbiente
UNION ALL SELECT 'operativo.ConsumoEnergetico',    COUNT(*) FROM operativo.ConsumoEnergetico
UNION ALL SELECT 'operativo.EventoAnomalia',       COUNT(*) FROM operativo.EventoAnomalia;
```

### Resultado esperado

| Tabla | Filas esperadas |
|---|---|
| `catalogo.CondicionClima` | 4 |
| `catalogo.TipoZona` | 5 |
| `catalogo.TipoSensor` | 4 |
| `catalogo.TipoLampara` | 5 |
| `catalogo.TipoAnomalia` | 6 |
| `catalogo.EstadoSensor` | 4 |
| `catalogo.EstadoLuminaria` | 4 |
| `maestro.Zona` | 20 |
| `maestro.Sensor` | 500 |
| `maestro.Luminaria` | 500 |
| `control.PoliticaIluminacion` | 20 |
| `operativo.LecturaAmbiente` | **1.000.000** |
| `operativo.ConsumoEnergetico` | **1.000.000** |
| `operativo.EventoAnomalia` | ~20.000 |

---

## Resumen de IDs de catálogo usados en el dataset

Estos IDs ya están sembrados por el DDL. El dataset los referencia directamente.

**CondicionClima**
| ID | Nombre |
|---|---|
| 1 | Soleado |
| 2 | Nublado |
| 3 | Lluvioso |
| 4 | Despejado Nocturno |

**TipoZona**
| ID | Nombre |
|---|---|
| 1 | Residencial |
| 2 | Comercial |
| 3 | Industrial |
| 4 | Mixta |
| 5 | Rural |

**TipoSensor**
| ID | Modelo |
|---|---|
| 1 | BH1750 |
| 2 | TSL2561 |
| 3 | GL5528 |
| 4 | VEML7700 |

**TipoLampara**
| ID | Nombre |
|---|---|
| 1 | LED |
| 2 | Sodio Alta Presión |
| 3 | Haluro Metálico |
| 4 | Mercurio |
| 5 | Inducción |

**EstadoSensor / EstadoLuminaria**
| ID | Nombre |
|---|---|
| 1 | Activo / Operativa |
| 2 | Inactivo / Averiada |
| 3 | En mantenimiento / En reemplazo |
| 4 | Dado de baja / Dada de baja |

---

## Troubleshooting — Errores frecuentes

| Error | Causa | Solución |
|---|---|---|
| `Column name 'zona_id' does not exist` | BULK INSERT intenta llenar columna IDENTITY | Usar tabla staging intermedia (ver pasos anteriores) |
| `type mismatch ... anomalia_flag` | BIT no acepta 0/1 directo en BULK INSERT | Declarar como TINYINT en staging y hacer CAST al insertar |
| `0 rows affected` sin error | Terminador de línea incorrecto | Cambiar `'\n'` por `'0x0a'` o viceversa |
| `Cannot bulk load — path not found` | La ruta del CSV no es accesible desde el servidor SQL | Usar ruta absoluta local; si SQL Server está en otro equipo, mover el CSV al servidor |
| `Incorrect syntax near '('` | Lista de columnas en BULK INSERT | BULK INSERT no acepta columnas entre paréntesis; usar staging |

---

*Guía generada por Integrante 2 — Data Engineer*  
*Proyecto: Ciudades Inteligentes · ODS 7 · ODS 11 · ODS 13*
