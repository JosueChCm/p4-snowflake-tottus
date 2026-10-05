-- Silver | detalle_compra: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_detalle_compra as integer)                  as id_detalle_compra,
    cast(id_compra as integer)                          as id_compra,
    cast(id_producto as integer)                        as id_producto,
    cast(cantidad as integer)                           as cantidad,
    cast(costo_unitario as number(10,2))                as costo_unitario,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'DETALLE_COMPRA') }}
where id_detalle_compra is not null
{{ deduplicar('id_detalle_compra') }}
