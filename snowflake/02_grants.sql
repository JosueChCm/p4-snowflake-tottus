/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   02_grants.sql   —   Ejecutar en Snowsight con rol ACCOUNTADMIN
   ---------------------------------------------------------------------
   Requisitos: terraform apply de infra/snowflake y 01_integraciones.sql.
   Separación de capas por PERMISOS (mínimo privilegio):

     ROL_INGESTA  -> escribe BRONZE_DB.RAW, lee el contenedor bronze
     ROL_DBT      -> lee BRONZE, escribe SILVER, GOLD y DEV_DB (Iceberg)
     ROL_ORQ      -> ROL_INGESTA + ROL_DBT + OPS_DB (lo usa Data Factory)
     ROL_POWERBI  -> SOLO lectura de GOLD_DB.MARTS

   Antes de ejecutar, reemplaza los 2 valores marcados con <== :
     1) Llave pública de ADF (sección 6)
     2) Contraseña de SVC_PBI (sección 6)
   ===================================================================== */
USE ROLE ACCOUNTADMIN;

/* 1) Warehouse ------------------------------------------------------- */
GRANT USAGE, OPERATE ON WAREHOUSE WH_TOTTUS TO ROLE ROL_INGESTA;
GRANT USAGE, OPERATE ON WAREHOUSE WH_TOTTUS TO ROLE ROL_DBT;
GRANT USAGE          ON WAREHOUSE WH_TOTTUS TO ROLE ROL_POWERBI;

/* 2) BRONZE: solo la ingesta escribe -------------------------------- */
GRANT USAGE ON DATABASE BRONZE_DB                 TO ROLE ROL_INGESTA;
GRANT ALL   ON SCHEMA   BRONZE_DB.RAW             TO ROLE ROL_INGESTA;
GRANT ALL   ON ALL TABLES    IN SCHEMA BRONZE_DB.RAW TO ROLE ROL_INGESTA;
GRANT ALL   ON FUTURE TABLES IN SCHEMA BRONZE_DB.RAW TO ROLE ROL_INGESTA;
GRANT USAGE ON INTEGRATION AZ_BRONZE_INT          TO ROLE ROL_INGESTA;

/* 3) dbt: lee BRONZE ------------------------------------------------- */
GRANT USAGE  ON DATABASE BRONZE_DB                    TO ROLE ROL_DBT;
GRANT USAGE  ON SCHEMA   BRONZE_DB.RAW                TO ROLE ROL_DBT;
GRANT SELECT ON ALL TABLES    IN SCHEMA BRONZE_DB.RAW TO ROLE ROL_DBT;
GRANT SELECT ON FUTURE TABLES IN SCHEMA BRONZE_DB.RAW TO ROLE ROL_DBT;

/* 4) dbt: escribe SILVER, GOLD (Iceberg) y DEV_DB -------------------- */
GRANT USAGE ON DATABASE SILVER_DB             TO ROLE ROL_DBT;
GRANT USAGE ON DATABASE GOLD_DB               TO ROLE ROL_DBT;
GRANT ALL   ON SCHEMA SILVER_DB.STAGING       TO ROLE ROL_DBT;
GRANT ALL   ON SCHEMA SILVER_DB.SNAPSHOTS     TO ROLE ROL_DBT;
GRANT ALL   ON SCHEMA GOLD_DB.MARTS           TO ROLE ROL_DBT;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_DB TO ROLE ROL_DBT;
GRANT USAGE ON EXTERNAL VOLUME EV_SILVER      TO ROLE ROL_DBT;
GRANT USAGE ON EXTERNAL VOLUME EV_GOLD        TO ROLE ROL_DBT;
GRANT APPLY MASKING POLICY ON ACCOUNT         TO ROLE ROL_DBT;

/* 5) POWER BI: solo lectura de GOLD ----------------------------------
      Los grants FUTURE alcanzan las tablas que dbt recrea en cada corrida */
GRANT USAGE  ON DATABASE GOLD_DB                               TO ROLE ROL_POWERBI;
GRANT USAGE  ON SCHEMA   GOLD_DB.MARTS                         TO ROLE ROL_POWERBI;
GRANT SELECT ON FUTURE TABLES         IN SCHEMA GOLD_DB.MARTS  TO ROLE ROL_POWERBI;
GRANT SELECT ON FUTURE ICEBERG TABLES IN SCHEMA GOLD_DB.MARTS  TO ROLE ROL_POWERBI;
GRANT SELECT ON FUTURE VIEWS          IN SCHEMA GOLD_DB.MARTS  TO ROLE ROL_POWERBI;

/* 6) ORQUESTADOR: objetos de despliegue en OPS_DB --------------------
      (ROL_ORQ ya hereda ROL_INGESTA y ROL_DBT por Terraform)           */
GRANT USAGE ON DATABASE OPS_DB     TO ROLE ROL_ORQ;
GRANT ALL   ON SCHEMA   OPS_DB.ADMIN TO ROLE ROL_ORQ;

/* 7) Usuarios de servicio -------------------------------------------- */

-- Data Factory: llave RSA (contenido de ~/.snowflake/adf_key.pub en UNA línea,
-- sin BEGIN/END). Obtenerla con:
--   grep -v "PUBLIC KEY" ~/.snowflake/adf_key.pub | tr -d '\n'; echo
CREATE USER IF NOT EXISTS SVC_ADF
  TYPE              = SERVICE
  DEFAULT_ROLE      = ROL_ORQ
  DEFAULT_WAREHOUSE = WH_TOTTUS
  RSA_PUBLIC_KEY    = 'PEGAR_AQUI_LA_LLAVE_PUBLICA_DE_ADF'          -- <== 1
  COMMENT           = 'Usuario técnico de Azure Data Factory';
GRANT ROLE ROL_ORQ TO USER SVC_ADF;

-- Power BI: usuario de servicio con contraseña (solo lectura de GOLD)
CREATE USER IF NOT EXISTS SVC_PBI
  TYPE                 = LEGACY_SERVICE
  PASSWORD             = 'Cambiar-Por-Una-Clave-Larga-2026'          -- <== 2
  DEFAULT_ROLE         = ROL_POWERBI
  DEFAULT_WAREHOUSE    = WH_TOTTUS
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT              = 'Usuario técnico de Power BI (DirectQuery)';
GRANT ROLE ROL_POWERBI TO USER SVC_PBI;

/* Si SVC_PBI falla porque la cuenta no admite TYPE = LEGACY_SERVICE,
   omítelo por ahora; en la Fase 11 se conecta Power BI con JOSUECH y
   rol ROL_POWERBI, o se configura SSO.                                 */

/* 8) Tu usuario -------------------------------------------------------- */
ALTER USER JOSUECH SET DEFAULT_WAREHOUSE = WH_TOTTUS;

/* 9) Verificación ------------------------------------------------------ */
SHOW GRANTS TO ROLE ROL_INGESTA;
SHOW GRANTS TO ROLE ROL_DBT;
SHOW GRANTS TO ROLE ROL_POWERBI;
SHOW GRANTS TO ROLE ROL_ORQ;
DESC USER SVC_ADF;      -- HAS_KEYPAIR = true
