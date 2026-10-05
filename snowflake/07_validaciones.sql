/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure
   07_validaciones.sql   —   Evidencias para el informe y la exposición
   ---------------------------------------------------------------------
   Ejecutar con ROL_ORQ después de una corrida completa de pl_p4_full.
   Compara con oltp/validaciones.sql (Azure SQL).
   ===================================================================== */
USE ROLE ROL_ORQ;
USE WAREHOUSE WH_TOTTUS;

/* 1) Conciliación de filas por capa: Bronze = Silver = Gold ------------ */
SELECT 'Ventas (cabecera)' AS entidad,
       (SELECT COUNT(*) FROM BRONZE_DB.RAW.VENTAS)                AS bronze,
       (SELECT COUNT(*) FROM SILVER_DB.STAGING.STG_VENTAS)        AS silver,
       (SELECT COUNT(DISTINCT id_venta) FROM GOLD_DB.MARTS.FACT_VENTAS) AS gold
UNION ALL
SELECT 'Líneas de venta',
       (SELECT COUNT(*) FROM BRONZE_DB.RAW.DETALLE_VENTA),
       (SELECT COUNT(*) FROM SILVER_DB.STAGING.STG_DETALLE_VENTA),
       (SELECT COUNT(*) FROM GOLD_DB.MARTS.FACT_VENTAS)
UNION ALL
SELECT 'Devoluciones',
       (SELECT COUNT(*) FROM BRONZE_DB.RAW.DEVOLUCIONES),
       (SELECT COUNT(*) FROM SILVER_DB.STAGING.STG_DEVOLUCIONES),
       (SELECT COUNT(*) FROM GOLD_DB.MARTS.FACT_DEVOLUCIONES);

/* 2) Conciliación de montos (debe coincidir con ventas_netas del OLTP) - */
SELECT
  (SELECT SUM(cantidad * precio_unitario - COALESCE(descuento, 0)) FROM BRONZE_DB.RAW.DETALLE_VENTA)::NUMBER(18,2) AS ventas_netas_bronze,
  (SELECT SUM(monto_neto) FROM GOLD_DB.MARTS.FACT_VENTAS)::NUMBER(18,2)                                            AS ventas_netas_gold;

/* 3) Integridad del modelo estrella: hechos sin dimensión (esperado 0) - */
SELECT
  COUNT_IF(producto_sk IS NULL) AS sin_producto,
  COUNT_IF(sucursal_sk IS NULL) AS sin_sucursal,
  COUNT_IF(cliente_sk  = '-1')  AS ventas_cliente_anonimo
FROM GOLD_DB.MARTS.FACT_VENTAS;

/* 4) SCD2: productos con más de una versión (crece tras cada demo) ------ */
SELECT id_producto, COUNT(*) AS versiones
FROM GOLD_DB.MARTS.DIM_PRODUCTO
GROUP BY id_producto
HAVING COUNT(*) > 1
ORDER BY versiones DESC;

-- Historia completa de un producto (reemplaza el id por el de la demo)
SELECT id_producto, nombre_producto, precio_lista, valido_desde, valido_hasta, es_actual
FROM GOLD_DB.MARTS.DIM_PRODUCTO
WHERE id_producto = 1
ORDER BY valido_desde;

-- Ventas del producto por versión de precio (el valor del SCD2)
SELECT p.precio_lista, p.valido_desde, p.valido_hasta,
       COUNT(*) AS lineas, SUM(f.cantidad) AS unidades, SUM(f.monto_neto) AS ventas
FROM GOLD_DB.MARTS.FACT_VENTAS f
JOIN GOLD_DB.MARTS.DIM_PRODUCTO p ON p.producto_sk = f.producto_sk
WHERE p.id_producto = 1
GROUP BY 1, 2, 3
ORDER BY 2;

/* 5) Rendimiento observado (Proyecto 6) --------------------------------- */
SELECT * FROM OPS_DB.ADMIN.V_CORRIDAS ORDER BY inicio DESC;

/* 6) Separación física de capas: tablas Iceberg y su volumen ----------- */
SHOW ICEBERG TABLES IN DATABASE SILVER_DB;
SHOW ICEBERG TABLES IN DATABASE GOLD_DB;

/* 7) Frescura: última carga en Bronze ----------------------------------- */
SELECT MAX(_load_ts) AS ultima_carga, ANY_VALUE(_source_file) AS archivo
FROM BRONZE_DB.RAW.VENTAS;
