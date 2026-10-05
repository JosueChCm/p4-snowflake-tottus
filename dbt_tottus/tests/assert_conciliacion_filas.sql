-- Solo prod: Gold debe tener exactamente las mismas líneas de venta que Bronze
{{ config(enabled = (target.name == 'prod')) }}
select g.n as filas_gold, b.n as filas_bronze
from (select count(*) n from {{ ref('fact_ventas') }}) g,
     (select count(*) n from {{ source('bronze', 'DETALLE_VENTA') }}) b
where g.n <> b.n
