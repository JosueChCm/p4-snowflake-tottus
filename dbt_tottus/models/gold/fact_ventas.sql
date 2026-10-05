-- Gold | fact_ventas — grano: una línea de detalle de venta
-- Cada línea se une con la versión del producto, cliente y sucursal
-- VIGENTE EN LA FECHA DE LA VENTA (join SCD2 por rango de validez).
with d  as (select * from {{ ref('stg_detalle_venta') }}),
     v  as (select * from {{ ref('stg_ventas') }}),
     p  as (select * from {{ ref('dim_producto') }}),
     c  as (select * from {{ ref('dim_cliente') }} where cliente_sk <> '-1'),
     su as (select * from {{ ref('dim_sucursal') }})
select
    d.id_detalle_venta,
    v.id_venta,
    cast(to_char(v.fecha_venta, 'YYYYMMDD') as integer)     as fecha_sk,
    p.producto_sk,
    coalesce(c.cliente_sk, '-1')                            as cliente_sk,
    su.sucursal_sk,
    v.id_empleado                                           as empleado_sk,
    v.id_metodo_pago                                        as metodo_pago_sk,
    v.fecha_venta,
    d.cantidad,
    d.precio_unitario                                       as precio_cobrado,
    p.precio_lista                                          as precio_lista_vigente,
    d.descuento,
    cast(d.cantidad * d.precio_unitario as number(14,2))                as monto_bruto,
    cast(d.cantidad * d.precio_unitario - d.descuento as number(14,2))  as monto_neto,
    d._load_ts
from d
join v on d.id_venta = v.id_venta
left join p  on d.id_producto = p.id_producto
            and v.fecha_venta >= p.valido_desde  and v.fecha_venta < p.valido_hasta
left join c  on v.id_cliente  = c.id_cliente
            and v.fecha_venta >= c.valido_desde  and v.fecha_venta < c.valido_hasta
left join su on v.id_sucursal = su.id_sucursal
            and v.fecha_venta >= su.valido_desde and v.fecha_venta < su.valido_hasta
