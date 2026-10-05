-- Solo prod: las ventas netas de Gold deben cuadrar con Bronze (tolerancia 1 céntimo)
{{ config(enabled = (target.name == 'prod')) }}
select g.total as ventas_gold, b.total as ventas_bronze
from (select sum(monto_neto) total from {{ ref('fact_ventas') }}) g,
     (select sum(cantidad * precio_unitario - coalesce(descuento, 0)) total
        from {{ source('bronze', 'DETALLE_VENTA') }}) b
where abs(g.total - b.total) > 0.01
