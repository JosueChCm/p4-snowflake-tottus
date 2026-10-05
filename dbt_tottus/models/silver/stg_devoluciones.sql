-- Silver | devoluciones
select
    cast(d.id_devolucion as integer)                    as id_devolucion,
    cast(d.id_venta as integer)                         as id_venta,
    cast(d.id_producto as integer)                      as id_producto,
    {{ texto('d.motivo') }}                             as motivo,
    {{ ts6('d.fecha_devolucion') }}                     as fecha_devolucion,
    cast(d.cantidad as integer)                         as cantidad,
    {{ ts6('d.updated_at') }}                           as updated_at,
    {{ ts6("convert_timezone('UTC', d._load_ts)") }}    as _load_ts,
    cast(d._source_file as varchar)                     as _source_file
from {{ source('bronze', 'DEVOLUCIONES') }} d
where d.id_devolucion is not null
{% if target.name == 'dev' %}
  and d.id_venta in (select id_venta from {{ ref('stg_ventas') }})
{% endif %}
qualify row_number() over (partition by d.id_devolucion order by d.updated_at desc, d._load_ts desc) = 1
