-- Aviso de calidad (no detiene el pipeline): líneas cuyo descuento original superaba el monto bruto
-- y fueron topadas en Silver. En cada corrida dbt informa: WARN <n>.
{{ config(severity = 'warn') }}
select id_detalle_venta, id_venta, descuento_original, descuento, ajuste_descuento
from {{ ref('fact_ventas') }}
where descuento_ajustado
