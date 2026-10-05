/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   prueba_humo_iceberg.sql   —   EL HITO MÁS IMPORTANTE DE LA SEMANA
   ---------------------------------------------------------------------
   Confirma que Snowflake puede ESCRIBIR tablas Iceberg en los
   contenedores silver y gold (capas separadas físicamente) usando el
   rol con el que trabajará dbt.
   Requisitos: 01_integraciones.sql (con consentimiento y permisos en
   Azure) y 02_grants.sql.
   ===================================================================== */

/* 1) Verificar los volúmenes (ACCOUNTADMIN) --------------------------- */
USE ROLE ACCOUNTADMIN;
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('EV_SILVER') AS verificacion_silver;
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('EV_GOLD')   AS verificacion_gold;
-- Ambos deben contener "success":true. Si dicen 403/AuthorizationPermissionMismatch,
-- revisa asignar_permisos_azure.sh y espera 5-10 minutos.

/* 2) Escribir con el rol de dbt --------------------------------------- */
USE ROLE ROL_DBT;
USE WAREHOUSE WH_TOTTUS;

CREATE OR REPLACE ICEBERG TABLE SILVER_DB.STAGING.PRUEBA_HUMO (
    id      INT,
    detalle STRING,
    ts      TIMESTAMP_NTZ(6)                -- Iceberg exige precisión 6
)
  CATALOG         = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'EV_SILVER'
  BASE_LOCATION   = 'prueba_humo';

INSERT INTO SILVER_DB.STAGING.PRUEBA_HUMO
SELECT 1, 'silver ok', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6);

CREATE OR REPLACE ICEBERG TABLE GOLD_DB.MARTS.PRUEBA_HUMO (
    id      INT,
    detalle STRING,
    ts      TIMESTAMP_NTZ(6)
)
  CATALOG         = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'EV_GOLD'
  BASE_LOCATION   = 'prueba_humo';

INSERT INTO GOLD_DB.MARTS.PRUEBA_HUMO
SELECT 1, 'gold ok', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6);

/* 3) Leer ------------------------------------------------------------- */
SELECT 'SILVER' AS capa, * FROM SILVER_DB.STAGING.PRUEBA_HUMO
UNION ALL
SELECT 'GOLD',           * FROM GOLD_DB.MARTS.PRUEBA_HUMO;

/* 4) Comprobar en Azure (Git Bash) — deben aparecer data/ y metadata/:
      az storage blob list --account-name stdwtottusjc -c silver --auth-mode login --query "[].name" -o tsv
      az storage blob list --account-name stdwtottusjc -c gold   --auth-mode login --query "[].name" -o tsv
      ¡Guarda una captura! Es la evidencia de la separación física de capas.   */

/* 5) Limpiar (después de la captura) ---------------------------------- */
-- DROP ICEBERG TABLE SILVER_DB.STAGING.PRUEBA_HUMO;
-- DROP ICEBERG TABLE GOLD_DB.MARTS.PRUEBA_HUMO;
