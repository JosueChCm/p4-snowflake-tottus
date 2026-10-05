# Diccionario de datos — Proyecto 4 (Tottus)

Sensible = dato personal protegido por la Ley N.° 29733.

## Capas y ubicación

| Capa | Base / esquema Snowflake | Contenedor ADLS | Formato |
|------|--------------------------|-----------------|---------|
| Bronze | `BRONZE_DB.RAW` (15 tablas) | `bronze/<tabla>/carga=<id>/` | Parquet (archivos) + tablas nativas |
| Silver | `SILVER_DB.STAGING` (15 `STG_*`), `SILVER_DB.SNAPSHOTS` (3 `SNAP_*`) | `silver/` | Apache Iceberg |
| Gold | `GOLD_DB.MARTS` (6 dimensiones + 2 hechos) | `gold/` | Apache Iceberg |
| Operación | `OPS_DB.ADMIN` (repositorio Git, proyecto dbt, bitácora) | — | nativo |

Columnas de auditoría en Bronze y Silver: `UPDATED_AT` (última modificación en el OLTP, la mantienen
triggers), `_LOAD_TS` (momento de la carga), `_SOURCE_FILE` (Parquet de origen).

## Gold — dimensiones

### DIM_FECHA (calendario 2018-2028)
| Columna | Tipo | Descripción |
|---|---|---|
| FECHA_SK | NUMBER | Clave AAAAMMDD |
| FECHA | DATE | Fecha |
| ANIO, TRIMESTRE, MES, DIA | NUMBER | Partes de la fecha |
| NOMBRE_MES, NOMBRE_DIA | VARCHAR | En español |
| ANIO_MES | VARCHAR | AAAA-MM |
| DIA_SEMANA | NUMBER | 1 = lunes … 7 = domingo |
| ES_FIN_DE_SEMANA | BOOLEAN | Sábado o domingo |

### DIM_PRODUCTO (SCD2 — una fila por versión)
| Columna | Tipo | Descripción |
|---|---|---|
| PRODUCTO_SK | VARCHAR | Clave sustituta = `dbt_scd_id` de la versión |
| ID_PRODUCTO | NUMBER | Clave de negocio |
| NOMBRE_PRODUCTO | VARCHAR | Nombre |
| SUBCATEGORIA, CATEGORIA | VARCHAR | Jerarquía (desnormalizada: modelo estrella) |
| MARCA, ES_MARCA_PROPIA | VARCHAR / BOOLEAN | Marca y si es propia de Tottus |
| PROVEEDOR | VARCHAR | Razón social del proveedor |
| UNIDAD_MEDIDA | VARCHAR | Unidad de venta |
| PRECIO_LISTA | NUMBER(10,2) | Precio de lista de **esa versión** |
| ACTIVO | BOOLEAN | Producto activo |
| VALIDO_DESDE / VALIDO_HASTA | TIMESTAMP_NTZ(6) | Vigencia (1ª versión desde 1900-01-01; vigente hasta 9999-12-31) |
| ES_ACTUAL | BOOLEAN | Versión vigente |

### DIM_CLIENTE (SCD2 + fila `-1` "Cliente anónimo")
| Columna | Tipo | Descripción | Sensible |
|---|---|---|---|
| CLIENTE_SK | VARCHAR | Clave sustituta (`-1` = venta sin cliente) | |
| ID_CLIENTE | NUMBER | Clave de negocio | |
| NOMBRES | VARCHAR | Nombre del cliente | Sí |
| TIPO_DOCUMENTO | VARCHAR | DNI, CE, … | |
| NUM_DOCUMENTO | VARCHAR | **Enmascarado** (`MP_DATO_PERSONAL`) salvo para roles de transformación | **Sí** |
| RANGO_EDAD | VARCHAR | 18-24, 25-34, 35-44, 45-59, 60+ (la fecha de nacimiento no llega a Gold) | Minimizado |
| TIENE_TARJETA_CMR | BOOLEAN | Cliente con tarjeta CMR | |
| VALIDO_DESDE / VALIDO_HASTA / ES_ACTUAL | | Vigencia SCD2 | |

### DIM_SUCURSAL (SCD2)
| Columna | Tipo | Descripción |
|---|---|---|
| SUCURSAL_SK | VARCHAR | Clave sustituta de la versión |
| ID_SUCURSAL | NUMBER | Clave de negocio |
| NOMBRE_SUCURSAL, FORMATO | VARCHAR | Tienda y formato |
| DISTRITO, CIUDAD, REGION | VARCHAR | Ubicación |
| FECHA_APERTURA | DATE | Apertura |
| VALIDO_DESDE / VALIDO_HASTA / ES_ACTUAL | | Vigencia SCD2 |

### DIM_EMPLEADO / DIM_METODO_PAGO (tipo 1)
| Columna | Descripción |
|---|---|
| EMPLEADO_SK, NOMBRES, CARGO, ID_SUCURSAL, FECHA_INGRESO | Estado actual del empleado |
| METODO_PAGO_SK, METODO_PAGO | Efectivo, tarjeta, etc. |

## Gold — hechos

### FACT_VENTAS (grano: una línea de venta)
| Columna | Tipo | Descripción |
|---|---|---|
| ID_DETALLE_VENTA | NUMBER | Clave de la línea |
| ID_VENTA | NUMBER | Ticket |
| FECHA_SK, PRODUCTO_SK, CLIENTE_SK, SUCURSAL_SK, EMPLEADO_SK, METODO_PAGO_SK | | Claves a dimensiones (las SCD2 se unen por la versión vigente en la fecha de venta) |
| FECHA_VENTA | TIMESTAMP_NTZ(6) | Fecha y hora |
| CANTIDAD | NUMBER | Unidades |
| PRECIO_COBRADO | NUMBER(10,2) | Precio unitario cobrado |
| PRECIO_LISTA_VIGENTE | NUMBER(10,2) | Precio de lista de la versión vigente del producto |
| DESCUENTO | NUMBER(10,2) | Descuento de la línea |
| MONTO_BRUTO | NUMBER(14,2) | CANTIDAD × PRECIO_COBRADO |
| MONTO_NETO | NUMBER(14,2) | MONTO_BRUTO − DESCUENTO |

### FACT_DEVOLUCIONES (grano: una devolución)
| Columna | Descripción |
|---|---|
| ID_DEVOLUCION, ID_VENTA | Claves |
| FECHA_SK, PRODUCTO_SK, SUCURSAL_SK | Dimensiones |
| MOTIVO, FECHA_DEVOLUCION, CANTIDAD | Detalle |
| MONTO_ESTIMADO | Cantidad × precio neto unitario cobrado en la venta |

## Origen (OLTP Azure SQL `tottus_oltp`, 15 tablas)

Categorias · Subcategorias · Marcas · Proveedores · Productos (SCD2) · Formatos_Tienda · Sucursales (SCD2) ·
Empleados · Clientes (SCD2, sensible) · Metodos_Pago · Ventas · Detalle_Venta · Compras_Proveedor ·
Detalle_Compra · Devoluciones. Todas con `updated_at DATETIME2(6)`.
