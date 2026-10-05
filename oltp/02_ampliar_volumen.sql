/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure | OLTP Tottus
   02_ampliar_volumen.sql
   ---------------------------------------------------------------------
   Lleva dbo.Ventas a @objetivo filas (por defecto 110 000) y genera su
   detalle con la misma proporción del Proyecto 2 (≈ 7,5 líneas por
   venta => Detalle_Venta queda en ≈ 800 000 filas).

   Reglas para que los datos sean coherentes:
     - Fechas dentro del rango de ventas existente, entre 08:00 y 22:00.
     - El empleado pertenece a la sucursal de la venta.
     - Se respeta el % de ventas sin cliente (id_cliente NULL) actual.
     - Solo productos activos; precio = precio_unitario actual del producto.
     - ≈ 12 % de las líneas con descuento de 5 %, 10 % o 15 %.
     - Ventas.total = SUM(cantidad * precio_unitario - descuento).
     - updated_at = fecha de la venta.
   No modifica ni borra filas existentes. Si Ventas ya tiene @objetivo
   filas, no hace nada (idempotente).
   Ejecutar DESPUÉS de 01_adaptar_scd2.sql, en la instancia LOCAL.
   Tiempo aproximado: 1 a 3 minutos.
   ===================================================================== */

USE [Tottus_OLTP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @objetivo INT = 110000;      -- <== total de ventas deseado

DECLARE @actual INT = (SELECT COUNT(*) FROM dbo.Ventas);
DECLARE @faltan INT = @objetivo - @actual;

IF @faltan <= 0
BEGIN
    PRINT 'Ventas ya tiene ' + CAST(@actual AS VARCHAR(12)) + ' filas. No se genera nada.';
    RETURN;
END

DECLARE @max_id     INT      = (SELECT MAX(id_venta)    FROM dbo.Ventas);
DECLARE @fmin       DATE     = (SELECT CAST(MIN(fecha_venta) AS DATE) FROM dbo.Ventas);
DECLARE @fmax       DATE     = (SELECT CAST(MAX(fecha_venta) AS DATE) FROM dbo.Ventas);
DECLARE @dias       INT      = DATEDIFF(DAY, @fmin, @fmax) + 1;
DECLARE @pct_anon   FLOAT    = (SELECT AVG(CASE WHEN id_cliente IS NULL THEN 1.0 ELSE 0.0 END) FROM dbo.Ventas);

PRINT 'Ventas actuales: ' + CAST(@actual AS VARCHAR(12)) + ' | a generar: ' + CAST(@faltan AS VARCHAR(12));
PRINT 'Rango de fechas: ' + CONVERT(VARCHAR(10), @fmin, 120) + ' a ' + CONVERT(VARCHAR(10), @fmax, 120);

/* ---------------------------------------------------------------------
   1) Catálogos numerados para elegir valores al azar con un JOIN
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS #cli, #prod, #suc, #emp, #mp, #k, #nv, #dv;

SELECT ROW_NUMBER() OVER (ORDER BY id_cliente) AS rn, id_cliente
INTO #cli FROM dbo.Clientes;

SELECT ROW_NUMBER() OVER (ORDER BY id_producto) AS rn, id_producto, precio_unitario
INTO #prod FROM dbo.Productos WHERE activo = 1;

SELECT ROW_NUMBER() OVER (ORDER BY s.id_sucursal) AS rn, s.id_sucursal
INTO #suc FROM dbo.Sucursales s
WHERE EXISTS (SELECT 1 FROM dbo.Empleados e WHERE e.id_sucursal = s.id_sucursal);

SELECT id_sucursal,
       ROW_NUMBER() OVER (PARTITION BY id_sucursal ORDER BY id_empleado) AS rn,
       COUNT(*)     OVER (PARTITION BY id_sucursal)                      AS cnt,
       id_empleado
INTO #emp FROM dbo.Empleados;

SELECT ROW_NUMBER() OVER (ORDER BY id_metodo_pago) AS rn, id_metodo_pago
INTO #mp FROM dbo.Metodos_Pago;

DECLARE @ncli  INT = (SELECT COUNT(*) FROM #cli);
DECLARE @nprod INT = (SELECT COUNT(*) FROM #prod);
DECLARE @nsuc  INT = (SELECT COUNT(*) FROM #suc);
DECLARE @nmp   INT = (SELECT COUNT(*) FROM #mp);

IF @ncli = 0 OR @nprod = 0 OR @nsuc = 0 OR @nmp = 0
BEGIN
    RAISERROR('Faltan datos maestros (clientes, productos activos, sucursales con empleados o métodos de pago).', 16, 1);
    RETURN;
END

-- Números 1..14 para las líneas de cada venta
SELECT TOP (14) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k INTO #k FROM sys.all_objects;

/* ---------------------------------------------------------------------
   2) Cabeceras nuevas: valores aleatorios materializados en #nv
      (CAST a BIGINT evita el desbordamiento de ABS(-2147483648))
   --------------------------------------------------------------------- */
;WITH n AS (
    SELECT TOP (@faltan) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
SELECT n,
       ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % @nsuc + 1 AS r_suc,
       ABS(CAST(CHECKSUM(NEWID()) AS BIGINT))             AS r_emp,
       ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % @ncli + 1 AS r_cli,
       RAND(CHECKSUM(NEWID()))                            AS p_anon,
       ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % @nmp + 1  AS r_mp,
       DATEADD(SECOND,
               CAST(28800 + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 50400 AS INT),      -- 08:00 a 22:00
               CAST(DATEADD(DAY, CAST(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % @dias AS INT), @fmin)
                    AS DATETIME)
       )                                                  AS fecha,
       ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 14 + 1    AS lineas            -- promedio 7,5
INTO #nv
FROM n;

/* ---------------------------------------------------------------------
   3) Detalle: valores aleatorios materializados en #dv
   --------------------------------------------------------------------- */
SELECT @max_id + v.n                                       AS id_venta,
       CAST(v.fecha AS DATETIME2(6))                        AS updated_at,
       ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % @nprod + 1  AS r_prod,
       ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5 + 1       AS cantidad,
       RAND(CHECKSUM(NEWID()))                              AS p_desc,
       0.05 * (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 3 + 1) AS pct_desc
INTO #dv
FROM #nv v
JOIN #k  k ON k.k <= v.lineas;

/* ---------------------------------------------------------------------
   4) Inserción en una sola transacción
   --------------------------------------------------------------------- */
BEGIN TRANSACTION;

    SET IDENTITY_INSERT dbo.Ventas ON;

    INSERT INTO dbo.Ventas (id_venta, id_sucursal, id_cliente, id_empleado, id_metodo_pago,
                            fecha_venta, total, updated_at)
    SELECT @max_id + v.n,
           s.id_sucursal,
           CASE WHEN v.p_anon < @pct_anon THEN NULL ELSE c.id_cliente END,
           e.id_empleado,
           m.id_metodo_pago,
           v.fecha,
           0,
           CAST(v.fecha AS DATETIME2(6))
    FROM #nv v
    JOIN #suc s ON s.rn = v.r_suc
    JOIN #emp e ON e.id_sucursal = s.id_sucursal AND e.rn = v.r_emp % e.cnt + 1
    JOIN #cli c ON c.rn = v.r_cli
    JOIN #mp  m ON m.rn = v.r_mp;

    SET IDENTITY_INSERT dbo.Ventas OFF;

    INSERT INTO dbo.Detalle_Venta (id_venta, id_producto, cantidad, precio_unitario, descuento, updated_at)
    SELECT d.id_venta,
           p.id_producto,
           d.cantidad,
           p.precio_unitario,
           CASE WHEN d.p_desc < 0.12
                THEN ROUND(d.cantidad * p.precio_unitario * d.pct_desc, 2)
                ELSE 0 END,
           d.updated_at
    FROM #dv d
    JOIN #prod p ON p.rn = d.r_prod;

    UPDATE v
       SET total = x.total
      FROM dbo.Ventas v
      JOIN (SELECT id_venta, SUM(cantidad * precio_unitario - descuento) AS total
              FROM dbo.Detalle_Venta
             WHERE id_venta > @max_id
             GROUP BY id_venta) x
        ON x.id_venta = v.id_venta;

COMMIT TRANSACTION;

/* ---------------------------------------------------------------------
   5) Resumen
   --------------------------------------------------------------------- */
SELECT 'Ventas'        AS tabla, COUNT(*) AS filas FROM dbo.Ventas
UNION ALL
SELECT 'Detalle_Venta',           COUNT(*)          FROM dbo.Detalle_Venta;

SELECT MIN(fecha_venta) AS primera_venta, MAX(fecha_venta) AS ultima_venta,
       CAST(AVG(CASE WHEN id_cliente IS NULL THEN 1.0 ELSE 0.0 END) * 100 AS DECIMAL(5,1)) AS pct_sin_cliente
FROM dbo.Ventas;

DROP TABLE IF EXISTS #cli, #prod, #suc, #emp, #mp, #k, #nv, #dv;
GO
