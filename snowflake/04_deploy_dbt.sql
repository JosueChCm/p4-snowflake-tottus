/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   04_deploy_dbt.sql   —   dbt en la NUBE (dbt Projects on Snowflake)
   ---------------------------------------------------------------------
   Snowflake lee el proyecto dbt desde la rama main de GitHub y lo
   ejecuta dentro de Snowflake. ADF solo tendrá que hacer:
        CALL OPS_DB.ADMIN.SP_EJECUTAR_DBT();
   Antes de ejecutar: reemplaza <TU_USUARIO_GITHUB> (2 lugares).
   El repositorio debe ser PÚBLICO (no se usa token).
   ===================================================================== */

/* 1) Integración con GitHub (ACCOUNTADMIN) ---------------------------- */
USE ROLE ACCOUNTADMIN;

CREATE API INTEGRATION IF NOT EXISTS GIT_API_INT
  API_PROVIDER         = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/JosueChCm')
  ENABLED              = TRUE
  COMMENT              = 'Lectura del repositorio público del Proyecto 4';

GRANT USAGE ON INTEGRATION GIT_API_INT TO ROLE ROL_ORQ;

/* 2) Repositorio Git dentro de Snowflake (ROL_ORQ) ---------------------- */
USE ROLE ROL_ORQ;
USE WAREHOUSE WH_TOTTUS;
USE SCHEMA OPS_DB.ADMIN;

CREATE GIT REPOSITORY IF NOT EXISTS OPS_DB.ADMIN.REPO_P4
  API_INTEGRATION = GIT_API_INT
  ORIGIN          = 'https://github.com/JosueChCm/p4-snowflake-tottus.git'
  COMMENT         = 'Código del proyecto (rama main)';

ALTER GIT REPOSITORY OPS_DB.ADMIN.REPO_P4 FETCH;

-- Debe listar dbt_project.yml, profiles.yml, models/, snapshots/...
LS @OPS_DB.ADMIN.REPO_P4/branches/main/dbt_tottus/;

/* 3) Proyecto dbt + primera ejecución manual ---------------------------- */
CREATE OR REPLACE DBT PROJECT OPS_DB.ADMIN.DBT_TOTTUS
  FROM '@OPS_DB.ADMIN.REPO_P4/branches/main/dbt_tottus'
  COMMENT = 'Proyecto dbt Tottus (Silver, snapshots SCD2, Gold)';

EXECUTE DBT PROJECT OPS_DB.ADMIN.DBT_TOTTUS ARGS = 'build --target prod';

/* 4) Procedimiento que usará ADF ---------------------------------------
   - Trae la última versión de main (los cambios se despliegan solos)
   - Recrea el objeto DBT PROJECT con esa versión
   - Ejecuta "dbt build --target prod"
   - Si dbt informa fallo, lanza una excepción -> ADF marca la actividad
     en rojo (EXECUTE DBT PROJECT por sí solo podría no fallar).
   ----------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE OPS_DB.ADMIN.SP_EJECUTAR_DBT(DBT_ARGS VARCHAR DEFAULT 'build --target prod')
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  resultado VARIANT;
  exito     BOOLEAN;
  error_dbt EXCEPTION (-20001, 'dbt terminó con errores: revisar STDOUT en Query History');
BEGIN
  ALTER GIT REPOSITORY OPS_DB.ADMIN.REPO_P4 FETCH;

  EXECUTE IMMEDIATE
    'CREATE OR REPLACE DBT PROJECT OPS_DB.ADMIN.DBT_TOTTUS ' ||
    'FROM ''@OPS_DB.ADMIN.REPO_P4/branches/main/dbt_tottus''';

  EXECUTE IMMEDIATE 'EXECUTE DBT PROJECT OPS_DB.ADMIN.DBT_TOTTUS ARGS = ''' || dbt_args || '''';

  SELECT OBJECT_CONSTRUCT(*) INTO :resultado
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    LIMIT 1;

  exito := COALESCE(resultado:SUCCESS::BOOLEAN, resultado:success::BOOLEAN, TRUE);
  IF (NOT exito) THEN
    RAISE error_dbt;
  END IF;

  RETURN 'dbt OK: ' || dbt_args;
END;
$$;

-- Prueba (tarda unos minutos: snapshots + 23 modelos + tests)
CALL OPS_DB.ADMIN.SP_EJECUTAR_DBT();

/* Si algo falla:
   - "DBT PROJECT" no reconocido -> la función no está habilitada en la
     cuenta: avisar (plan B = contenedor dbt en Azure Container Instances).
   - Errores de modelos/tests -> Monitoring > Query History > abrir la
     consulta EXECUTE DBT PROJECT y revisar la columna STDOUT.            */
