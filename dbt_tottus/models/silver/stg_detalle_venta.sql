-- Silver | detalle de venta (grano del hecho principal)
select
    cast(d.id_detalle_venta as integer)                 as id_detalle_venta,
    cast(d.id_venta as integer)                         as id_venta,
    cast(d.id_producto as integer)                      as id_producto,
    cast(d.cantidad as integer)                         as cantidad,
    cast(d.precio_unitario as number(10,2))             as precio_unitario,
    cast(coalesce(d.descuento, 0) as number(10,2))      as descuento,
    {{ ts6('d.updated_at') }}                           as updated_at,
    {{ ts6("convert_timezone('UTC', d._load_ts)") }}    as _load_ts,
    cast(d._source_file as varchar)                     as _source_file
from {{ source('bronze', 'DETALLE_VENTA') }} d
where d.id_detalle_venta is not null
{% if target.name == 'dev' %}
  and d.id_venta in (select id_venta from {{ ref('stg_ventas') }})
{% endif %}
qualify row_number() over (partition by d.id_detalle_venta order by d.updated_at desc, d._load_ts desc) = 1
