-- Silver | sucursales: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_sucursal as integer)                        as id_sucursal,
    {{ texto('nombre') }}                               as nombre_sucursal,
    cast(id_formato as integer)                         as id_formato,
    {{ nombre_propio('distrito') }}                     as distrito,
    {{ nombre_propio('ciudad') }}                       as ciudad,
    {{ nombre_propio('region') }}                       as region,
    cast(fecha_apertura as date)                        as fecha_apertura,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'SUCURSALES') }}
where id_sucursal is not null
{{ deduplicar('id_sucursal') }}
