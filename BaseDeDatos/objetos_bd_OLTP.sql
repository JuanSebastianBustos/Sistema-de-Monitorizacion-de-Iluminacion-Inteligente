-- ============================================================
--  SCRIPT DE OBJETOS DE BASE DE DATOS — OLTP
--  Sistema de Monitorización de Iluminación Inteligente
--  Bogotá D.C. · Ciudades Inteligentes
-- ============================================================
--  Motor        : SQL Server 2019 / 2022
--  Base de datos: IluminacionBogota_OLTP
--
--  Contenido:
--    BLOQUE 1 — Tablas de auditoría (requisito previo de triggers)
--    BLOQUE 2 — Stored Procedures (7 procedimientos)
--    BLOQUE 3 — Triggers (5 triggers)
--    BLOQUE 4 — Vistas (4 vistas)
--    BLOQUE 5 — Verificación post-instalación
--
--  PREREQUISITO: ejecutar modelo_transaccional_DDL.sql primero.
--  Este script asume que la base de datos y todas sus tablas
--  ya existen en IluminacionBogota_OLTP.
-- ============================================================

USE IluminacionBogota_OLTP;
GO

-- ============================================================
-- BLOQUE 1 — TABLAS DE AUDITORÍA
--  Deben existir antes de crear los triggers que las alimentan.
--  Esquema: control (auditoría y trazabilidad de operaciones).
--  Patrón: guardan snapshot del estado anterior (OLD) y
--  posterior (NEW) junto con metadatos de la operación.
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 control.AuditSensor
--     Historial completo de cambios sobre maestro.Sensor.
--     Alimentada por trg_Audit_Sensor_IUD.
-- ------------------------------------------------------------
IF OBJECT_ID('control.AuditSensor', 'U') IS NOT NULL
    DROP TABLE control.AuditSensor;
GO

CREATE TABLE control.AuditSensor (
    audit_id               BIGINT        NOT NULL  IDENTITY(1,1),
    tipo_operacion         CHAR(1)       NOT NULL,
    -- 'I' = INSERT | 'U' = UPDATE | 'D' = DELETE
    fecha_operacion        DATETIME2(0)  NOT NULL  DEFAULT GETDATE(),
    usuario_bd             NVARCHAR(128) NOT NULL  DEFAULT SUSER_SNAME(),
    host_name              NVARCHAR(128) NOT NULL  DEFAULT HOST_NAME(),
    sensor_id              INT               NULL,
    -- Valores ANTERIORES (NULL en INSERT)
    old_zona_id            INT               NULL,
    old_tipo_sensor_id     INT               NULL,
    old_estado_sensor_id   TINYINT           NULL,
    old_fecha_ultimo_mant  DATE              NULL,
    old_observaciones      VARCHAR(255)      NULL,
    -- Valores POSTERIORES (NULL en DELETE)
    new_zona_id            INT               NULL,
    new_tipo_sensor_id     INT               NULL,
    new_estado_sensor_id   TINYINT           NULL,
    new_fecha_ultimo_mant  DATE              NULL,
    new_observaciones      VARCHAR(255)      NULL,

    CONSTRAINT PK_AuditSensor PRIMARY KEY (audit_id)
);
GO

-- ------------------------------------------------------------
-- 1.2 control.AuditLuminaria
--     Historial completo de cambios sobre maestro.Luminaria.
--     Alimentada por trg_Audit_Luminaria_IUD.
--     horas_operacion_acumuladas trazable para calcular ROI
--     real de la modernización LED.
-- ------------------------------------------------------------
IF OBJECT_ID('control.AuditLuminaria', 'U') IS NOT NULL
    DROP TABLE control.AuditLuminaria;
GO

CREATE TABLE control.AuditLuminaria (
    audit_id                       BIGINT        NOT NULL  IDENTITY(1,1),
    tipo_operacion                 CHAR(1)       NOT NULL,
    fecha_operacion                DATETIME2(0)  NOT NULL  DEFAULT GETDATE(),
    usuario_bd                     NVARCHAR(128) NOT NULL  DEFAULT SUSER_SNAME(),
    host_name                      NVARCHAR(128) NOT NULL  DEFAULT HOST_NAME(),
    luminaria_id                   INT               NULL,
    -- Valores anteriores
    old_sensor_id                  INT               NULL,
    old_zona_id                    INT               NULL,
    old_tipo_lampara_id            INT               NULL,
    old_estado_luminaria_id        TINYINT           NULL,
    old_potencia_w                 DECIMAL(6,2)      NULL,
    old_horas_operacion_acumuladas INT               NULL,
    -- Valores posteriores
    new_sensor_id                  INT               NULL,
    new_zona_id                    INT               NULL,
    new_tipo_lampara_id            INT               NULL,
    new_estado_luminaria_id        TINYINT           NULL,
    new_potencia_w                 DECIMAL(6,2)      NULL,
    new_horas_operacion_acumuladas INT               NULL,

    CONSTRAINT PK_AuditLuminaria PRIMARY KEY (audit_id)
);
GO

-- ------------------------------------------------------------
-- 1.3 control.AuditPolitica
--     Historial completo de cambios sobre control.PoliticaIluminacion.
--     Alimentada por trg_Audit_PoliticaIluminacion_IUD.
--     Permite reconstruir el estado exacto de una política en
--     cualquier fecha histórica para análisis en Power BI.
-- ------------------------------------------------------------
IF OBJECT_ID('control.AuditPolitica', 'U') IS NOT NULL
    DROP TABLE control.AuditPolitica;
GO

CREATE TABLE control.AuditPolitica (
    audit_id                         BIGINT        NOT NULL  IDENTITY(1,1),
    tipo_operacion                   CHAR(1)       NOT NULL,
    fecha_operacion                  DATETIME2(0)  NOT NULL  DEFAULT GETDATE(),
    usuario_bd                       NVARCHAR(128) NOT NULL  DEFAULT SUSER_SNAME(),
    host_name                        NVARCHAR(128) NOT NULL  DEFAULT HOST_NAME(),
    politica_id                      INT               NULL,
    -- Valores anteriores
    old_zona_id                      INT               NULL,
    old_nombre_politica              VARCHAR(100)      NULL,
    old_hora_encendido               TIME(0)           NULL,
    old_hora_apagado                 TIME(0)           NULL,
    old_nivel_lux_umbral             DECIMAL(6,2)      NULL,
    old_nivel_potencia_reduccion_pct TINYINT           NULL,
    old_aplica_fines_semana          BIT               NULL,
    old_aplica_festivos              BIT               NULL,
    old_fecha_vigencia_desde         DATE              NULL,
    old_fecha_vigencia_hasta         DATE              NULL,
    old_activa                       BIT               NULL,
    -- Valores posteriores
    new_zona_id                      INT               NULL,
    new_nombre_politica              VARCHAR(100)      NULL,
    new_hora_encendido               TIME(0)           NULL,
    new_hora_apagado                 TIME(0)           NULL,
    new_nivel_lux_umbral             DECIMAL(6,2)      NULL,
    new_nivel_potencia_reduccion_pct TINYINT           NULL,
    new_aplica_fines_semana          BIT               NULL,
    new_aplica_festivos              BIT               NULL,
    new_fecha_vigencia_desde         DATE              NULL,
    new_fecha_vigencia_hasta         DATE              NULL,
    new_activa                       BIT               NULL,

    CONSTRAINT PK_AuditPolitica PRIMARY KEY (audit_id)
);
GO


-- ============================================================
-- BLOQUE 2 — STORED PROCEDURES
--  Convención de nombres : usp_ (user stored procedure)
--  Manejo de errores     : TRY/CATCH + RAISERROR en todos.
--  Transacciones         : explícitas en escrituras.
--  SET NOCOUNT ON        : evita mensajes de filas afectadas
--                          que interfieren con resultsets ETL.
-- ============================================================

-- ------------------------------------------------------------
-- SP-01  usp_InsertarLecturaAmbiente
--  Valida existencia y estado activo del sensor.
--  Valida existencia de la condición climática en catálogo.
--  Valida rango de cobertura nubosa (0-100).
--  Detecta anomalía física: lux = 0 con radiación alta
--  (posible falla de sensor en horario diurno).
--  Parámetro OUTPUT: devuelve el lectura_id generado.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.usp_InsertarLecturaAmbiente', 'P') IS NOT NULL
    DROP PROCEDURE operativo.usp_InsertarLecturaAmbiente;
GO

CREATE PROCEDURE operativo.usp_InsertarLecturaAmbiente
    @sensor_id            INT,
    @condicion_clima_id   TINYINT,
    @timestamp_lectura    DATETIME2(0),
    @nivel_lux            DECIMAL(8,2),
    @temperatura_c        DECIMAL(5,2),
    @cobertura_nubosa_pct TINYINT,
    @radiacion_solar_wm2  DECIMAL(7,2),
    @lectura_id           BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @estado_nombre VARCHAR(60);
    DECLARE @anomalia      BIT = 0;
    DECLARE @msg           VARCHAR(300);

    BEGIN TRY

        -- 1. Validar que el sensor existe y está Activo
        SELECT @estado_nombre = es.nombre
        FROM   maestro.Sensor        s
        JOIN   catalogo.EstadoSensor es ON s.estado_sensor_id = es.estado_sensor_id
        WHERE  s.sensor_id = @sensor_id;

        IF @estado_nombre IS NULL
        BEGIN
            SET @msg = 'sensor_id ' + CAST(@sensor_id AS VARCHAR) + ' no existe.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        IF @estado_nombre <> 'Activo'
        BEGIN
            SET @msg = 'sensor_id ' + CAST(@sensor_id AS VARCHAR)
                     + ' no está Activo (estado: ' + @estado_nombre + '). Lectura rechazada.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 2. Validar condición climática en catálogo
        IF NOT EXISTS (
            SELECT 1 FROM catalogo.CondicionClima
            WHERE  condicion_clima_id = @condicion_clima_id
        )
        BEGIN
            SET @msg = 'condicion_clima_id ' + CAST(@condicion_clima_id AS VARCHAR)
                     + ' no existe en catalogo.CondicionClima.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 3. Validar rango de cobertura nubosa
        IF @cobertura_nubosa_pct < 0 OR @cobertura_nubosa_pct > 100
        BEGIN
            RAISERROR('cobertura_nubosa_pct debe estar entre 0 y 100.', 16, 1);
            RETURN;
        END

        -- 4. Detectar inconsistencia física: lux=0 con radiación alta
        IF @nivel_lux <= 0 AND @radiacion_solar_wm2 > 50.0
            SET @anomalia = 1;

        -- 5. Insertar
        BEGIN TRANSACTION;

            INSERT INTO operativo.LecturaAmbiente (
                sensor_id, condicion_clima_id, timestamp_lectura,
                nivel_lux, temperatura_c, cobertura_nubosa_pct,
                radiacion_solar_wm2, anomalia_flag
            )
            VALUES (
                @sensor_id, @condicion_clima_id, @timestamp_lectura,
                @nivel_lux, @temperatura_c, @cobertura_nubosa_pct,
                @radiacion_solar_wm2, @anomalia
            );

            SET @lectura_id = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @e_msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @e_sev INT            = ERROR_SEVERITY();
        DECLARE @e_sta INT            = ERROR_STATE();
        RAISERROR(@e_msg, @e_sev, @e_sta);
    END CATCH
END;
GO


-- ------------------------------------------------------------
-- SP-02  usp_InsertarConsumoEnergetico
--  Valida existencia de luminaria y de la lectura asociada.
--  Valida que kwh no sea negativo.
--  Detecta inconsistencia física: kwh > 0 con luminaria
--  apagada → marca anomalia_flag en la lectura origen.
--  Parámetro OUTPUT: devuelve el consumo_id generado.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.usp_InsertarConsumoEnergetico', 'P') IS NOT NULL
    DROP PROCEDURE operativo.usp_InsertarConsumoEnergetico;
GO

CREATE PROCEDURE operativo.usp_InsertarConsumoEnergetico
    @luminaria_id      INT,
    @lectura_id        BIGINT,
    @fecha_hora        DATETIME2(0),
    @kwh_consumido     DECIMAL(8,4),
    @estado_encendido  BIT,
    @potencia_activa_w DECIMAL(6,2)  = NULL,
    @tarifa_cop_kwh    DECIMAL(10,2) = NULL,
    @consumo_id        BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @msg VARCHAR(300);

    BEGIN TRY

        -- 1. Validar luminaria
        IF NOT EXISTS (SELECT 1 FROM maestro.Luminaria WHERE luminaria_id = @luminaria_id)
        BEGIN
            SET @msg = 'luminaria_id ' + CAST(@luminaria_id AS VARCHAR) + ' no existe.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 2. Validar lectura origen
        IF NOT EXISTS (SELECT 1 FROM operativo.LecturaAmbiente WHERE lectura_id = @lectura_id)
        BEGIN
            SET @msg = 'lectura_id ' + CAST(@lectura_id AS VARCHAR) + ' no existe en LecturaAmbiente.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 3. Validar valor de consumo
        IF @kwh_consumido < 0
        BEGIN
            RAISERROR('kwh_consumido no puede ser negativo.', 16, 1);
            RETURN;
        END

        BEGIN TRANSACTION;

            -- 4. Insertar registro de consumo
            INSERT INTO operativo.ConsumoEnergetico (
                luminaria_id, lectura_id, fecha_hora,
                kwh_consumido, estado_encendido,
                potencia_activa_w, tarifa_cop_kwh
            )
            VALUES (
                @luminaria_id, @lectura_id, @fecha_hora,
                @kwh_consumido, @estado_encendido,
                @potencia_activa_w, @tarifa_cop_kwh
            );

            SET @consumo_id = SCOPE_IDENTITY();

            -- 5. Inconsistencia física: consumo registrado con luminaria apagada
            IF @kwh_consumido > 0 AND @estado_encendido = 0
            BEGIN
                UPDATE operativo.LecturaAmbiente
                SET    anomalia_flag = 1
                WHERE  lectura_id   = @lectura_id;
            END

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @e_msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @e_sev INT            = ERROR_SEVERITY();
        DECLARE @e_sta INT            = ERROR_STATE();
        RAISERROR(@e_msg, @e_sev, @e_sta);
    END CATCH
END;
GO


-- ------------------------------------------------------------
-- SP-03  usp_RegistrarEventoAnomalia
--  Lógica upsert: si ya existe un evento abierto del mismo
--  tipo para la misma luminaria, actualiza descripción en
--  lugar de insertar un duplicado.
--  OUTPUT @evento_id : ID del registro creado o actualizado.
--  OUTPUT @es_nuevo  : 1 = nuevo evento, 0 = actualizado.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.usp_RegistrarEventoAnomalia', 'P') IS NOT NULL
    DROP PROCEDURE operativo.usp_RegistrarEventoAnomalia;
GO

CREATE PROCEDURE operativo.usp_RegistrarEventoAnomalia
    @luminaria_id     INT,
    @lectura_id       BIGINT       = NULL,
    @tipo_anomalia_id TINYINT,
    @descripcion      VARCHAR(500) = NULL,
    @evento_id        INT  OUTPUT,
    @es_nuevo         BIT  OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @msg VARCHAR(300);

    BEGIN TRY

        -- 1. Validar luminaria
        IF NOT EXISTS (SELECT 1 FROM maestro.Luminaria WHERE luminaria_id = @luminaria_id)
        BEGIN
            SET @msg = 'luminaria_id ' + CAST(@luminaria_id AS VARCHAR) + ' no existe.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 2. Validar tipo de anomalía
        IF NOT EXISTS (SELECT 1 FROM catalogo.TipoAnomalia WHERE tipo_anomalia_id = @tipo_anomalia_id)
        BEGIN
            SET @msg = 'tipo_anomalia_id ' + CAST(@tipo_anomalia_id AS VARCHAR) + ' no existe en catálogo.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 3. Validar lectura si fue proporcionada
        IF @lectura_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM operativo.LecturaAmbiente WHERE lectura_id = @lectura_id)
        BEGIN
            SET @msg = 'lectura_id ' + CAST(@lectura_id AS VARCHAR) + ' no existe.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        BEGIN TRANSACTION;

            -- 4. Buscar evento abierto del mismo tipo para la misma luminaria
            SELECT @evento_id = evento_id
            FROM   operativo.EventoAnomalia
            WHERE  luminaria_id     = @luminaria_id
              AND  tipo_anomalia_id = @tipo_anomalia_id
              AND  resuelto         = 0;

            IF @evento_id IS NOT NULL
            BEGIN
                -- Evento duplicado: actualizar descripción
                UPDATE operativo.EventoAnomalia
                SET    descripcion = ISNULL(@descripcion, descripcion),
                       lectura_id  = ISNULL(@lectura_id,  lectura_id)
                WHERE  evento_id   = @evento_id;

                SET @es_nuevo = 0;
            END
            ELSE
            BEGIN
                -- Nuevo evento
                INSERT INTO operativo.EventoAnomalia (
                    luminaria_id, lectura_id, tipo_anomalia_id,
                    fecha_hora, descripcion, resuelto
                )
                VALUES (
                    @luminaria_id, @lectura_id, @tipo_anomalia_id,
                    GETDATE(), @descripcion, 0
                );

                SET @evento_id = SCOPE_IDENTITY();
                SET @es_nuevo  = 1;
            END

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @e_msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @e_sev INT            = ERROR_SEVERITY();
        DECLARE @e_sta INT            = ERROR_STATE();
        RAISERROR(@e_msg, @e_sev, @e_sta);
    END CATCH
END;
GO


-- ------------------------------------------------------------
-- SP-04  usp_ResolverEventoAnomalia
--  Cierra un evento abierto.
--  Valida que exista y no esté ya resuelto.
--  Registra técnico responsable y timestamp de resolución.
--  tecnico_responsable es obligatorio para el cierre.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.usp_ResolverEventoAnomalia', 'P') IS NOT NULL
    DROP PROCEDURE operativo.usp_ResolverEventoAnomalia;
GO

CREATE PROCEDURE operativo.usp_ResolverEventoAnomalia
    @evento_id           INT,
    @tecnico_responsable VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @msg      VARCHAR(300);
    DECLARE @resuelto BIT;

    BEGIN TRY

        -- 1. Verificar que el evento existe
        SELECT @resuelto = resuelto
        FROM   operativo.EventoAnomalia
        WHERE  evento_id = @evento_id;

        IF @resuelto IS NULL
        BEGIN
            SET @msg = 'evento_id ' + CAST(@evento_id AS VARCHAR) + ' no existe.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 2. Verificar que no esté ya resuelto
        IF @resuelto = 1
        BEGIN
            SET @msg = 'evento_id ' + CAST(@evento_id AS VARCHAR) + ' ya fue resuelto anteriormente.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 3. Técnico es obligatorio
        IF LTRIM(RTRIM(ISNULL(@tecnico_responsable, ''))) = ''
        BEGIN
            RAISERROR('tecnico_responsable es obligatorio para cerrar un evento.', 16, 1);
            RETURN;
        END

        BEGIN TRANSACTION;

            UPDATE operativo.EventoAnomalia
            SET    resuelto            = 1,
                   fecha_resolucion    = GETDATE(),
                   tecnico_responsable = @tecnico_responsable
            WHERE  evento_id           = @evento_id;

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @e_msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @e_sev INT            = ERROR_SEVERITY();
        DECLARE @e_sta INT            = ERROR_STATE();
        RAISERROR(@e_msg, @e_sev, @e_sta);
    END CATCH
END;
GO


-- ------------------------------------------------------------
-- SP-05  usp_ActualizarEstadoSensor
--  Actualiza el estado operativo de un sensor.
--  Propagación en cascada: si el sensor pasa a Inactivo o
--  Dado de baja, la luminaria asociada pasa a Averiada.
--  Registra fecha_ultimo_mantenimiento automáticamente.
-- ------------------------------------------------------------
IF OBJECT_ID('maestro.usp_ActualizarEstadoSensor', 'P') IS NOT NULL
    DROP PROCEDURE maestro.usp_ActualizarEstadoSensor;
GO

CREATE PROCEDURE maestro.usp_ActualizarEstadoSensor
    @sensor_id       INT,
    @nuevo_estado_id TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @msg             VARCHAR(300);
    DECLARE @nombre_estado   VARCHAR(60);
    DECLARE @luminaria_id    INT;
    DECLARE @estado_averiada TINYINT;

    BEGIN TRY

        -- 1. Validar que el sensor existe
        IF NOT EXISTS (SELECT 1 FROM maestro.Sensor WHERE sensor_id = @sensor_id)
        BEGIN
            SET @msg = 'sensor_id ' + CAST(@sensor_id AS VARCHAR) + ' no existe.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 2. Validar que el nuevo estado existe en catálogo
        SELECT @nombre_estado = nombre
        FROM   catalogo.EstadoSensor
        WHERE  estado_sensor_id = @nuevo_estado_id;

        IF @nombre_estado IS NULL
        BEGIN
            SET @msg = 'estado_sensor_id ' + CAST(@nuevo_estado_id AS VARCHAR) + ' no existe en catálogo.';
            RAISERROR(@msg, 16, 1);
            RETURN;
        END

        -- 3. Obtener luminaria asociada y el ID del estado 'Averiada'
        SELECT @luminaria_id = luminaria_id
        FROM   maestro.Luminaria
        WHERE  sensor_id = @sensor_id;

        SELECT @estado_averiada = estado_luminaria_id
        FROM   catalogo.EstadoLuminaria
        WHERE  nombre = 'Averiada';

        BEGIN TRANSACTION;

            -- 4. Actualizar estado del sensor
            UPDATE maestro.Sensor
            SET    estado_sensor_id           = @nuevo_estado_id,
                   fecha_ultimo_mantenimiento = CAST(GETDATE() AS DATE)
            WHERE  sensor_id                  = @sensor_id;

            -- 5. Propagación: sensor no operable → luminaria Averiada
            IF @luminaria_id IS NOT NULL
               AND @nombre_estado IN ('Inactivo', 'Dado de baja')
            BEGIN
                UPDATE maestro.Luminaria
                SET    estado_luminaria_id = @estado_averiada
                WHERE  luminaria_id        = @luminaria_id;
            END

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @e_msg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @e_sev INT            = ERROR_SEVERITY();
        DECLARE @e_sta INT            = ERROR_STATE();
        RAISERROR(@e_msg, @e_sev, @e_sta);
    END CATCH
END;
GO


-- ------------------------------------------------------------
-- SP-06  usp_ObtenerLecturasPorSensorYRango
--  Extrae lecturas de un sensor en un rango temporal.
--  Desnormaliza condición climática mediante JOIN.
--  Usado por el Integrante 3 para extraer datos de ML y
--  por el SSIS para validaciones del pipeline.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.usp_ObtenerLecturasPorSensorYRango', 'P') IS NOT NULL
    DROP PROCEDURE operativo.usp_ObtenerLecturasPorSensorYRango;
GO

CREATE PROCEDURE operativo.usp_ObtenerLecturasPorSensorYRango
    @sensor_id    INT,
    @fecha_inicio DATETIME2(0),
    @fecha_fin    DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @msg VARCHAR(300);

    -- 1. Validar que el sensor existe
    IF NOT EXISTS (SELECT 1 FROM maestro.Sensor WHERE sensor_id = @sensor_id)
    BEGIN
        SET @msg = 'sensor_id ' + CAST(@sensor_id AS VARCHAR) + ' no existe.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    -- 2. Validar rango lógico
    IF @fecha_inicio > @fecha_fin
    BEGIN
        RAISERROR('fecha_inicio no puede ser posterior a fecha_fin.', 16, 1);
        RETURN;
    END

    -- 3. Devolver lecturas con contexto climático desnormalizado
    SELECT
        la.lectura_id,
        la.sensor_id,
        la.timestamp_lectura,
        la.nivel_lux,
        la.temperatura_c,
        la.cobertura_nubosa_pct,
        la.radiacion_solar_wm2,
        la.anomalia_flag,
        cc.condicion_clima_id,
        cc.nombre AS condicion_clima
    FROM  operativo.LecturaAmbiente la
    JOIN  catalogo.CondicionClima   cc ON la.condicion_clima_id = cc.condicion_clima_id
    WHERE la.sensor_id         = @sensor_id
      AND la.timestamp_lectura >= @fecha_inicio
      AND la.timestamp_lectura <= @fecha_fin
    ORDER BY la.timestamp_lectura ASC;

END;
GO


-- ------------------------------------------------------------
-- SP-07  usp_ObtenerResumenConsumoZona
--  Resumen agregado de consumo de una zona por mes y año.
--  Insumo para validar los totales del ETL: los agregados
--  de este SP deben coincidir con los del DW tras cada carga.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.usp_ObtenerResumenConsumoZona', 'P') IS NOT NULL
    DROP PROCEDURE operativo.usp_ObtenerResumenConsumoZona;
GO

CREATE PROCEDURE operativo.usp_ObtenerResumenConsumoZona
    @zona_id INT,
    @anio    SMALLINT,
    @mes     TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @msg VARCHAR(300);

    -- 1. Validar zona
    IF NOT EXISTS (SELECT 1 FROM maestro.Zona WHERE zona_id = @zona_id)
    BEGIN
        SET @msg = 'zona_id ' + CAST(@zona_id AS VARCHAR) + ' no existe.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    -- 2. Validar mes
    IF @mes < 1 OR @mes > 12
    BEGIN
        RAISERROR('El mes debe estar entre 1 y 12.', 16, 1);
        RETURN;
    END

    -- 3. Resumen agregado de la zona para el período solicitado
    SELECT
        z.nombre_zona,
        @anio                                                AS anio,
        @mes                                                 AS mes,
        COUNT(DISTINCT l.luminaria_id)                       AS total_luminarias_activas,
        ROUND(SUM(ce.kwh_consumido), 4)                      AS total_kwh_consumido,
        ROUND(SUM(ce.costo_cop), 2)                          AS total_costo_cop,
        ROUND(AVG(la.nivel_lux), 2)                          AS promedio_nivel_lux,
        SUM(CAST(ce.estado_encendido AS INT))                 AS total_horas_operacion,
        COUNT(CASE WHEN la.anomalia_flag = 1 THEN 1 END)     AS total_anomalias,
        ROUND(
            100.0 * COUNT(CASE WHEN la.anomalia_flag = 1 THEN 1 END)
            / NULLIF(COUNT(la.lectura_id), 0),
        2)                                                   AS pct_anomalias
    FROM  maestro.Zona                  z
    JOIN  maestro.Luminaria             l  ON z.zona_id      = l.zona_id
    JOIN  operativo.ConsumoEnergetico   ce ON l.luminaria_id = ce.luminaria_id
    JOIN  operativo.LecturaAmbiente     la ON ce.lectura_id  = la.lectura_id
    WHERE z.zona_id           = @zona_id
      AND YEAR(ce.fecha_hora)  = @anio
      AND MONTH(ce.fecha_hora) = @mes
    GROUP BY z.nombre_zona;

END;
GO


-- ============================================================
-- BLOQUE 3 — TRIGGERS
--  Nota sobre INSERTED / DELETED:
--    SQL Server las provee automáticamente dentro del trigger.
--    INSERTED = estado nuevo.  DELETED = estado anterior.
--    INSERT  → solo INSERTED.
--    DELETE  → solo DELETED.
--    UPDATE  → ambas.
--  FULL OUTER JOIN entre INSERTED y DELETED garantiza que
--  los triggers de auditoría procesen correctamente lotes
--  de múltiples filas (ej. carga masiva del SSIS).
-- ============================================================

-- ------------------------------------------------------------
-- TR-01  trg_Audit_Sensor_IUD
--  AFTER INSERT, UPDATE, DELETE sobre maestro.Sensor.
--  Registra snapshot anterior y posterior en AuditSensor.
-- ------------------------------------------------------------
IF OBJECT_ID('maestro.trg_Audit_Sensor_IUD', 'TR') IS NOT NULL
    DROP TRIGGER maestro.trg_Audit_Sensor_IUD;
GO

CREATE TRIGGER maestro.trg_Audit_Sensor_IUD
ON maestro.Sensor
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tipo_op CHAR(1);

    IF EXISTS (SELECT 1 FROM INSERTED) AND EXISTS (SELECT 1 FROM DELETED)
        SET @tipo_op = 'U';
    ELSE IF EXISTS (SELECT 1 FROM INSERTED)
        SET @tipo_op = 'I';
    ELSE
        SET @tipo_op = 'D';

    INSERT INTO control.AuditSensor (
        tipo_operacion, fecha_operacion, usuario_bd, host_name,
        sensor_id,
        old_zona_id,          old_tipo_sensor_id,    old_estado_sensor_id,
        old_fecha_ultimo_mant, old_observaciones,
        new_zona_id,          new_tipo_sensor_id,    new_estado_sensor_id,
        new_fecha_ultimo_mant, new_observaciones
    )
    SELECT
        @tipo_op, GETDATE(), SUSER_SNAME(), HOST_NAME(),
        COALESCE(i.sensor_id, d.sensor_id),
        d.zona_id,            d.tipo_sensor_id,      d.estado_sensor_id,
        d.fecha_ultimo_mantenimiento, d.observaciones,
        i.zona_id,            i.tipo_sensor_id,      i.estado_sensor_id,
        i.fecha_ultimo_mantenimiento, i.observaciones
    FROM      INSERTED i
    FULL OUTER JOIN DELETED d ON i.sensor_id = d.sensor_id;

END;
GO


-- ------------------------------------------------------------
-- TR-02  trg_Audit_Luminaria_IUD
--  AFTER INSERT, UPDATE, DELETE sobre maestro.Luminaria.
--  Registra snapshot anterior y posterior en AuditLuminaria.
--  horas_operacion_acumuladas incluida para trazabilidad
--  del ciclo de vida de cada luminaria.
-- ------------------------------------------------------------
IF OBJECT_ID('maestro.trg_Audit_Luminaria_IUD', 'TR') IS NOT NULL
    DROP TRIGGER maestro.trg_Audit_Luminaria_IUD;
GO

CREATE TRIGGER maestro.trg_Audit_Luminaria_IUD
ON maestro.Luminaria
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tipo_op CHAR(1);

    IF EXISTS (SELECT 1 FROM INSERTED) AND EXISTS (SELECT 1 FROM DELETED)
        SET @tipo_op = 'U';
    ELSE IF EXISTS (SELECT 1 FROM INSERTED)
        SET @tipo_op = 'I';
    ELSE
        SET @tipo_op = 'D';

    INSERT INTO control.AuditLuminaria (
        tipo_operacion, fecha_operacion, usuario_bd, host_name,
        luminaria_id,
        old_sensor_id,       old_zona_id,
        old_tipo_lampara_id, old_estado_luminaria_id,
        old_potencia_w,      old_horas_operacion_acumuladas,
        new_sensor_id,       new_zona_id,
        new_tipo_lampara_id, new_estado_luminaria_id,
        new_potencia_w,      new_horas_operacion_acumuladas
    )
    SELECT
        @tipo_op, GETDATE(), SUSER_SNAME(), HOST_NAME(),
        COALESCE(i.luminaria_id, d.luminaria_id),
        d.sensor_id,         d.zona_id,
        d.tipo_lampara_id,   d.estado_luminaria_id,
        d.potencia_w,        d.horas_operacion_acumuladas,
        i.sensor_id,         i.zona_id,
        i.tipo_lampara_id,   i.estado_luminaria_id,
        i.potencia_w,        i.horas_operacion_acumuladas
    FROM      INSERTED i
    FULL OUTER JOIN DELETED d ON i.luminaria_id = d.luminaria_id;

END;
GO


-- ------------------------------------------------------------
-- TR-03  trg_Audit_PoliticaIluminacion_IUD
--  AFTER INSERT, UPDATE, DELETE sobre control.PoliticaIluminacion.
--  Registra snapshot completo de la política en AuditPolitica.
--  Permite reconstruir qué política regía cada zona en
--  cualquier fecha histórica para análisis en Power BI.
-- ------------------------------------------------------------
IF OBJECT_ID('control.trg_Audit_PoliticaIluminacion_IUD', 'TR') IS NOT NULL
    DROP TRIGGER control.trg_Audit_PoliticaIluminacion_IUD;
GO

CREATE TRIGGER control.trg_Audit_PoliticaIluminacion_IUD
ON control.PoliticaIluminacion
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tipo_op CHAR(1);

    IF EXISTS (SELECT 1 FROM INSERTED) AND EXISTS (SELECT 1 FROM DELETED)
        SET @tipo_op = 'U';
    ELSE IF EXISTS (SELECT 1 FROM INSERTED)
        SET @tipo_op = 'I';
    ELSE
        SET @tipo_op = 'D';

    INSERT INTO control.AuditPolitica (
        tipo_operacion, fecha_operacion, usuario_bd, host_name,
        politica_id,
        old_zona_id,                      old_nombre_politica,
        old_hora_encendido,               old_hora_apagado,
        old_nivel_lux_umbral,             old_nivel_potencia_reduccion_pct,
        old_aplica_fines_semana,          old_aplica_festivos,
        old_fecha_vigencia_desde,         old_fecha_vigencia_hasta,
        old_activa,
        new_zona_id,                      new_nombre_politica,
        new_hora_encendido,               new_hora_apagado,
        new_nivel_lux_umbral,             new_nivel_potencia_reduccion_pct,
        new_aplica_fines_semana,          new_aplica_festivos,
        new_fecha_vigencia_desde,         new_fecha_vigencia_hasta,
        new_activa
    )
    SELECT
        @tipo_op, GETDATE(), SUSER_SNAME(), HOST_NAME(),
        COALESCE(i.politica_id, d.politica_id),
        d.zona_id,                        d.nombre_politica,
        d.hora_encendido,                 d.hora_apagado,
        d.nivel_lux_umbral,               d.nivel_potencia_reduccion_pct,
        d.aplica_fines_semana,            d.aplica_festivos,
        d.fecha_vigencia_desde,           d.fecha_vigencia_hasta,
        d.activa,
        i.zona_id,                        i.nombre_politica,
        i.hora_encendido,                 i.hora_apagado,
        i.nivel_lux_umbral,               i.nivel_potencia_reduccion_pct,
        i.aplica_fines_semana,            i.aplica_festivos,
        i.fecha_vigencia_desde,           i.fecha_vigencia_hasta,
        i.activa
    FROM      INSERTED i
    FULL OUTER JOIN DELETED d ON i.politica_id = d.politica_id;

END;
GO


-- ------------------------------------------------------------
-- TR-04  trg_ValidarPoliticaUnicaActiva
--  AFTER INSERT, UPDATE sobre control.PoliticaIluminacion.
--  Garantiza que no existan dos políticas activas con vigencia
--  solapada para la misma zona.
--  Lógica de solapamiento de intervalos [A,B] y [C,D]:
--    se solapan cuando A <= D AND C <= B
--    (NULL en fecha_hasta = política sin fecha de fin definida,
--     se trata como '9999-12-31' para la comparación).
--  En caso de conflicto: ROLLBACK + error descriptivo.
-- ------------------------------------------------------------
IF OBJECT_ID('control.trg_ValidarPoliticaUnicaActiva', 'TR') IS NOT NULL
    DROP TRIGGER control.trg_ValidarPoliticaUnicaActiva;
GO

CREATE TRIGGER control.trg_ValidarPoliticaUnicaActiva
ON control.PoliticaIluminacion
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @zona_conflicto     INT;
    DECLARE @politica_nueva     INT;
    DECLARE @politica_existente INT;
    DECLARE @msg                NVARCHAR(500);

    SELECT TOP 1
        @zona_conflicto     = i.zona_id,
        @politica_nueva     = i.politica_id,
        @politica_existente = p.politica_id
    FROM INSERTED i
    JOIN control.PoliticaIluminacion p
         ON  p.zona_id     = i.zona_id
         AND p.activa      = 1
         AND p.politica_id <> i.politica_id
    WHERE i.activa = 1
      -- Detección de solapamiento temporal
      AND i.fecha_vigencia_desde <= ISNULL(p.fecha_vigencia_hasta, '9999-12-31')
      AND p.fecha_vigencia_desde <= ISNULL(i.fecha_vigencia_hasta, '9999-12-31');

    IF @zona_conflicto IS NOT NULL
    BEGIN
        SET @msg = N'Error de integridad: la zona_id '
                 + CAST(@zona_conflicto AS NVARCHAR)
                 + N' ya tiene una política activa (politica_id: '
                 + CAST(@politica_existente AS NVARCHAR)
                 + N') con vigencia solapada a la política '
                 + CAST(@politica_nueva AS NVARCHAR)
                 + N'. Desactive la política existente antes de activar una nueva.';

        ROLLBACK TRANSACTION;
        RAISERROR(@msg, 16, 1);
    END

END;
GO


-- ------------------------------------------------------------
-- TR-05  trg_ActualizarHorasOperacion
--  AFTER INSERT sobre operativo.ConsumoEnergetico.
--  Incrementa horas_operacion_acumuladas en Luminaria cuando
--  estado_encendido = 1.
--  Procesamiento en lote: agrupa por luminaria_id antes del
--  UPDATE para manejar inserciones masivas del SSIS en un
--  solo DML, minimizando el impacto en la tabla de alto volumen.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.trg_ActualizarHorasOperacion', 'TR') IS NOT NULL
    DROP TRIGGER operativo.trg_ActualizarHorasOperacion;
GO

CREATE TRIGGER operativo.trg_ActualizarHorasOperacion
ON operativo.ConsumoEnergetico
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- UPDATE en lote: una sola sentencia para todas las luminarias
    -- afectadas en el INSERT, incluso si son miles de filas (SSIS).
    UPDATE l
    SET    l.horas_operacion_acumuladas =
               l.horas_operacion_acumuladas + conteo.horas_nuevas
    FROM   maestro.Luminaria l
    JOIN (
        SELECT   luminaria_id,
                 COUNT(*) AS horas_nuevas
        FROM     INSERTED
        WHERE    estado_encendido = 1
        GROUP BY luminaria_id
    ) AS conteo ON l.luminaria_id = conteo.luminaria_id;

END;
GO


-- ============================================================
-- BLOQUE 4 — VISTAS
--  Convención: vw_ + nombre descriptivo.
--  Sin SELECT *: columnas explícitas para evitar que cambios
--  en tablas base rompan silenciosamente las vistas.
--  Cada vista va en el esquema que corresponde al propósito
--  dominante de los datos que expone.
-- ============================================================

-- ------------------------------------------------------------
-- VW-01  vw_ConsumoLuminaria_Completo
--  Interfaz principal del SSIS Flujo 6 para cargar
--  FactConsumoIluminacion en el DW.
--  Desnormaliza tipo de lámpara, estado y zona para eliminar
--  JOINs en el pipeline ETL.
--  Incluye pct_vida_util_consumida como métrica derivada lista
--  para el análisis de modernización en Power BI.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.vw_ConsumoLuminaria_Completo', 'V') IS NOT NULL
    DROP VIEW operativo.vw_ConsumoLuminaria_Completo;
GO

CREATE VIEW operativo.vw_ConsumoLuminaria_Completo
AS
SELECT
    -- Identificadores clave
    ce.consumo_id,
    ce.lectura_id,
    ce.luminaria_id,
    l.sensor_id,
    l.zona_id,
    -- Datos físicos de la luminaria
    l.codigo_poste,
    l.potencia_w                            AS potencia_nominal_w,
    l.altura_poste_m,
    l.fecha_instalacion                     AS luminaria_fecha_instalacion,
    l.horas_operacion_acumuladas,
    -- Tipo de lámpara desnormalizado
    tl.tipo_lampara_id,
    tl.nombre_tipo                          AS tipo_lampara,
    tl.eficiencia_lm_w,
    tl.vida_util_horas,
    -- Estado de la luminaria desnormalizado
    el.estado_luminaria_id,
    el.nombre                               AS estado_luminaria,
    -- Zona desnormalizada
    z.nombre_zona,
    -- Métricas del consumo
    ce.fecha_hora,
    ce.kwh_consumido,
    ce.estado_encendido,
    ce.potencia_activa_w,
    ce.tarifa_cop_kwh,
    ce.costo_cop,
    -- Porcentaje de vida útil consumida (métrica de modernización)
    CASE
        WHEN tl.vida_util_horas > 0
        THEN ROUND(
                 100.0 * l.horas_operacion_acumuladas
                 / tl.vida_util_horas,
             2)
        ELSE NULL
    END                                     AS pct_vida_util_consumida
FROM  operativo.ConsumoEnergetico   ce
JOIN  maestro.Luminaria             l  ON ce.luminaria_id       = l.luminaria_id
JOIN  catalogo.TipoLampara          tl ON l.tipo_lampara_id     = tl.tipo_lampara_id
JOIN  catalogo.EstadoLuminaria      el ON l.estado_luminaria_id = el.estado_luminaria_id
JOIN  maestro.Zona                  z  ON l.zona_id             = z.zona_id;
GO


-- ------------------------------------------------------------
-- VW-02  vw_Sensores_Activos_Por_Zona
--  Lista sensores con estado 'Activo' enriquecidos con zona,
--  tipo, modelo y días desde el último mantenimiento.
--  Vista de trabajo diario de operadores de la red.
--  LEFT JOIN a Luminaria: muestra el sensor aunque no tenga
--  luminaria asignada (posible durante instalación).
-- ------------------------------------------------------------
IF OBJECT_ID('maestro.vw_Sensores_Activos_Por_Zona', 'V') IS NOT NULL
    DROP VIEW maestro.vw_Sensores_Activos_Por_Zona;
GO

CREATE VIEW maestro.vw_Sensores_Activos_Por_Zona
AS
SELECT
    z.zona_id,
    z.nombre_zona,
    z.localidad,
    tz.nombre                               AS tipo_zona,
    s.sensor_id,
    s.codigo_externo,
    ts.nombre_tipo                          AS tipo_sensor,
    ts.modelo                               AS modelo_sensor,
    ts.fabricante,
    ts.precision_pct,
    s.latitud                               AS sensor_latitud,
    s.longitud                              AS sensor_longitud,
    s.fecha_instalacion,
    s.fecha_ultimo_mantenimiento,
    DATEDIFF(
        DAY,
        s.fecha_ultimo_mantenimiento,
        CAST(GETDATE() AS DATE)
    )                                       AS dias_sin_mantenimiento,
    -- Luminaria asociada (puede ser NULL durante alta del sensor)
    l.luminaria_id,
    l.codigo_poste,
    tl.nombre_tipo                          AS tipo_lampara_asociada
FROM  maestro.Sensor            s
JOIN  catalogo.EstadoSensor     es ON s.estado_sensor_id = es.estado_sensor_id
JOIN  catalogo.TipoSensor       ts ON s.tipo_sensor_id   = ts.tipo_sensor_id
JOIN  maestro.Zona              z  ON s.zona_id          = z.zona_id
JOIN  catalogo.TipoZona         tz ON z.tipo_zona_id     = tz.tipo_zona_id
LEFT JOIN maestro.Luminaria     l  ON l.sensor_id        = s.sensor_id
LEFT JOIN catalogo.TipoLampara  tl ON l.tipo_lampara_id  = tl.tipo_lampara_id
WHERE es.nombre = 'Activo';
GO


-- ------------------------------------------------------------
-- VW-03  vw_Anomalias_Abiertas
--  Lista eventos no resueltos (resuelto = 0) con zona, tipo
--  de anomalía, severidad descriptiva y horas transcurridas.
--  Alimenta el panel de mantenimiento predictivo en Power BI
--  y la cola de trabajo de técnicos de campo.
-- ------------------------------------------------------------
IF OBJECT_ID('operativo.vw_Anomalias_Abiertas', 'V') IS NOT NULL
    DROP VIEW operativo.vw_Anomalias_Abiertas;
GO

CREATE VIEW operativo.vw_Anomalias_Abiertas
AS
SELECT
    ea.evento_id,
    ea.luminaria_id,
    l.codigo_poste,
    z.zona_id,
    z.nombre_zona,
    z.localidad,
    ta.tipo_anomalia_id,
    ta.nombre                               AS tipo_anomalia,
    ta.nivel_severidad,
    CASE ta.nivel_severidad
        WHEN 1 THEN 'Informativo'
        WHEN 2 THEN 'Leve'
        WHEN 3 THEN 'Moderado'
        WHEN 4 THEN 'Crítico'
    END                                     AS descripcion_severidad,
    ea.fecha_hora                           AS fecha_deteccion,
    DATEDIFF(HOUR, ea.fecha_hora, GETDATE()) AS horas_abierto,
    ea.descripcion                          AS detalle_evento,
    ea.lectura_id,
    tl.nombre_tipo                          AS tipo_lampara,
    el.nombre                               AS estado_actual_luminaria
FROM  operativo.EventoAnomalia  ea
JOIN  maestro.Luminaria         l  ON ea.luminaria_id       = l.luminaria_id
JOIN  maestro.Zona              z  ON l.zona_id             = z.zona_id
JOIN  catalogo.TipoAnomalia     ta ON ea.tipo_anomalia_id   = ta.tipo_anomalia_id
JOIN  catalogo.TipoLampara      tl ON l.tipo_lampara_id     = tl.tipo_lampara_id
JOIN  catalogo.EstadoLuminaria  el ON l.estado_luminaria_id = el.estado_luminaria_id
WHERE ea.resuelto = 0;
GO


-- ------------------------------------------------------------
-- VW-04  vw_InventarioLuminarias_Estado
--  Inventario agrupado por zona y tipo de lámpara con conteo
--  por estado, porcentaje de operatividad y métricas de
--  vida útil (promedio, máximo, luminarias con vida vencida).
--  Base para planificar el programa de sustitución LED y
--  calcular el presupuesto de modernización por localidad.
-- ------------------------------------------------------------
IF OBJECT_ID('maestro.vw_InventarioLuminarias_Estado', 'V') IS NOT NULL
    DROP VIEW maestro.vw_InventarioLuminarias_Estado;
GO

CREATE VIEW maestro.vw_InventarioLuminarias_Estado
AS
SELECT
    z.zona_id,
    z.nombre_zona,
    z.localidad,
    tl.tipo_lampara_id,
    tl.nombre_tipo                              AS tipo_lampara,
    tl.vida_util_horas,
    -- Conteo total y por estado
    COUNT(l.luminaria_id)                       AS total_luminarias,
    SUM(CASE WHEN el.nombre = 'Operativa'    THEN 1 ELSE 0 END) AS total_operativas,
    SUM(CASE WHEN el.nombre = 'Averiada'     THEN 1 ELSE 0 END) AS total_averiadas,
    SUM(CASE WHEN el.nombre = 'En reemplazo' THEN 1 ELSE 0 END) AS total_en_reemplazo,
    SUM(CASE WHEN el.nombre = 'Dada de baja' THEN 1 ELSE 0 END) AS total_dadas_de_baja,
    -- Porcentaje de operatividad del grupo
    ROUND(
        100.0 * SUM(CASE WHEN el.nombre = 'Operativa' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(l.luminaria_id), 0),
    2)                                          AS pct_operatividad,
    -- Métricas de vida útil
    AVG(l.horas_operacion_acumuladas)           AS promedio_horas_acumuladas,
    MAX(l.horas_operacion_acumuladas)           AS max_horas_acumuladas,
    ROUND(
        100.0 * AVG(l.horas_operacion_acumuladas)
        / NULLIF(tl.vida_util_horas, 0),
    2)                                          AS pct_vida_util_consumida_promedio,
    -- Luminarias que ya superaron su vida útil estimada
    SUM(CASE
        WHEN tl.vida_util_horas > 0
         AND l.horas_operacion_acumuladas >= tl.vida_util_horas
        THEN 1 ELSE 0
    END)                                        AS luminarias_vida_util_vencida
FROM  maestro.Luminaria        l
JOIN  maestro.Zona             z  ON l.zona_id             = z.zona_id
JOIN  catalogo.TipoLampara     tl ON l.tipo_lampara_id     = tl.tipo_lampara_id
JOIN  catalogo.EstadoLuminaria el ON l.estado_luminaria_id = el.estado_luminaria_id
GROUP BY
    z.zona_id,
    z.nombre_zona,
    z.localidad,
    tl.tipo_lampara_id,
    tl.nombre_tipo,
    tl.vida_util_horas;
GO


-- ============================================================
-- BLOQUE 5 — VERIFICACIÓN POST-INSTALACIÓN
-- ============================================================

SELECT
    o.type_desc                 AS tipo_objeto,
    s.name                      AS esquema,
    o.name                      AS nombre_objeto,
    o.create_date               AS fecha_creacion
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type IN ('U','P','TR','V')
  AND s.name   IN ('catalogo','maestro','operativo','control')
  AND o.name   IN (
      -- Tablas de auditoría
      'AuditSensor','AuditLuminaria','AuditPolitica',
      -- Stored procedures
      'usp_InsertarLecturaAmbiente','usp_InsertarConsumoEnergetico',
      'usp_RegistrarEventoAnomalia','usp_ResolverEventoAnomalia',
      'usp_ActualizarEstadoSensor',
      'usp_ObtenerLecturasPorSensorYRango','usp_ObtenerResumenConsumoZona',
      -- Triggers
      'trg_Audit_Sensor_IUD','trg_Audit_Luminaria_IUD',
      'trg_Audit_PoliticaIluminacion_IUD',
      'trg_ValidarPoliticaUnicaActiva','trg_ActualizarHorasOperacion',
      -- Vistas
      'vw_ConsumoLuminaria_Completo','vw_Sensores_Activos_Por_Zona',
      'vw_Anomalias_Abiertas','vw_InventarioLuminarias_Estado'
  )
ORDER BY
    CASE o.type_desc
        WHEN 'USER_TABLE'           THEN 1
        WHEN 'SQL_STORED_PROCEDURE' THEN 2
        WHEN 'SQL_TRIGGER'          THEN 3
        WHEN 'VIEW'                 THEN 4
    END,
    s.name,
    o.name;
GO

-- ============================================================
-- FIN DEL SCRIPT
-- ============================================================
-- Objetos creados (19 total):
--
--  TABLAS DE AUDITORÍA (3)
--    control.AuditSensor
--    control.AuditLuminaria
--    control.AuditPolitica
--
--  STORED PROCEDURES (7)
--    operativo.usp_InsertarLecturaAmbiente
--    operativo.usp_InsertarConsumoEnergetico
--    operativo.usp_RegistrarEventoAnomalia
--    operativo.usp_ResolverEventoAnomalia
--    maestro.usp_ActualizarEstadoSensor
--    operativo.usp_ObtenerLecturasPorSensorYRango
--    operativo.usp_ObtenerResumenConsumoZona
--
--  TRIGGERS (5)
--    maestro.trg_Audit_Sensor_IUD
--    maestro.trg_Audit_Luminaria_IUD
--    control.trg_Audit_PoliticaIluminacion_IUD
--    control.trg_ValidarPoliticaUnicaActiva
--    operativo.trg_ActualizarHorasOperacion
--
--  VISTAS (4)
--    operativo.vw_ConsumoLuminaria_Completo
--    maestro.vw_Sensores_Activos_Por_Zona
--    operativo.vw_Anomalias_Abiertas
--    maestro.vw_InventarioLuminarias_Estado
-- ============================================================
