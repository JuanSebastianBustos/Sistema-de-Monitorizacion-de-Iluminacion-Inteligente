-- ============================================================
--  SCRIPT DDL — MODELO TRANSACCIONAL OLTP
--  Sistema de Monitorización de Iluminación Inteligente
--  Bogotá D.C. · Ciudades Inteligentes
-- ============================================================
--  Motor        : SQL Server 2019 / 2022
--  Base de datos: IluminacionBogota_OLTP
--  Normalización: Tercera Forma Normal (3FN)
--  Esquemas     : catalogo · maestro · operativo · control
--
--  Orden de creación:
--    1. Base de datos y esquemas
--    2. Tablas de catálogo (sin dependencias externas)
--    3. Tablas maestras (dependen de catálogos)
--    4. Tablas operativas / transaccionales (dependen de maestras)
--    5. Índices
-- ============================================================


-- ============================================================
-- 0. CREACIÓN DE LA BASE DE DATOS
-- ============================================================

USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'IluminacionBogota_OLTP')
BEGIN
    ALTER DATABASE IluminacionBogota_OLTP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE IluminacionBogota_OLTP;
END
GO

CREATE DATABASE IluminacionBogota_OLTP
    COLLATE Modern_Spanish_CI_AS;
GO

USE IluminacionBogota_OLTP;
GO


-- ============================================================
-- 1. ESQUEMAS
-- ============================================================
-- catalogo : tablas de referencia estática (tipos, estados,
--            clasificaciones). Solo crecen por altas; nunca
--            se modifican por operación del sistema.
-- maestro  : entidades físicas y geográficas del sistema
--            (zonas, sensores, luminarias, políticas).
-- operativo: tablas transaccionales de alta frecuencia
--            (lecturas, consumos, eventos).
-- control  : auditoría y trazabilidad de operaciones.
-- ============================================================

CREATE SCHEMA catalogo AUTHORIZATION dbo;
GO
CREATE SCHEMA maestro   AUTHORIZATION dbo;
GO
CREATE SCHEMA operativo AUTHORIZATION dbo;
GO
CREATE SCHEMA control   AUTHORIZATION dbo;
GO


-- ============================================================
-- 2. TABLAS DE CATÁLOGO
--    Sin FK hacia otros esquemas. Son la base de todo.
-- ============================================================

-- ------------------------------------------------------------
-- 2.1 catalogo.TipoZona
--     Clasificación funcional de las zonas de Bogotá.
--     Ejemplos: Residencial, Comercial, Industrial, Mixta, Rural
-- ------------------------------------------------------------
CREATE TABLE catalogo.TipoZona (
    tipo_zona_id   TINYINT      NOT NULL  IDENTITY(1,1),
    nombre         VARCHAR(60)  NOT NULL,
    descripcion    VARCHAR(255)     NULL,

    CONSTRAINT PK_TipoZona PRIMARY KEY (tipo_zona_id),
    CONSTRAINT UQ_TipoZona_nombre UNIQUE (nombre)
);
GO

-- ------------------------------------------------------------
-- 2.2 catalogo.TipoSensor
--     Modelo y características técnicas de cada tipo de sensor.
--     Separa atributos del modelo de las unidades físicas.
-- ------------------------------------------------------------
CREATE TABLE catalogo.TipoSensor (
    tipo_sensor_id    INT          NOT NULL  IDENTITY(1,1),
    nombre_tipo       VARCHAR(80)  NOT NULL,
    modelo            VARCHAR(100) NOT NULL,
    fabricante        VARCHAR(100) NOT NULL,
    unidad_medida_lux VARCHAR(20)  NOT NULL  DEFAULT 'lux',
    precision_pct     DECIMAL(5,2)     NULL,
    descripcion       VARCHAR(255)     NULL,

    CONSTRAINT PK_TipoSensor PRIMARY KEY (tipo_sensor_id),
    CONSTRAINT UQ_TipoSensor_modelo UNIQUE (modelo)
);
GO

-- ------------------------------------------------------------
-- 2.3 catalogo.EstadoSensor
--     Estados operativos posibles de un sensor.
--     Ejemplos: Activo, Inactivo, En mantenimiento, Dado de baja
-- ------------------------------------------------------------
CREATE TABLE catalogo.EstadoSensor (
    estado_sensor_id TINYINT     NOT NULL  IDENTITY(1,1),
    nombre           VARCHAR(60) NOT NULL,
    descripcion      VARCHAR(255)    NULL,

    CONSTRAINT PK_EstadoSensor PRIMARY KEY (estado_sensor_id),
    CONSTRAINT UQ_EstadoSensor_nombre UNIQUE (nombre)
);
GO

-- ------------------------------------------------------------
-- 2.4 catalogo.TipoLampara
--     Tecnologías de iluminación: LED, Sodio, Haluro, etc.
--     Centraliza atributos técnicos para evitar dependencias
--     transitivas en Luminaria.
-- ------------------------------------------------------------
CREATE TABLE catalogo.TipoLampara (
    tipo_lampara_id          INT          NOT NULL  IDENTITY(1,1),
    nombre_tipo              VARCHAR(80)  NOT NULL,
    eficiencia_lm_w          DECIMAL(6,2)     NULL,
    vida_util_horas          INT              NULL,
    indice_reproduccion_color INT             NULL,
    temperatura_color_k      INT              NULL,
    descripcion              VARCHAR(255)     NULL,

    CONSTRAINT PK_TipoLampara PRIMARY KEY (tipo_lampara_id),
    CONSTRAINT UQ_TipoLampara_nombre UNIQUE (nombre_tipo)
);
GO

-- ------------------------------------------------------------
-- 2.5 catalogo.EstadoLuminaria
--     Estados operativos posibles de una luminaria.
--     Ejemplos: Operativa, Averiada, En reemplazo, Dada de baja
-- ------------------------------------------------------------
CREATE TABLE catalogo.EstadoLuminaria (
    estado_luminaria_id TINYINT     NOT NULL  IDENTITY(1,1),
    nombre              VARCHAR(60) NOT NULL,
    descripcion         VARCHAR(255)    NULL,

    CONSTRAINT PK_EstadoLuminaria PRIMARY KEY (estado_luminaria_id),
    CONSTRAINT UQ_EstadoLuminaria_nombre UNIQUE (nombre)
);
GO

-- ------------------------------------------------------------
-- 2.6 catalogo.CondicionClima
--     Condiciones climáticas registradas por los sensores.
--     Ejemplos: Soleado, Nublado, Lluvioso, Despejado Nocturno
-- ------------------------------------------------------------
CREATE TABLE catalogo.CondicionClima (
    condicion_clima_id TINYINT     NOT NULL  IDENTITY(1,1),
    nombre             VARCHAR(60) NOT NULL,
    descripcion        VARCHAR(255)    NULL,

    CONSTRAINT PK_CondicionClima PRIMARY KEY (condicion_clima_id),
    CONSTRAINT UQ_CondicionClima_nombre UNIQUE (nombre)
);
GO

-- ------------------------------------------------------------
-- 2.7 catalogo.TipoAnomalia
--     Categorías de anomalías detectables en la red.
--     Ejemplos: Consumo elevado, Falla de sensor, Encendido diurno
-- ------------------------------------------------------------
CREATE TABLE catalogo.TipoAnomalia (
    tipo_anomalia_id TINYINT      NOT NULL  IDENTITY(1,1),
    nombre           VARCHAR(80)  NOT NULL,
    nivel_severidad  TINYINT      NOT NULL,
    -- 1=Informativo | 2=Leve | 3=Moderado | 4=Crítico
    descripcion      VARCHAR(255)     NULL,

    CONSTRAINT PK_TipoAnomalia PRIMARY KEY (tipo_anomalia_id),
    CONSTRAINT UQ_TipoAnomalia_nombre UNIQUE (nombre)
);
GO


-- ============================================================
-- 3. TABLAS MAESTRAS
--    Entidades físicas y geográficas del sistema.
--    Dependen de tablas de catálogo.
-- ============================================================

-- ------------------------------------------------------------
-- 3.1 maestro.Zona
--     Catálogo de las 20 localidades de Bogotá D.C.
--     Tabla raíz: sensores, luminarias y políticas dependen de ella.
-- ------------------------------------------------------------
CREATE TABLE maestro.Zona (
    zona_id        INT           NOT NULL  IDENTITY(1,1),
    nombre_zona    VARCHAR(100)  NOT NULL,
    localidad      VARCHAR(100)  NOT NULL,
    tipo_zona_id   TINYINT       NOT NULL,
    latitud        DECIMAL(9,6)  NOT NULL,
    longitud       DECIMAL(9,6)  NOT NULL,
    poblacion      INT           NOT NULL,
    area_km2       DECIMAL(8,2)  NOT NULL,
    fecha_registro DATETIME2(0)  NOT NULL  DEFAULT GETDATE(),
    activa         BIT           NOT NULL  DEFAULT 1,

    CONSTRAINT PK_Zona PRIMARY KEY (zona_id),
    CONSTRAINT UQ_Zona_nombre UNIQUE (nombre_zona),
    CONSTRAINT FK_Zona_TipoZona FOREIGN KEY (tipo_zona_id)
        REFERENCES catalogo.TipoZona (tipo_zona_id)
);
GO

-- ------------------------------------------------------------
-- 3.2 maestro.Sensor
--     Unidades físicas de sensor instaladas en la red.
--     Cada sensor reporta a una zona y pertenece a un tipo/modelo.
-- ------------------------------------------------------------
CREATE TABLE maestro.Sensor (
    sensor_id                 INT          NOT NULL  IDENTITY(1,1),
    zona_id                   INT          NOT NULL,
    tipo_sensor_id            INT          NOT NULL,
    estado_sensor_id          TINYINT      NOT NULL,
    codigo_externo            VARCHAR(50)      NULL,
    latitud                   DECIMAL(9,6) NOT NULL,
    longitud                  DECIMAL(9,6) NOT NULL,
    fecha_instalacion         DATE         NOT NULL,
    fecha_ultimo_mantenimiento DATE             NULL,
    observaciones             VARCHAR(255)     NULL,

    CONSTRAINT PK_Sensor PRIMARY KEY (sensor_id),
    CONSTRAINT FK_Sensor_Zona FOREIGN KEY (zona_id)
        REFERENCES maestro.Zona (zona_id),
    CONSTRAINT FK_Sensor_TipoSensor FOREIGN KEY (tipo_sensor_id)
        REFERENCES catalogo.TipoSensor (tipo_sensor_id),
    CONSTRAINT FK_Sensor_EstadoSensor FOREIGN KEY (estado_sensor_id)
        REFERENCES catalogo.EstadoSensor (estado_sensor_id)
);
GO

-- ------------------------------------------------------------
-- 3.3 maestro.Luminaria
--     Inventario de cada punto de luz de la red de alumbrado.
--     Asociada a un sensor (1:1 simplificado) y a una zona.
-- ------------------------------------------------------------
CREATE TABLE maestro.Luminaria (
    luminaria_id              INT           NOT NULL  IDENTITY(1,1),
    sensor_id                 INT           NOT NULL,
    zona_id                   INT           NOT NULL,
    tipo_lampara_id           INT           NOT NULL,
    estado_luminaria_id       TINYINT       NOT NULL,
    potencia_w                DECIMAL(6,2)  NOT NULL,
    altura_poste_m            DECIMAL(5,2)      NULL,
    codigo_poste              VARCHAR(50)       NULL,
    latitud                   DECIMAL(9,6)      NULL,
    longitud                  DECIMAL(9,6)      NULL,
    fecha_instalacion         DATE          NOT NULL,
    horas_operacion_acumuladas INT          NOT NULL  DEFAULT 0,

    CONSTRAINT PK_Luminaria PRIMARY KEY (luminaria_id),
    CONSTRAINT FK_Luminaria_Sensor FOREIGN KEY (sensor_id)
        REFERENCES maestro.Sensor (sensor_id),
    CONSTRAINT FK_Luminaria_Zona FOREIGN KEY (zona_id)
        REFERENCES maestro.Zona (zona_id),
    CONSTRAINT FK_Luminaria_TipoLampara FOREIGN KEY (tipo_lampara_id)
        REFERENCES catalogo.TipoLampara (tipo_lampara_id),
    CONSTRAINT FK_Luminaria_EstadoLuminaria FOREIGN KEY (estado_luminaria_id)
        REFERENCES catalogo.EstadoLuminaria (estado_luminaria_id)
);
GO

-- ------------------------------------------------------------
-- 3.4 control.PoliticaIluminacion
--     Reglas de encendido/apagado y dimming por zona.
--     Incluye vigencia temporal para auditar cambios de política
--     (SCD Tipo 2 simplificado).
--     Va en esquema 'control' porque es una directriz operativa,
--     no un activo físico.
-- ------------------------------------------------------------
CREATE TABLE control.PoliticaIluminacion (
    politica_id                 INT           NOT NULL  IDENTITY(1,1),
    zona_id                     INT           NOT NULL,
    nombre_politica             VARCHAR(100)  NOT NULL,
    hora_encendido              TIME(0)       NOT NULL,
    hora_apagado                TIME(0)       NOT NULL,
    nivel_lux_umbral            DECIMAL(6,2)  NOT NULL,
    nivel_potencia_reduccion_pct TINYINT      NOT NULL  DEFAULT 100,
    -- 0–100: porcentaje de potencia en horario de baja demanda
    aplica_fines_semana         BIT           NOT NULL  DEFAULT 1,
    aplica_festivos             BIT           NOT NULL  DEFAULT 1,
    fecha_vigencia_desde        DATE          NOT NULL,
    fecha_vigencia_hasta        DATE              NULL,
    activa                      BIT           NOT NULL  DEFAULT 1,
    descripcion                 VARCHAR(255)      NULL,

    CONSTRAINT PK_PoliticaIluminacion PRIMARY KEY (politica_id),
    CONSTRAINT FK_Politica_Zona FOREIGN KEY (zona_id)
        REFERENCES maestro.Zona (zona_id)
);
GO


-- ============================================================
-- 4. TABLAS OPERATIVAS / TRANSACCIONALES
--    Alta frecuencia de escritura. Aquí vive el millón de filas.
-- ============================================================

-- ------------------------------------------------------------
-- 4.1 operativo.LecturaAmbiente
--     TABLA PRINCIPAL — millones de filas.
--     Cada fila = una medición de un sensor en un instante.
--     Fuente primaria del pipeline ETL hacia el DW.
-- ------------------------------------------------------------
CREATE TABLE operativo.LecturaAmbiente (
    lectura_id         BIGINT        NOT NULL  IDENTITY(1,1),
    sensor_id          INT           NOT NULL,
    condicion_clima_id TINYINT       NOT NULL,
    timestamp_lectura  DATETIME2(0)  NOT NULL,
    nivel_lux          DECIMAL(8,2)  NOT NULL,
    temperatura_c      DECIMAL(5,2)  NOT NULL,
    cobertura_nubosa_pct TINYINT     NOT NULL,
    -- 0–100 (TINYINT ahorra espacio en millones de filas)
    radiacion_solar_wm2 DECIMAL(7,2) NOT NULL,
    anomalia_flag      BIT           NOT NULL  DEFAULT 0,
    -- 1 en ~2% de registros → dispara carga en EventoAnomalia

    CONSTRAINT PK_LecturaAmbiente PRIMARY KEY (lectura_id),
    CONSTRAINT FK_Lectura_Sensor FOREIGN KEY (sensor_id)
        REFERENCES maestro.Sensor (sensor_id),
    CONSTRAINT FK_Lectura_CondicionClima FOREIGN KEY (condicion_clima_id)
        REFERENCES catalogo.CondicionClima (condicion_clima_id)
);
GO

-- ------------------------------------------------------------
-- 4.2 operativo.ConsumoEnergetico
--     Consumo eléctrico de cada luminaria por período de medición.
--     Se vincula con LecturaAmbiente para correlacionar consumo
--     con condiciones ambientales.
--     costo_cop es columna computada persisted para consultas rápidas.
-- ------------------------------------------------------------
CREATE TABLE operativo.ConsumoEnergetico (
    consumo_id       BIGINT        NOT NULL  IDENTITY(1,1),
    luminaria_id     INT           NOT NULL,
    lectura_id       BIGINT        NOT NULL,
    fecha_hora       DATETIME2(0)  NOT NULL,
    kwh_consumido    DECIMAL(8,4)  NOT NULL,
    estado_encendido BIT           NOT NULL,
    potencia_activa_w DECIMAL(6,2)     NULL,
    tarifa_cop_kwh   DECIMAL(10,2)     NULL,
    costo_cop        AS (kwh_consumido * tarifa_cop_kwh) PERSISTED,
    -- Columna computada: se almacena físicamente para evitar
    -- recálculo en cada consulta de Power BI / ETL.

    CONSTRAINT PK_ConsumoEnergetico PRIMARY KEY (consumo_id),
    CONSTRAINT FK_Consumo_Luminaria FOREIGN KEY (luminaria_id)
        REFERENCES maestro.Luminaria (luminaria_id),
    CONSTRAINT FK_Consumo_Lectura FOREIGN KEY (lectura_id)
        REFERENCES operativo.LecturaAmbiente (lectura_id)
);
GO

-- ------------------------------------------------------------
-- 4.3 operativo.EventoAnomalia
--     Fallas y comportamientos fuera de rango detectados.
--     Se pobla desde LecturaAmbiente (anomalia_flag=1) o
--     manualmente por operadores.
-- ------------------------------------------------------------
CREATE TABLE operativo.EventoAnomalia (
    evento_id          INT           NOT NULL  IDENTITY(1,1),
    luminaria_id       INT           NOT NULL,
    lectura_id         BIGINT            NULL,
    tipo_anomalia_id   TINYINT       NOT NULL,
    fecha_hora         DATETIME2(0)  NOT NULL,
    descripcion        VARCHAR(500)      NULL,
    resuelto           BIT           NOT NULL  DEFAULT 0,
    fecha_resolucion   DATETIME2(0)      NULL,
    tecnico_responsable VARCHAR(100)     NULL,

    CONSTRAINT PK_EventoAnomalia PRIMARY KEY (evento_id),
    CONSTRAINT FK_Evento_Luminaria FOREIGN KEY (luminaria_id)
        REFERENCES maestro.Luminaria (luminaria_id),
    CONSTRAINT FK_Evento_Lectura FOREIGN KEY (lectura_id)
        REFERENCES operativo.LecturaAmbiente (lectura_id),
    CONSTRAINT FK_Evento_TipoAnomalia FOREIGN KEY (tipo_anomalia_id)
        REFERENCES catalogo.TipoAnomalia (tipo_anomalia_id)
);
GO


-- ============================================================
-- 5. ÍNDICES
--    Optimizan las consultas más frecuentes: rango temporal,
--    filtro por sensor/zona, y los JOINs del ETL (Flujo 6).
-- ============================================================

-- LecturaAmbiente: las consultas más costosas ocurren aquí.
-- El índice agrupado por defecto queda en lectura_id (PK).
-- Agregamos no agrupados para los patrones de acceso reales.

CREATE NONCLUSTERED INDEX IX_LecturaAmbiente_Timestamp
    ON operativo.LecturaAmbiente (timestamp_lectura ASC);
GO

CREATE NONCLUSTERED INDEX IX_LecturaAmbiente_SensorId
    ON operativo.LecturaAmbiente (sensor_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_LecturaAmbiente_Sensor_Timestamp
    ON operativo.LecturaAmbiente (sensor_id ASC, timestamp_lectura ASC)
    INCLUDE (nivel_lux, kwh_consumido)
    -- Índice cubriente para el JOIN principal del ETL (Flujo 6)
    -- Evita key lookups al proyectar las columnas más usadas.
;
GO

-- ConsumoEnergetico: filtros por período y por luminaria.

CREATE NONCLUSTERED INDEX IX_ConsumoEnergetico_FechaHora
    ON operativo.ConsumoEnergetico (fecha_hora ASC);
GO

CREATE NONCLUSTERED INDEX IX_ConsumoEnergetico_Luminaria_Fecha
    ON operativo.ConsumoEnergetico (luminaria_id ASC, fecha_hora ASC);
GO

-- EventoAnomalia: consultas de mantenimiento por luminaria y fecha.

CREATE NONCLUSTERED INDEX IX_EventoAnomalia_LuminariaId
    ON operativo.EventoAnomalia (luminaria_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_EventoAnomalia_FechaHora
    ON operativo.EventoAnomalia (fecha_hora ASC);
GO

-- Sensor: filtros por zona (frecuente en reportes geográficos).

CREATE NONCLUSTERED INDEX IX_Sensor_ZonaId
    ON maestro.Sensor (zona_id ASC);
GO

-- Luminaria: filtros por zona y por sensor.

CREATE NONCLUSTERED INDEX IX_Luminaria_ZonaId
    ON maestro.Luminaria (zona_id ASC);
GO

CREATE NONCLUSTERED INDEX IX_Luminaria_SensorId
    ON maestro.Luminaria (sensor_id ASC);
GO


-- ============================================================
-- 6. DATOS SEMILLA — TABLAS DE CATÁLOGO
--    Se insertan antes de cualquier carga de datos.
--    El Integrante 2 debe referenciar estos IDs en el CSV.
-- ============================================================

-- 6.1 TipoZona
INSERT INTO catalogo.TipoZona (nombre, descripcion) VALUES
    ('Residencial', 'Zonas predominantemente habitacionales'),
    ('Comercial',   'Zonas con alta actividad comercial y de servicios'),
    ('Industrial',  'Zonas de actividad fabril y logística'),
    ('Mixta',       'Zonas con uso combinado residencial y comercial'),
    ('Rural',       'Zonas de baja densidad urbana o periurbanas');
GO

-- 6.2 TipoSensor
INSERT INTO catalogo.TipoSensor (nombre_tipo, modelo, fabricante, unidad_medida_lux, precision_pct, descripcion) VALUES
    ('Fotoeléctrico Digital', 'BH1750',   'ROHM Semiconductor', 'lux', 1.80, 'Sensor de luz ambiente de alta precisión, interfaz I2C, rango 1–65535 lux'),
    ('Fotoeléctrico Digital', 'TSL2561',  'ams OSRAM',          'lux', 0.50, 'Sensor de luminosidad con canal IR independiente, interfaz I2C'),
    ('LDR Analógico',         'GL5528',   'Token Electronics',   'lux', 5.00, 'Fotorresistencia de bajo costo para medición aproximada de iluminancia'),
    ('Multifunción',          'VEML7700', 'Vishay',             'lux', 0.25, 'Sensor ALS de alta resolución con umbral programable, I2C');
GO

-- 6.3 EstadoSensor
INSERT INTO catalogo.EstadoSensor (nombre, descripcion) VALUES
    ('Activo',           'Sensor operando con normalidad'),
    ('Inactivo',         'Sensor apagado o sin alimentación'),
    ('En mantenimiento', 'Sensor temporalmente fuera de servicio por revisión técnica'),
    ('Dado de baja',     'Sensor retirado definitivamente de la red');
GO

-- 6.4 TipoLampara
INSERT INTO catalogo.TipoLampara (nombre_tipo, eficiencia_lm_w, vida_util_horas, indice_reproduccion_color, temperatura_color_k, descripcion) VALUES
    ('LED',                130.00, 50000, 80, 4000, 'Diodo emisor de luz. Alta eficiencia y vida útil. Tecnología preferida en modernización'),
    ('Sodio Alta Presión',  95.00, 24000, 25, 2100, 'Lámpara de vapor de sodio. Alta eficiencia pero pobre reproducción de color'),
    ('Haluro Metálico',     90.00, 15000, 85, 4200, 'Buena reproducción de color. Usada en zonas comerciales y deportivas'),
    ('Mercurio',            55.00, 16000, 45, 3900, 'Tecnología obsoleta en proceso de sustitución por normativa ambiental'),
    ('Inducción',          100.00, 60000, 80, 4000, 'Larga vida útil, sin electrodos. Adecuada para puntos de difícil acceso');
GO

-- 6.5 EstadoLuminaria
INSERT INTO catalogo.EstadoLuminaria (nombre, descripcion) VALUES
    ('Operativa',    'Luminaria funcionando dentro de parámetros normales'),
    ('Averiada',     'Luminaria con falla detectada, pendiente de atención'),
    ('En reemplazo', 'Luminaria en proceso de sustitución por cuadrilla técnica'),
    ('Dada de baja', 'Luminaria retirada definitivamente del servicio');
GO

-- 6.6 CondicionClima
INSERT INTO catalogo.CondicionClima (nombre, descripcion) VALUES
    ('Soleado',            'Cielo despejado con alta radiación solar, típico de mediodía'),
    ('Nublado',            'Cobertura nubosa significativa, radiación solar reducida'),
    ('Lluvioso',           'Presencia de precipitación, baja visibilidad y alta humedad'),
    ('Despejado Nocturno', 'Cielo sin nubes en horario nocturno, sin radiación solar');
GO

-- 6.7 TipoAnomalia
INSERT INTO catalogo.TipoAnomalia (nombre, nivel_severidad, descripcion) VALUES
    ('Consumo elevado',       3, 'El kWh consumido supera en más de 20% el valor esperado para la potencia nominal'),
    ('Consumo nulo',          2, 'La luminaria reporta estado encendido pero kwh_consumido = 0'),
    ('Falla de sensor',       4, 'El sensor no responde o entrega valores fuera del rango físico posible'),
    ('Encendido diurno',      2, 'La luminaria permanece encendida cuando nivel_lux supera el umbral de la política'),
    ('Apagado nocturno',      3, 'La luminaria no enciende cuando nivel_lux cae por debajo del umbral nocturno'),
    ('Fluctuación de voltaje',3, 'Variación brusca de potencia activa indicando inestabilidad en el suministro');
GO


-- ============================================================
-- 7. VERIFICACIÓN RÁPIDA POST-INSTALACIÓN
-- ============================================================

SELECT
    s.name       AS esquema,
    t.name       AS tabla,
    p.rows       AS filas_estimadas
FROM sys.tables   t
JOIN sys.schemas  s ON t.schema_id = s.schema_id
JOIN sys.indexes  i ON t.object_id = i.object_id AND i.index_id IN (0,1)
JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE s.name IN ('catalogo','maestro','operativo','control')
ORDER BY s.name, t.name;
GO

-- ============================================================
-- FIN DEL SCRIPT
-- ============================================================
-- Próximo paso (Días 3-4): ejecutar stored_procedures_carga.sql
-- para poblar maestro.Zona (20 localidades), maestro.Sensor,
-- maestro.Luminaria, control.PoliticaIluminacion, y luego
-- la carga masiva de operativo.LecturaAmbiente con BULK INSERT.
-- ============================================================
