/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure | OLTP Tottus
   validaciones.sql
   ---------------------------------------------------------------------
   Ejecutar DOS veces y comparar (deben coincidir):
     a) En SSMS sobre la base LOCAL Tottus_OLTP   (después de 01 y 02)
     b) En Azure Data Studio sobre tottus_oltp    (después de migrar)
   Guarda capturas: son la evidencia del requisito de volumen y de la
   conciliación OLTP = Bronze = Gold.
   ===================================================================== */
SET NOCOUNT ON;

/* 1) Filas por tabla (deben ser 15 tablas) */
SELECT t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY t.name
ORDER BY filas DESC;

SELECT COUNT(*) AS total_tablas FROM sys.tables WHERE is_ms_shipped = 0;

/* 2) Requisito: tablas principales con >= 100 000 filas */
SELECT 'Ventas' AS tabla, COUNT(*) AS filas,
       CASE WHEN COUNT(*) >= 100000 THEN 'CUMPLE' ELSE 'NO CUMPLE' END AS requisito
FROM dbo.Ventas
UNION ALL
SELECT 'Detalle_Venta', COUNT(*),
       CASE WHEN COUNT(*) >= 100000 THEN 'CUMPLE' ELSE 'NO CUMPLE' END
FROM dbo.Detalle_Venta;

/* 3) Coherencia: Ventas.total = suma de su detalle (esperado: 0 diferencias)
      Si las ventas del Proyecto 2 calculaban el total de otra forma,
      aparecerán aquí: revisar antes de construir Gold. */
SELECT COUNT(*) AS ventas_con_total_distinto
FROM dbo.Ventas v
JOIN (SELECT id_venta, SUM(cantidad * precio_unitario - descuento) AS total_detalle
        FROM dbo.Detalle_Venta GROUP BY id_venta) d
  ON d.id_venta = v.id_venta
WHERE ABS(v.total - d.total_detalle) > 0.01;

SELECT COUNT(*) AS ventas_sin_detalle
FROM dbo.Ventas v
WHERE NOT EXISTS (SELECT 1 FROM dbo.Detalle_Venta d WHERE d.id_venta = v.id_venta);

/* 4) Totales de negocio (deben coincidir local vs Azure, y luego con Gold) */
SELECT COUNT(DISTINCT v.id_venta)                                   AS num_ventas,
       COUNT(*)                                                     AS lineas_detalle,
       SUM(d.cantidad)                                              AS unidades,
       CAST(SUM(d.cantidad * d.precio_unitario - d.descuento) AS DECIMAL(18,2)) AS ventas_netas,
       MIN(v.fecha_venta)                                           AS primera_venta,
       MAX(v.fecha_venta)                                           AS ultima_venta
FROM dbo.Ventas v
JOIN dbo.Detalle_Venta d ON d.id_venta = v.id_venta;

SELECT YEAR(v.fecha_venta) AS anio, COUNT(*) AS ventas,
       CAST(SUM(v.total) AS DECIMAL(18,2)) AS monto
FROM dbo.Ventas v
GROUP BY YEAR(v.fecha_venta)
ORDER BY anio;

/* 5) Preparación SCD2: columna, triggers y rango de updated_at */
SELECT t.name AS tabla,
       CASE WHEN c.name IS NULL THEN 'FALTA' ELSE 'OK' END AS updated_at
FROM sys.tables t
LEFT JOIN sys.columns c ON c.object_id = t.object_id AND c.name = 'updated_at'
WHERE t.is_ms_shipped = 0
ORDER BY t.name;

SELECT name AS trigger_scd2, OBJECT_NAME(parent_id) AS tabla, is_disabled
FROM sys.triggers
WHERE name LIKE 'trg[_]%updated[_]at';

SELECT 'Productos'  AS tabla, MIN(updated_at) AS min_updated_at, MAX(updated_at) AS max_updated_at FROM dbo.Productos
UNION ALL SELECT 'Clientes',   MIN(updated_at), MAX(updated_at) FROM dbo.Clientes
UNION ALL SELECT 'Sucursales', MIN(updated_at), MAX(updated_at) FROM dbo.Sucursales;

/* 6) Datos para el diseño del DW */
SELECT CAST(AVG(CASE WHEN id_cliente IS NULL THEN 1.0 ELSE 0.0 END) * 100 AS DECIMAL(5,1))
       AS pct_ventas_sin_cliente
FROM dbo.Ventas;

SELECT DB_NAME() AS base, compatibility_level
FROM sys.databases WHERE name = DB_NAME();
