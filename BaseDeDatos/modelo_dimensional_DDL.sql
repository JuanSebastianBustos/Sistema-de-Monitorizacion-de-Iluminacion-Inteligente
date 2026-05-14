-- ============================================================
--  SCRIPT DDL — MODELO MULTIDIMENSIONAL (DATA WAREHOUSE)
--  Sistema de Monitorización de Iluminación Inteligente
--  Bogotá D.C. · Ciudades Inteligentes
-- ============================================================
--  Motor        : SQL Server 2019 / 2022
--  Base de datos: IluminacionBogota_DW
--  Esquema      : Star Schema (Kimball)
--  Fuente       : IluminacionBogota_OLTP vía pipeline SSIS
--
--  Orden de creación:
--    1. Base de datos
--    2. Dimensiones (sin dependencias entre sí)
--    3. Tabla de hechos (depende de todas las dimensiones)
--    4. Índices
-- ============================================================


-- ============================================================
-- 0. CREACIÓN DE LA BASE DE DATOS
-- ============================================================

USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'IluminacionBogota_DW')
BEGIN
    ALTER DATABASE IluminacionBogota_DW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE IluminacionBogota_DW;
END
GO

CREATE DATABASE IluminacionBogota_DW
    COLLATE Modern_Spanish_CI_AS;
GO

USE IluminacionBogota_DW;
GO


-- ============================================================
-- 1. DIMENSIONES
--    Se crean antes que la tabla de hechos.
--    No tienen dependencias entre sí — se pueden crear en
--    cualquier orden dentro de este bloque.
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 DimTiempo
--     Descompone cada instante temporal en todos sus atributos
--     analíticos. Generada programáticamente por el Flujo 1
--     del SSIS para el rango 2023-01-01 00:00 a 2024-12-31 23:00.
--     Granularidad: una fila por hora por día → 17.520 filas.
-- ------------------------------------------------------------
CREATE TABLE DimTiempo (
    tiempo_id             INT          NOT NULL,
    -- Formato YYYYMMDDHH (ej: 2024010623). Facilita joins y debugging.
    fecha                 DATE         NOT NULL,
    anio                  SMALLINT     NOT NULL,
    semestre              TINYINT      NOT NULL,
    trimestre             TINYINT      NOT NULL,
    mes                   TINYINT      NOT NULL,
    nombre_mes            VARCHAR(20)  NOT NULL,
    semana_iso            TINYINT      NOT NULL,
    dia_mes               TINYINT      NOT NULL,
    dia_semana            TINYINT      NOT NULL,
    -- 1 = Lunes ... 7 = Domingo
    nombre_dia            VARCHAR(20)  NOT NULL,
    hora                  TINYINT      NOT NULL,
    -- 0 a 23
    es_horario_nocturno   BIT          NOT NULL,
    -- 1 si hora BETWEEN 18 AND 23 OR hora BETWEEN 0 AND 5
    es_fin_semana         BIT          NOT NULL,
    es_festivo            BIT          NOT NULL,
    -- Festivos Colombia según Ley 51/1983 y modificaciones
    estacion_climatica    VARCHAR(20)  NOT NULL,
    -- 'Época seca' | 'Época lluviosa' (régimen bimodal Bogotá)

    CONSTRAINT PK_DimTiempo PRIMARY KEY (tiempo_id)
);
GO

-- ------------------------------------------------------------
-- 1.2 DimZona
--     Catálogo de las 20 localidades de Bogotá D.C.
--     Eje geográfico del análisis. Habilita mapas de calor
--     en Power BI y métricas normalizadas por habitante / km².
--     Cargada desde maestro.Zona + catalogo.TipoZona (SSIS Flujo 2).
-- ------------------------------------------------------------
CREATE TABLE DimZona (
    zona_id    INT           NOT NULL,
    nombre_zona VARCHAR(100) NOT NULL,
    localidad   VARCHAR(100) NOT NULL,
    tipo_zona   VARCHAR(60)  NOT NULL,
    -- Desnormalizado desde catalogo.TipoZona del OLTP
    latitud     DECIMAL(9,6) NOT NULL,
    longitud    DECIMAL(9,6) NOT NULL,
    poblacion   INT          NOT NULL,
    area_km2    DECIMAL(8,2) NOT NULL,
    activa      BIT          NOT NULL,

    CONSTRAINT PK_DimZona PRIMARY KEY (zona_id)
);
GO

-- ------------------------------------------------------------
-- 1.3 DimSensor
--     Registro de cada sensor físico instalado.
--     Permite analizar calidad de datos por modelo/fabricante
--     y es fuente de features para el modelo ML del Integrante 3.
--     Cargada desde maestro.Sensor + catálogos (SSIS Flujo 3).
-- ------------------------------------------------------------
CREATE TABLE DimSensor (
    sensor_id          INT          NOT NULL,
    zona_id            INT          NOT NULL,
    tipo_sensor        VARCHAR(80)  NOT NULL,
    -- Desnormalizado desde catalogo.TipoSensor
    modelo             VARCHAR(100) NOT NULL,
    fabricante         VARCHAR(100) NOT NULL,
    precision_pct      DECIMAL(5,2)     NULL,
    fecha_instalacion  DATE         NOT NULL,
    estado_sensor      VARCHAR(60)  NOT NULL,
    -- Desnormalizado desde catalogo.EstadoSensor

    CONSTRAINT PK_DimSensor PRIMARY KEY (sensor_id)
);
GO

-- ------------------------------------------------------------
-- 1.4 DimLuminaria
--     Inventario analítico de cada punto de luz.
--     Dimensión clave para comparar tecnologías (LED vs Sodio),
--     estimar fin de vida útil y calcular ROI de modernización.
--     Cargada desde maestro.Luminaria + catálogos (SSIS Flujo 3b).
-- ------------------------------------------------------------
CREATE TABLE DimLuminaria (
    luminaria_id         INT          NOT NULL,
    zona_id              INT          NOT NULL,
    tipo_lampara         VARCHAR(80)  NOT NULL,
    -- Desnormalizado desde catalogo.TipoLampara
    eficiencia_lm_w      DECIMAL(6,2)     NULL,
    vida_util_horas      INT              NULL,
    potencia_nominal_w   DECIMAL(6,2) NOT NULL,
    altura_poste_m       DECIMAL(5,2)     NULL,
    fecha_instalacion    DATE         NOT NULL,
    estado_luminaria     VARCHAR(60)  NOT NULL,
    -- Desnormalizado desde catalogo.EstadoLuminaria

    CONSTRAINT PK_DimLuminaria PRIMARY KEY (luminaria_id)
);
GO

-- ------------------------------------------------------------
-- 1.5 DimClima
--     Perfiles de condición climática observados en el dataset.
--     Dimensión de combinaciones únicas (SELECT DISTINCT del OLTP).
--     Incluye valores exactos para correlación avanzada y
--     rangos categóricos para segmentadores en Power BI.
--     Cargada desde operativo.LecturaAmbiente (SSIS Flujo 4).
-- ------------------------------------------------------------
CREATE TABLE DimClima (
    clima_id               INT          NOT NULL  IDENTITY(1,1),
    condicion_clima        VARCHAR(60)  NOT NULL,
    -- Desnormalizado desde catalogo.CondicionClima
    rango_cobertura_nubosa VARCHAR(40)  NOT NULL,
    -- 'Despejado (0-25%)' | 'Parcialmente nublado (26-50%)'
    -- 'Muy nublado (51-75%)' | 'Cubierto (76-100%)'
    rango_radiacion_solar  VARCHAR(40)  NOT NULL,
    -- 'Nula (noche)' | 'Baja (<200 W/m2)'
    -- 'Media (200-500 W/m2)' | 'Alta (>500 W/m2)'
    rango_temperatura      VARCHAR(40)  NOT NULL,
    -- 'Fría (<10°C)' | 'Fresca (10-14°C)' | 'Templada (>14°C)'
    cobertura_nubosa_pct   TINYINT      NOT NULL,
    radiacion_solar_wm2    DECIMAL(7,2) NOT NULL,
    temperatura_c          DECIMAL(5,2) NOT NULL,

    CONSTRAINT PK_DimClima PRIMARY KEY (clima_id)
);
GO

-- ------------------------------------------------------------
-- 1.6 DimPolitica
--     Políticas de iluminación activas por zona.
--     Cierra el ciclo analítico: permite comparar el comportamiento
--     real del sistema contra las directrices municipales.
--     Cargada desde control.PoliticaIluminacion (SSIS Flujo 5).
-- ------------------------------------------------------------
CREATE TABLE DimPolitica (
    politica_id                  INT          NOT NULL,
    zona_id                      INT          NOT NULL,
    nombre_politica              VARCHAR(100) NOT NULL,
    hora_encendido               TIME(0)      NOT NULL,
    hora_apagado                 TIME(0)      NOT NULL,
    nivel_lux_umbral             DECIMAL(6,2) NOT NULL,
    nivel_potencia_reduccion_pct TINYINT      NOT NULL,
    -- 0-100: porcentaje de potencia en horario de baja demanda
    aplica_fines_semana          BIT          NOT NULL,
    aplica_festivos              BIT          NOT NULL,
    fecha_vigencia_desde         DATE         NOT NULL,
    fecha_vigencia_hasta         DATE             NULL,

    CONSTRAINT PK_DimPolitica PRIMARY KEY (politica_id)
);
GO


-- ============================================================
-- 2. TABLA DE HECHOS — FactConsumoIluminacion
--    Corazón del Data Warehouse. ~1 millón de filas.
--    Granularidad: una fila por sensor por período de medición.
--    Cargada desde el JOIN principal del SSIS (Flujo 6).
-- ============================================================

CREATE TABLE FactConsumoIluminacion (
    hecho_id                BIGINT        NOT NULL  IDENTITY(1,1),

    -- ── Claves foráneas dimensionales ──────────────────────
    tiempo_id               INT           NOT NULL,
    zona_id                 INT           NOT NULL,
    sensor_id               INT           NOT NULL,
    luminaria_id            INT           NOT NULL,
    clima_id                INT           NOT NULL,
    politica_id             INT           NOT NULL,

    -- ── Métricas base ──────────────────────────────────────
    nivel_lux               DECIMAL(8,2)  NOT NULL,
    consumo_kwh             DECIMAL(8,4)  NOT NULL,
    potencia_activa_w       DECIMAL(6,2)      NULL,
    tarifa_cop_kwh          DECIMAL(10,2)     NULL,
    estado_encendido        BIT           NOT NULL,

    -- ── Métricas derivadas (calculadas en el ETL) ──────────
    costo_cop               DECIMAL(12,2)     NULL,
    -- consumo_kwh × tarifa_cop_kwh, persistido en el ETL
    -- para evitar recálculos en cada consulta DAX de Power BI.

    -- ── Métricas del modelo ML (Semana 2) ──────────────────
    lux_optimo_predicho     DECIMAL(8,2)      NULL,
    -- Valor predicho por el Random Forest del Integrante 3.
    -- NULL hasta la integración del modelo en Semana 2.
    diferencia_lux          DECIMAL(8,2)      NULL,
    -- nivel_lux - lux_optimo_predicho
    -- Mide brecha entre alumbrado real y óptimo.
    ahorro_kwh_estimado     DECIMAL(8,4)      NULL,
    -- kWh que se ahorrarían ajustando al nivel óptimo.
    -- Base para proyecciones de ROI en Power BI.

    -- ── Indicador de anomalía ──────────────────────────────
    anomalia_flag           BIT           NOT NULL  DEFAULT 0,

    -- ── Restricciones ──────────────────────────────────────
    CONSTRAINT PK_FactConsumoIluminacion
        PRIMARY KEY (hecho_id),

    CONSTRAINT FK_Fact_Tiempo
        FOREIGN KEY (tiempo_id)
        REFERENCES DimTiempo (tiempo_id),

    CONSTRAINT FK_Fact_Zona
        FOREIGN KEY (zona_id)
        REFERENCES DimZona (zona_id),

    CONSTRAINT FK_Fact_Sensor
        FOREIGN KEY (sensor_id)
        REFERENCES DimSensor (sensor_id),

    CONSTRAINT FK_Fact_Luminaria
        FOREIGN KEY (luminaria_id)
        REFERENCES DimLuminaria (luminaria_id),

    CONSTRAINT FK_Fact_Clima
        FOREIGN KEY (clima_id)
        REFERENCES DimClima (clima_id),

    CONSTRAINT FK_Fact_Politica
        FOREIGN KEY (politica_id)
        REFERENCES DimPolitica (politica_id)
);
GO


-- ============================================================
-- 3. ÍNDICES
--    Optimizan los patrones de acceso más frecuentes:
--    filtros temporales, por zona, por tecnología de lámpara
--    y los lookups del SSIS durante la carga del Flujo 6.
-- ============================================================

-- ── Tabla de hechos ─────────────────────────────────────────
-- Las FK son los campos más consultados en Power BI (GROUP BY,
-- FILTER) y en los lookups del ETL. Un índice por FK es el
-- estándar en cualquier Star Schema de Kimball.

CREATE NONCLUSTERED INDEX IX_Fact_TiempoId
    ON FactConsumoIluminacion (tiempo_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_Fact_ZonaId
    ON FactConsumoIluminacion (zona_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_Fact_SensorId
    ON FactConsumoIluminacion (sensor_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_Fact_LuminariaId
    ON FactConsumoIluminacion (luminaria_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_Fact_ClimaId
    ON FactConsumoIluminacion (clima_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_Fact_PoliticaId
    ON FactConsumoIluminacion (politica_id ASC);
GO

-- Índice compuesto zona + tiempo: consulta más frecuente en
-- Power BI ("consumo de la zona X en el período Y").
CREATE NONCLUSTERED INDEX IX_Fact_Zona_Tiempo
    ON FactConsumoIluminacion (zona_id ASC, tiempo_id ASC)
    INCLUDE (consumo_kwh, nivel_lux, costo_cop, anomalia_flag);
GO

-- Índice para filtrar anomalías: Power BI filtra por este campo
-- en el panel de mantenimiento predictivo.
CREATE NONCLUSTERED INDEX IX_Fact_AnomaliaFlag
    ON FactConsumoIluminacion (anomalia_flag ASC)
    WHERE anomalia_flag = 1;
-- Índice filtrado: solo indexa el ~2% de filas con anomalía.
GO

-- ── DimTiempo ───────────────────────────────────────────────
-- Power BI filtra por fecha, anio y hora con frecuencia.

CREATE NONCLUSTERED INDEX IX_DimTiempo_Fecha
    ON DimTiempo (fecha ASC);
GO

CREATE NONCLUSTERED INDEX IX_DimTiempo_Anio_Mes
    ON DimTiempo (anio ASC, mes ASC);
GO

-- ── DimZona ─────────────────────────────────────────────────
CREATE NONCLUSTERED INDEX IX_DimZona_TipoZona
    ON DimZona (tipo_zona ASC);
GO

-- ── DimLuminaria ────────────────────────────────────────────
-- Filtros por tecnología de lámpara son centrales en el
-- análisis de modernización LED vs tecnologías convencionales.
CREATE NONCLUSTERED INDEX IX_DimLuminaria_TipoLampara
    ON DimLuminaria (tipo_lampara ASC);
GO

-- ── DimClima ────────────────────────────────────────────────
CREATE NONCLUSTERED INDEX IX_DimClima_CondicionClima
    ON DimClima (condicion_clima ASC);
GO

-- ── DimPolitica ─────────────────────────────────────────────
CREATE NONCLUSTERED INDEX IX_DimPolitica_ZonaId
    ON DimPolitica (zona_id ASC);
GO


-- ============================================================
-- 4. VERIFICACIÓN POST-INSTALACIÓN
-- ============================================================

SELECT
    t.name       AS tabla,
    p.rows       AS filas_estimadas
FROM sys.tables    t
JOIN sys.indexes   i ON t.object_id = i.object_id AND i.index_id IN (0,1)
JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE t.is_ms_shipped = 0
ORDER BY
    CASE t.name
        WHEN 'DimTiempo'              THEN 1
        WHEN 'DimZona'                THEN 2
        WHEN 'DimSensor'              THEN 3
        WHEN 'DimLuminaria'           THEN 4
        WHEN 'DimClima'               THEN 5
        WHEN 'DimPolitica'            THEN 6
        WHEN 'FactConsumoIluminacion' THEN 7
        ELSE 8
    END;
GO

-- ============================================================
-- FIN DEL SCRIPT
-- ============================================================
-- Próximo paso: ejecutar pipeline SSIS en el orden:
--   Flujo 1  → CargarDimTiempo
--   Flujo 2  → CargarDimZona
--   Flujo 3  → CargarDimSensor
--   Flujo 3b → CargarDimLuminaria
--   Flujo 4  → CargarDimClima
--   Flujo 5  → CargarDimPolitica
--   Flujo 6  → CargarFactConsumoIluminacion  (el más crítico)
-- ============================================================
