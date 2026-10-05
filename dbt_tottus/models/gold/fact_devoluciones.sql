-- Gold | fact_devoluciones — grano: una devolución
-- Monto estimado = cantidad devuelta x precio promedio cobrado en esa venta.
with dv as (select * from {{ ref('stg_devoluciones') }}),
     v  as (select * from {{ ref('stg_ventas') }}),
     pr as (
        select id_venta, id_producto,
               sum(cantidad * precio_unitario - descuento) / nullif(sum(cantidad), 0) as precio_neto_unitario
        from {{ ref('stg_detalle_venta') }}
        group by id_venta, id_producto
     ),
     p  as (select * from {{ ref('dim_producto') }}),
     su as (select * from {{ ref('dim_sucursal') }})
select
    dv.id_devolucion,
    dv.id_venta,
    cast(to_char(dv.fecha_devolucion, 'YYYYMMDD') as integer)              as fecha_sk,
    p.producto_sk,
    su.sucursal_sk,
    dv.motivo,
    dv.fecha_devolucion,
    dv.cantidad,
    cast(dv.cantidad * coalesce(pr.precio_neto_unitario, 0) as number(14,2)) as monto_estimado
from dv
left join v  on dv.id_venta = v.id_venta
left join pr on dv.id_venta = pr.id_venta and dv.id_producto = pr.id_producto
left join p  on dv.id_producto = p.id_producto
            and dv.fecha_devolucion >= p.valido_desde  and dv.fecha_devolucion < p.valido_hasta
left join su on v.id_sucursal = su.id_sucursal
            and dv.fecha_devolucion >= su.valido_desde and dv.fecha_devolucion < su.valido_hasta
