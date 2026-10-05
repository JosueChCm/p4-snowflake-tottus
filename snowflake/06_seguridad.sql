/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   06_seguridad.sql   —   Privacidad, acceso y auditoría
   ---------------------------------------------------------------------
   1. Masking policy para datos personales (DNI) en Gold
      -> la aplica dbt en cada corrida (post-hook de dim_cliente)
   2. Pruebas: el mismo dato visto con distintos roles
   3. Auditoría: quién consultó qué (ACCOUNT_USAGE, edición Enterprise)
   Marco normativo: Ley N.° 29733 de Protección de Datos Personales.
   EJECUTAR LA PARTE 1 ANTES de la siguiente corrida de dbt.
   ===================================================================== */

/* 1) Política de enmascaramiento (ACCOUNTADMIN) ----------------------- */
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_TOTTUS;

CREATE MASKING POLICY IF NOT EXISTS GOLD_DB.MARTS.MP_DATO_PERSONAL
  AS (val STRING) RETURNS STRING ->
  CASE
    WHEN val IS NULL                   THEN NULL
    WHEN IS_ROLE_IN_SESSION('ROL_DBT') THEN val            -- transformación: ve el dato real
    ELSE REPEAT('*', GREATEST(LENGTH(val) - 2, 0)) || RIGHT(val, 2)   -- resto: ******34
  END
  COMMENT = 'Ley 29733: DNI y documentos solo visibles para roles de transformación';

-- dbt (ROL_DBT / ROL_ORQ) puede aplicarla en cada corrida
GRANT APPLY ON MASKING POLICY GOLD_DB.MARTS.MP_DATO_PERSONAL TO ROLE ROL_DBT;

/* 2) Pruebas (después de una corrida de dbt) --------------------------- */

-- a) La política está aplicada a la columna
SELECT policy_name, ref_entity_name, ref_column_name
FROM TABLE(GOLD_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
       REF_ENTITY_NAME   => 'GOLD_DB.MARTS.DIM_CLIENTE',
       REF_ENTITY_DOMAIN => 'table'));

-- b) Rol de transformación: dato real
USE ROLE ROL_DBT;
SELECT id_cliente, nombres, num_documento FROM GOLD_DB.MARTS.DIM_CLIENTE WHERE id_cliente IS NOT NULL LIMIT 5;

-- c) Rol de Power BI: dato enmascarado
USE ROLE ROL_POWERBI;
SELECT id_cliente, nombres, num_documento FROM GOLD_DB.MARTS.DIM_CLIENTE WHERE id_cliente IS NOT NULL LIMIT 5;

-- d) Rol de Power BI: sin acceso a capas inferiores (debe FALLAR)
SELECT * FROM BRONZE_DB.RAW.CLIENTES LIMIT 1;
SELECT * FROM SILVER_DB.STAGING.STG_CLIENTES LIMIT 1;

/* 3) Auditoría (ACCOUNTADMIN). ACCOUNT_USAGE tiene latencia de 45 min a 3 h */
USE ROLE ACCOUNTADMIN;

-- Quién accedió a la tabla de clientes de Gold y cuándo
SELECT ah.query_start_time, ah.user_name, obj.value:"objectName"::STRING AS objeto
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
     LATERAL FLATTEN(input => ah.base_objects_accessed) obj
WHERE obj.value:"objectName"::STRING ILIKE 'GOLD_DB.MARTS.DIM_CLIENTE'
ORDER BY ah.query_start_time DESC
LIMIT 50;

-- Consultas por usuario y rol (últimos 7 días)
SELECT user_name, role_name, COUNT(*) AS consultas, SUM(total_elapsed_time) / 1000 AS segundos
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY user_name, role_name
ORDER BY consultas DESC;

-- Inicios de sesión (incluye usuarios de servicio SVC_ADF y SVC_PBI)
SELECT event_timestamp, user_name, client_ip, reported_client_type, first_authentication_factor, is_success
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
ORDER BY event_timestamp DESC
LIMIT 50;

-- Consumo de créditos del warehouse (control de costos)
SELECT DATE_TRUNC('day', start_time) AS dia, SUM(credits_used) AS creditos
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'WH_TOTTUS'
GROUP BY 1 ORDER BY 1 DESC;
