/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure | OLTP Tottus
   01_adaptar_scd2.sql
   ---------------------------------------------------------------------
   Prepara la base Tottus_OLTP (la del Proyecto 2) para el Proyecto 4:
     1. Nivel de compatibilidad 160 (SQL Server 2022), por precaución,
        para que el .bacpac se importe sin problemas en Azure SQL.
     2. Columna de auditoría  updated_at DATETIME2(6)  en las 15 tablas.
        - Precisión 6 (microsegundos): es la que admite Apache Iceberg.
     3. Relleno histórico de updated_at:
        - Catálogos y maestros: un día antes de la primera venta.
        - Transacciones: su propia fecha (venta, compra, devolución).
     4. Triggers que actualizan updated_at en cada UPDATE de
        Productos, Clientes y Sucursales (dimensiones SCD2 del DW).
     5. Índices de apoyo sobre claves foráneas y fechas.
   Ejecutar en SSMS conectado a la instancia LOCAL. Es idempotente:
   puede ejecutarse más de una vez sin duplicar nada.
   ===================================================================== */

USE [Tottus_OLTP];
GO

ALTER DATABASE [Tottus_OLTP] SET COMPATIBILITY_LEVEL = 160;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ---------------------------------------------------------------------
   1) Columna updated_at en las 15 tablas
   --------------------------------------------------------------------- */
DECLARE @tablas TABLE (nombre SYSNAME);
INSERT INTO @tablas (nombre) VALUES
 ('Categorias'), ('Subcategorias'), ('Marcas'), ('Proveedores'), ('Productos'),
 ('Formatos_Tienda'), ('Sucursales'), ('Empleados'), ('Clientes'), ('Metodos_Pago'),
 ('Ventas'), ('Detalle_Venta'), ('Compras_Proveedor'), ('Detalle_Compra'), ('Devoluciones');

DECLARE @t SYSNAME, @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT nombre FROM @tablas;
OPEN c;
FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF COL_LENGTH(N'dbo.' + @t, N'updated_at') IS NULL
    BEGIN
        SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@t) +
                   N' ADD updated_at DATETIME2(6) NOT NULL' +
                   N' CONSTRAINT ' + QUOTENAME(N'DF_' + @t + N'_updated_at') +
                   N' DEFAULT SYSUTCDATETIME();';
        EXEC sys.sp_executesql @sql;
        PRINT 'updated_at agregada a dbo.' + @t;
    END
    ELSE
        PRINT 'dbo.' + @t + ' ya tenía updated_at (sin cambios)';
    FETCH NEXT FROM c INTO @t;
END
CLOSE c;
DEALLOCATE c;
GO

/* ---------------------------------------------------------------------
   2) Relleno histórico (solo filas que aún tienen la fecha de hoy)
   --------------------------------------------------------------------- */
DECLARE @base DATETIME2(6) =
    CAST(DATEADD(DAY, -1, CAST((SELECT MIN(fecha_venta) FROM dbo.Ventas) AS DATE)) AS DATETIME2(6));
DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AS DATE);

PRINT 'Fecha base para catálogos y maestros: ' + CONVERT(VARCHAR(30), @base, 120);

-- Catálogos y maestros: versión inicial anterior a todas las ventas
UPDATE dbo.Categorias      SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Subcategorias   SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Marcas          SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Proveedores     SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Productos       SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Formatos_Tienda SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Sucursales      SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Empleados       SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Clientes        SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;
UPDATE dbo.Metodos_Pago    SET updated_at = @base WHERE CAST(updated_at AS DATE) = @hoy;

-- Transacciones: su propia fecha de negocio
UPDATE dbo.Ventas
   SET updated_at = CAST(fecha_venta AS DATETIME2(6))
 WHERE CAST(updated_at AS DATE) = @hoy;

UPDATE d
   SET updated_at = CAST(v.fecha_venta AS DATETIME2(6))
  FROM dbo.Detalle_Venta d
  JOIN dbo.Ventas v ON v.id_venta = d.id_venta
 WHERE CAST(d.updated_at AS DATE) = @hoy;

UPDATE dbo.Compras_Proveedor
   SET updated_at = CAST(fecha_compra AS DATETIME2(6))
 WHERE CAST(updated_at AS DATE) = @hoy;

UPDATE d
   SET updated_at = CAST(c.fecha_compra AS DATETIME2(6))
  FROM dbo.Detalle_Compra d
  JOIN dbo.Compras_Proveedor c ON c.id_compra = d.id_compra
 WHERE CAST(d.updated_at AS DATE) = @hoy;

UPDATE dbo.Devoluciones
   SET updated_at = CAST(fecha_devolucion AS DATETIME2(6))
 WHERE CAST(updated_at AS DATE) = @hoy;
GO

/* ---------------------------------------------------------------------
   3) Triggers SCD2: cada UPDATE marca la fila con la hora actual (UTC)
      TRIGGER_NESTLEVEL evita que el UPDATE del propio trigger lo vuelva
      a disparar aunque se active RECURSIVE_TRIGGERS.
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_Productos_updated_at
ON dbo.Productos
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 RETURN;
    UPDATE p
       SET updated_at = SYSUTCDATETIME()
      FROM dbo.Productos p
      JOIN inserted i ON i.id_producto = p.id_producto;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_Clientes_updated_at
ON dbo.Clientes
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 RETURN;
    UPDATE c
       SET updated_at = SYSUTCDATETIME()
      FROM dbo.Clientes c
      JOIN inserted i ON i.id_cliente = c.id_cliente;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_Sucursales_updated_at
ON dbo.Sucursales
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 RETURN;
    UPDATE s
       SET updated_at = SYSUTCDATETIME()
      FROM dbo.Sucursales s
      JOIN inserted i ON i.id_sucursal = s.id_sucursal;
END;
GO

/* ---------------------------------------------------------------------
   4) Índices de apoyo (el script original no tenía índices en FKs)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Ventas_fecha_venta')
    CREATE INDEX IX_Ventas_fecha_venta ON dbo.Ventas (fecha_venta);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Ventas_id_cliente')
    CREATE INDEX IX_Ventas_id_cliente ON dbo.Ventas (id_cliente);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Ventas_id_sucursal')
    CREATE INDEX IX_Ventas_id_sucursal ON dbo.Ventas (id_sucursal);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DetalleVenta_id_venta')
    CREATE INDEX IX_DetalleVenta_id_venta ON dbo.Detalle_Venta (id_venta);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DetalleVenta_id_producto')
    CREATE INDEX IX_DetalleVenta_id_producto ON dbo.Detalle_Venta (id_producto);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Empleados_id_sucursal')
    CREATE INDEX IX_Empleados_id_sucursal ON dbo.Empleados (id_sucursal);
GO

/* ---------------------------------------------------------------------
   5) Verificación
   --------------------------------------------------------------------- */
SELECT t.name AS tabla,
       CASE WHEN c.name IS NULL THEN 'FALTA' ELSE 'OK' END AS updated_at
FROM sys.tables t
LEFT JOIN sys.columns c ON c.object_id = t.object_id AND c.name = 'updated_at'
ORDER BY t.name;

SELECT name AS trigger_scd2, OBJECT_NAME(parent_id) AS tabla
FROM sys.triggers
WHERE name LIKE 'trg[_]%updated[_]at';
GO
