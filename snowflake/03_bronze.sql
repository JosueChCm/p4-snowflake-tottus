/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   03_bronze.sql   —   Ejecutar en Snowsight con rol ROL_INGESTA
   ---------------------------------------------------------------------
   Capa BRONZE en Snowflake:
     1. Formato Parquet y stage hacia el contenedor bronze
     2. SP_CREAR_TABLAS_BRONZE(): crea las 15 tablas infiriendo el
        esquema de la carga MÁS RECIENTE (una sola vez)
     3. SP_CARGAR_BRONZE(carga_id): CARGA COMPLETA = TRUNCATE + COPY INTO
        - Sin argumento: detecta sola la carpeta carga=… más reciente
        - Con argumento: carga esa corrida (lo usará ADF en la Fase 10)
   Cada tabla recibe dos columnas de auditoría:
     _LOAD_TS      momento de la carga
     _SOURCE_FILE  archivo Parquet de origen
   Requisitos: 01_integraciones.sql + permisos en Azure, 02_grants.sql
   y al menos una corrida completa de pl_ingesta_bronze en ADF.
   ===================================================================== */
USE ROLE ROL_INGESTA;
USE WAREHOUSE WH_TOTTUS;
USE SCHEMA BRONZE_DB.RAW;

/* 1) Formato y stage --------------------------------------------------- */
CREATE FILE FORMAT IF NOT EXISTS BRONZE_DB.RAW.FF_PARQUET
  TYPE    = PARQUET
  COMMENT = 'Parquet (snappy) generado por ADF';

CREATE STAGE IF NOT EXISTS BRONZE_DB.RAW.STG_BRONZE
  URL                 = 'azure://stdwtottusjc.blob.core.windows.net/bronze/'
  STORAGE_INTEGRATION = AZ_BRONZE_INT
  FILE_FORMAT         = BRONZE_DB.RAW.FF_PARQUET
  COMMENT             = 'Contenedor bronze del lake stdwtottusjc';

-- Debe listar los 15 Parquet de cada corrida
LIST @BRONZE_DB.RAW.STG_BRONZE;

/* 2) Crear las 15 tablas (inferencia de esquema) ----------------------- */
CREATE OR REPLACE PROCEDURE BRONZE_DB.RAW.SP_CREAR_TABLAS_BRONZE()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  tablas ARRAY DEFAULT ARRAY_CONSTRUCT(
    'CATEGORIAS','SUBCATEGORIAS','MARCAS','PROVEEDORES','PRODUCTOS',
    'FORMATOS_TIENDA','SUCURSALES','EMPLEADOS','CLIENTES','METODOS_PAGO',
    'VENTAS','DETALLE_VENTA','COMPRAS_PROVEEDOR','DETALLE_COMPRA','DEVOLUCIONES');
  carga  STRING;
  t      STRING;
  ruta   STRING;
BEGIN
  -- Carpeta carga=… más reciente (los nombres yyyyMMdd_HHmmss ordenan cronológicamente)
  EXECUTE IMMEDIATE 'LIST @BRONZE_DB.RAW.STG_BRONZE PATTERN = ''.*carga=[0-9_]+/.*[.]parquet''';
  SELECT MAX(REGEXP_SUBSTR("name", 'carga=([0-9_]+)', 1, 1, 'e', 1))
    INTO :carga
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

  IF (carga IS NULL) THEN
    RETURN 'ERROR: no hay archivos carga=… en el contenedor bronze. Ejecuta primero pl_ingesta_bronze.';
  END IF;

  FOR i IN 0 TO ARRAY_SIZE(tablas) - 1 DO
    t    := tablas[i]::STRING;
    ruta := '@BRONZE_DB.RAW.STG_BRONZE/' || LOWER(t) || '/carga=' || carga || '/';

    EXECUTE IMMEDIATE
         'CREATE TABLE IF NOT EXISTS BRONZE_DB.RAW.' || t || ' USING TEMPLATE ('
      || ' SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*)) WITHIN GROUP (ORDER BY ORDER_ID)'
      || ' FROM TABLE(INFER_SCHEMA('
      || '   LOCATION    => ''' || ruta || ''','
      || '   FILE_FORMAT => ''BRONZE_DB.RAW.FF_PARQUET'','
      || '   IGNORE_CASE => TRUE)))';

    EXECUTE IMMEDIATE 'ALTER TABLE BRONZE_DB.RAW.' || t || ' ADD COLUMN IF NOT EXISTS _LOAD_TS TIMESTAMP_LTZ';
    EXECUTE IMMEDIATE 'ALTER TABLE BRONZE_DB.RAW.' || t || ' ADD COLUMN IF NOT EXISTS _SOURCE_FILE STRING';
  END FOR;

  RETURN '15 tablas Bronze listas (esquema inferido de la carga ' || carga || ')';
END;
$$;

/* 3) Carga completa ---------------------------------------------------- */
CREATE OR REPLACE PROCEDURE BRONZE_DB.RAW.SP_CARGAR_BRONZE(CARGA_ID VARCHAR DEFAULT NULL)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
  tablas  ARRAY DEFAULT ARRAY_CONSTRUCT(
    'CATEGORIAS','SUBCATEGORIAS','MARCAS','PROVEEDORES','PRODUCTOS',
    'FORMATOS_TIENDA','SUCURSALES','EMPLEADOS','CLIENTES','METODOS_PAGO',
    'VENTAS','DETALLE_VENTA','COMPRAS_PROVEEDOR','DETALLE_COMPRA','DEVOLUCIONES');
  carga   STRING;
  t       STRING;
  fq      STRING;
  filas   INTEGER;
  resumen STRING DEFAULT '';
BEGIN
  carga := carga_id;

  -- Sin argumento: usar la carpeta más reciente
  IF (carga IS NULL OR carga = '') THEN
    EXECUTE IMMEDIATE 'LIST @BRONZE_DB.RAW.STG_BRONZE PATTERN = ''.*carga=[0-9_]+/.*[.]parquet''';
    SELECT MAX(REGEXP_SUBSTR("name", 'carga=([0-9_]+)', 1, 1, 'e', 1))
      INTO :carga
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
  END IF;

  IF (carga IS NULL) THEN
    RETURN 'ERROR: no se encontró ninguna carga en el contenedor bronze.';
  END IF;

  FOR i IN 0 TO ARRAY_SIZE(tablas) - 1 DO
    t  := tablas[i]::STRING;
    fq := 'BRONZE_DB.RAW.' || t;

    -- FULL LOAD: vaciar y volver a cargar la foto completa de esta corrida
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ' || fq;
    EXECUTE IMMEDIATE
         'COPY INTO ' || fq
      || ' FROM @BRONZE_DB.RAW.STG_BRONZE/' || LOWER(t) || '/carga=' || carga || '/'
      || ' FILE_FORMAT = (FORMAT_NAME = ''BRONZE_DB.RAW.FF_PARQUET'')'
      || ' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE'
      || ' INCLUDE_METADATA = (_LOAD_TS = METADATA$START_SCAN_TIME, _SOURCE_FILE = METADATA$FILENAME)'
      || ' ON_ERROR = ABORT_STATEMENT';

    SELECT COUNT(*) INTO :filas FROM IDENTIFIER(:fq);
    resumen := resumen || LOWER(t) || '=' || filas || '; ';
  END FOR;

  RETURN 'Carga ' || carga || ' -> ' || resumen;
END;
$$;

/* 4) Ejecutar --------------------------------------------------------- */
CALL BRONZE_DB.RAW.SP_CREAR_TABLAS_BRONZE();   -- una sola vez
CALL BRONZE_DB.RAW.SP_CARGAR_BRONZE();         -- carga la corrida más reciente

/* 5) Verificar: los conteos deben ser IGUALES a oltp/validaciones.sql -- */
SELECT 'CATEGORIAS' AS tabla, COUNT(*) AS filas, MAX(_LOAD_TS) AS cargado FROM BRONZE_DB.RAW.CATEGORIAS
UNION ALL SELECT 'SUBCATEGORIAS',     COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.SUBCATEGORIAS
UNION ALL SELECT 'MARCAS',            COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.MARCAS
UNION ALL SELECT 'PROVEEDORES',       COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.PROVEEDORES
UNION ALL SELECT 'PRODUCTOS',         COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.PRODUCTOS
UNION ALL SELECT 'FORMATOS_TIENDA',   COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.FORMATOS_TIENDA
UNION ALL SELECT 'SUCURSALES',        COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.SUCURSALES
UNION ALL SELECT 'EMPLEADOS',         COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.EMPLEADOS
UNION ALL SELECT 'CLIENTES',          COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.CLIENTES
UNION ALL SELECT 'METODOS_PAGO',      COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.METODOS_PAGO
UNION ALL SELECT 'VENTAS',            COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.VENTAS
UNION ALL SELECT 'DETALLE_VENTA',     COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.DETALLE_VENTA
UNION ALL SELECT 'COMPRAS_PROVEEDOR', COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.COMPRAS_PROVEEDOR
UNION ALL SELECT 'DETALLE_COMPRA',    COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.DETALLE_COMPRA
UNION ALL SELECT 'DEVOLUCIONES',      COUNT(*), MAX(_LOAD_TS) FROM BRONZE_DB.RAW.DEVOLUCIONES
ORDER BY filas DESC;

-- Total de ventas netas: debe coincidir con "ventas_netas" de oltp/validaciones.sql
SELECT CAST(SUM(CANTIDAD * PRECIO_UNITARIO - DESCUENTO) AS NUMBER(18,2)) AS ventas_netas
FROM BRONZE_DB.RAW.DETALLE_VENTA;

-- Tipos inferidos (útil para el lote de dbt)
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM BRONZE_DB.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'RAW'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
