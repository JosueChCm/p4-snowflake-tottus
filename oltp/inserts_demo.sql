/* =====================================================================
   Proyecto 4 - DW Snowflake sobre Azure | OLTP Tottus
   inserts_demo.sql  —  PRUEBA EN VIVO DE LA EXPOSICIÓN
   ---------------------------------------------------------------------
   Ejecutar en Azure Data Studio conectado a la base de AZURE (tottus_oltp)
   justo antes de lanzar el pipeline pl_p4_full con "Trigger now".

   Hace dos cosas:
     1. Sube 15 % el precio de un producto  -> el trigger actualiza
        updated_at y el snapshot de dbt creará una nueva versión (SCD2).
     2. Registra 3 ventas nuevas (con hora de Lima), dos de ellas con ese
        producto ya con el precio nuevo.
   Al final muestra lo insertado para comparar con Snowflake y Power BI.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @id_producto INT = NULL;   -- <== deja NULL para elegir el más vendido, o pon un id

IF @id_producto IS NULL
    SELECT TOP (1) @id_producto = d.id_producto
    FROM dbo.Detalle_Venta d
    JOIN dbo.Productos p ON p.id_producto = d.id_producto AND p.activo = 1
    GROUP BY d.id_producto
    ORDER BY COUNT(*) DESC;

DECLARE @otro_producto INT, @precio_otro DECIMAL(10,2);
SELECT TOP (1) @otro_producto = id_producto, @precio_otro = precio_unitario
FROM dbo.Productos
WHERE activo = 1 AND id_producto <> @id_producto
ORDER BY NEWID();

DECLARE @id_empleado INT, @id_sucursal INT;
SELECT TOP (1) @id_empleado = id_empleado, @id_sucursal = id_sucursal
FROM dbo.Empleados ORDER BY NEWID();

DECLARE @cliente1 INT = (SELECT TOP (1) id_cliente FROM dbo.Clientes ORDER BY NEWID());
DECLARE @cliente2 INT = (SELECT TOP (1) id_cliente FROM dbo.Clientes ORDER BY NEWID());
DECLARE @metodo   INT = (SELECT MIN(id_metodo_pago) FROM dbo.Metodos_Pago);
DECLARE @ahora_lima DATETIME = DATEADD(HOUR, -5, SYSUTCDATETIME());   -- Lima = UTC-5

DECLARE @precio_antes DECIMAL(10,2) =
    (SELECT precio_unitario FROM dbo.Productos WHERE id_producto = @id_producto);

DECLARE @v1 INT, @v2 INT, @v3 INT;

BEGIN TRANSACTION;

    /* 1) Cambio de precio (dispara trg_Productos_updated_at) */
    UPDATE dbo.Productos
       SET precio_unitario = ROUND(precio_unitario * 1.15, 2)
     WHERE id_producto = @id_producto;

    DECLARE @precio_nuevo DECIMAL(10,2) =
        (SELECT precio_unitario FROM dbo.Productos WHERE id_producto = @id_producto);

    /* 2) Tres ventas nuevas */
    INSERT INTO dbo.Ventas (id_sucursal, id_cliente, id_empleado, id_metodo_pago, fecha_venta, total)
    VALUES (@id_sucursal, @cliente1, @id_empleado, @metodo, @ahora_lima, 0);
    SET @v1 = SCOPE_IDENTITY();

    INSERT INTO dbo.Ventas (id_sucursal, id_cliente, id_empleado, id_metodo_pago, fecha_venta, total)
    VALUES (@id_sucursal, @cliente2, @id_empleado, @metodo, @ahora_lima, 0);
    SET @v2 = SCOPE_IDENTITY();

    INSERT INTO dbo.Ventas (id_sucursal, id_cliente, id_empleado, id_metodo_pago, fecha_venta, total)
    VALUES (@id_sucursal, NULL, @id_empleado, @metodo, @ahora_lima, 0);   -- venta sin cliente
    SET @v3 = SCOPE_IDENTITY();

    INSERT INTO dbo.Detalle_Venta (id_venta, id_producto, cantidad, precio_unitario, descuento)
    VALUES (@v1, @id_producto,   2, @precio_nuevo, 0),
           (@v2, @id_producto,   1, @precio_nuevo, 0),
           (@v2, @otro_producto, 1, @precio_otro,  0),
           (@v3, @otro_producto, 3, @precio_otro,  0);

    UPDATE v
       SET total = x.total
      FROM dbo.Ventas v
      JOIN (SELECT id_venta, SUM(cantidad * precio_unitario - descuento) AS total
              FROM dbo.Detalle_Venta
             WHERE id_venta IN (@v1, @v2, @v3)
             GROUP BY id_venta) x ON x.id_venta = v.id_venta;

COMMIT TRANSACTION;

/* 3) Lo que debe aparecer en Snowflake / Power BI después del pipeline */
SELECT @id_producto AS producto_cambiado, @precio_antes AS precio_antes, @precio_nuevo AS precio_nuevo;

SELECT v.id_venta, v.fecha_venta, v.id_sucursal, v.id_cliente, v.total, v.updated_at
FROM dbo.Ventas v WHERE v.id_venta IN (@v1, @v2, @v3);

SELECT id_producto, nombre_producto, precio_unitario, updated_at
FROM dbo.Productos WHERE id_producto = @id_producto;

SELECT COUNT(*) AS total_ventas_ahora FROM dbo.Ventas;
