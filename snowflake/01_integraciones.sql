/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   01_integraciones.sql   —   Ejecutar en Snowsight con rol ACCOUNTADMIN
   ---------------------------------------------------------------------
   Conecta Snowflake con los tres contenedores del lake stdwtottusjc:
     - AZ_BRONZE_INT  (storage integration): LEER los Parquet de bronze
     - EV_SILVER      (external volume):     ESCRIBIR Iceberg en silver
     - EV_GOLD        (external volume):     ESCRIBIR Iceberg en gold
   Dos volúmenes distintos = capas separadas físicamente.

   Después de ejecutar, la PARTE 2 muestra las URL de consentimiento y
   el nombre de la aplicación de Snowflake que hay que autorizar en Azure
   (ver snowflake/asignar_permisos_azure.sh).
   ===================================================================== */
USE ROLE ACCOUNTADMIN;

/* ---------------------------- PARTE 1 ------------------------------ */

CREATE STORAGE INTEGRATION IF NOT EXISTS AZ_BRONZE_INT
  TYPE                      = EXTERNAL_STAGE
  STORAGE_PROVIDER          = 'AZURE'
  ENABLED                   = TRUE
  AZURE_TENANT_ID           = '82d43218-95ae-4c58-90b0-c3e1d9c40e57'
  STORAGE_ALLOWED_LOCATIONS = ('azure://stdwtottusjc.blob.core.windows.net/bronze/')
  COMMENT                   = 'Lectura de la capa Bronze (Parquet de ADF)';

CREATE EXTERNAL VOLUME IF NOT EXISTS EV_SILVER
  STORAGE_LOCATIONS = ((
    NAME             = 'silver_southcentralus'
    STORAGE_PROVIDER = 'AZURE'
    STORAGE_BASE_URL = 'azure://stdwtottusjc.blob.core.windows.net/silver/'
    AZURE_TENANT_ID  = '82d43218-95ae-4c58-90b0-c3e1d9c40e57'
  ))
  ALLOW_WRITES = TRUE
  COMMENT      = 'Capa Silver: tablas Iceberg en el contenedor silver';

CREATE EXTERNAL VOLUME IF NOT EXISTS EV_GOLD
  STORAGE_LOCATIONS = ((
    NAME             = 'gold_southcentralus'
    STORAGE_PROVIDER = 'AZURE'
    STORAGE_BASE_URL = 'azure://stdwtottusjc.blob.core.windows.net/gold/'
    AZURE_TENANT_ID  = '82d43218-95ae-4c58-90b0-c3e1d9c40e57'
  ))
  ALLOW_WRITES = TRUE
  COMMENT      = 'Capa Gold: tablas Iceberg en el contenedor gold';

/* ---------------------------- PARTE 2 ------------------------------
   Datos para el consentimiento. Ejecuta cada par de sentencias
   (DESC + SELECT) juntas: el SELECT lee el resultado del DESC anterior.
   ------------------------------------------------------------------- */

-- a) Storage integration (bronze)
DESC STORAGE INTEGRATION AZ_BRONZE_INT;
SELECT "property", "property_value"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "property" IN ('AZURE_CONSENT_URL', 'AZURE_MULTI_TENANT_APP_NAME');

-- b) External volume silver
DESC EXTERNAL VOLUME EV_SILVER;
SELECT PARSE_JSON("property_value"):AZURE_CONSENT_URL::STRING           AS consent_url,
       PARSE_JSON("property_value"):AZURE_MULTI_TENANT_APP_NAME::STRING AS app_name
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "property" = 'STORAGE_LOCATION_1';

-- c) External volume gold
DESC EXTERNAL VOLUME EV_GOLD;
SELECT PARSE_JSON("property_value"):AZURE_CONSENT_URL::STRING           AS consent_url,
       PARSE_JSON("property_value"):AZURE_MULTI_TENANT_APP_NAME::STRING AS app_name
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "property" = 'STORAGE_LOCATION_1';

/* Normalmente las tres consultas devuelven la MISMA aplicación
   (mismo tenant). Abre la(s) URL de consentimiento, acepta, y luego
   ejecuta snowflake/asignar_permisos_azure.sh con el app_name.        */

/* ---------------------------- PARTE 3 ------------------------------
   Verificación (después de asignar los permisos en Azure y esperar
   5-10 minutos). Deben responder con "success": true.
   ------------------------------------------------------------------- */
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('EV_SILVER');
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('EV_GOLD');
