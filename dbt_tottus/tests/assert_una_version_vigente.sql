-- Falla si alguna entidad SCD2 tiene más de una versión vigente
select 'producto' as entidad, id_producto as id, count(*) as vigentes
from {{ ref('dim_producto') }} where es_actual group by id_producto having count(*) > 1
union all
select 'cliente', id_cliente, count(*)
from {{ ref('dim_cliente') }} where es_actual and id_cliente is not null group by id_cliente having count(*) > 1
union all
select 'sucursal', id_sucursal, count(*)
from {{ ref('dim_sucursal') }} where es_actual group by id_sucursal having count(*) > 1
