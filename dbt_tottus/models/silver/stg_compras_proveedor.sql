-- Silver | compras_proveedor: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_compra as integer)                          as id_compra,
    cast(id_proveedor as integer)                       as id_proveedor,
    cast(id_sucursal as integer)                        as id_sucursal,
    {{ ts6('fecha_compra') }}                           as fecha_compra,
    cast(total as number(12,2))                         as total,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'COMPRAS_PROVEEDOR') }}
where id_compra is not null
{{ deduplicar('id_compra') }}
