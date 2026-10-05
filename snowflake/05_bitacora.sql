/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   05_bitacora.sql   —   Auditoría de corridas del pipeline
   ---------------------------------------------------------------------
   ADF registra el inicio y el fin (OK / ERROR) de cada corrida.
   La vista V_CORRIDAS calcula la duración de punta a punta:
   evidencia de "rendimiento observado" para el Proyecto 6.
   Ejecutar con ROL_ORQ.
   ===================================================================== */
USE ROLE ROL_ORQ;
USE WAREHOUSE WH_TOTTUS;
USE SCHEMA OPS_DB.ADMIN;

CREATE TABLE IF NOT EXISTS OPS_DB.ADMIN.LOG_CORRIDAS (
    carga_id        VARCHAR       NOT NULL,
    adf_run_id      VARCHAR,
    estado          VARCHAR       NOT NULL,      -- INICIADA | OK | ERROR
    detalle         VARCHAR,
    registrado_en   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    usuario         VARCHAR       DEFAULT CURRENT_USER(),
    rol             VARCHAR       DEFAULT CURRENT_ROLE()
)
COMMENT = 'Bitácora de corridas de pl_p4_full (ADF)';

CREATE OR REPLACE PROCEDURE OPS_DB.ADMIN.SP_REGISTRAR_CORRIDA(
    CARGA_ID VARCHAR, ADF_RUN_ID VARCHAR, ESTADO VARCHAR, DETALLE VARCHAR DEFAULT NULL)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
  INSERT INTO OPS_DB.ADMIN.LOG_CORRIDAS (carga_id, adf_run_id, estado, detalle)
  VALUES (:carga_id, :adf_run_id, UPPER(:estado), :detalle);
  RETURN 'Registrado ' || estado || ' para ' || carga_id;
END;
$$;

CREATE OR REPLACE VIEW OPS_DB.ADMIN.V_CORRIDAS AS
SELECT
    carga_id,
    ANY_VALUE(adf_run_id)                                                AS adf_run_id,
    MIN(IFF(estado = 'INICIADA', registrado_en, NULL))                   AS inicio,
    MAX(IFF(estado IN ('OK', 'ERROR'), registrado_en, NULL))             AS fin,
    MAX(IFF(estado IN ('OK', 'ERROR'), estado, NULL))                    AS resultado,
    DATEDIFF(second,
             MIN(IFF(estado = 'INICIADA', registrado_en, NULL)),
             MAX(IFF(estado IN ('OK', 'ERROR'), registrado_en, NULL)))   AS duracion_seg
FROM OPS_DB.ADMIN.LOG_CORRIDAS
GROUP BY carga_id;

-- Prueba manual
CALL OPS_DB.ADMIN.SP_REGISTRAR_CORRIDA('prueba_manual', NULL, 'INICIADA');
CALL OPS_DB.ADMIN.SP_REGISTRAR_CORRIDA('prueba_manual', NULL, 'OK', 'registro de prueba');
SELECT * FROM OPS_DB.ADMIN.V_CORRIDAS ORDER BY inicio DESC;
DELETE FROM OPS_DB.ADMIN.LOG_CORRIDAS WHERE carga_id = 'prueba_manual';
