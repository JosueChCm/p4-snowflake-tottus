-- Solo prod: Gold + ajustes de descuento debe igualar a Bronze (tolerancia 1 céntimo).
-- Demuestra que la regla de calidad no pierde ni inventa ventas: solo reclasifica el exceso de descuento.
{{ config(enabled = (target.name == 'prod')) }}
select g.neto + g.ajustes as gold_mas_ajustes, b.neto as bronze
from (select sum(monto_neto) neto, sum(ajuste_descuento) ajustes
        from {{ ref('fact_ventas') }}) g,
     (select sum(cantidad * precio_unitario - coalesce(descuento, 0)) neto
        from {{ source('bronze', 'DETALLE_VENTA') }}) b
where abs((g.neto + g.ajustes) - b.neto) > 0.01
