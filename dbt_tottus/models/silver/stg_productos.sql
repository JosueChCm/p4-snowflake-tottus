-- Silver | productos: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_producto as integer)                        as id_producto,
    {{ texto('nombre_producto') }}                      as nombre_producto,
    cast(id_subcategoria as integer)                    as id_subcategoria,
    cast(id_marca as integer)                           as id_marca,
    cast(id_proveedor as integer)                       as id_proveedor,
    cast(precio_unitario as number(10,2))               as precio_unitario,
    {{ mayus('unidad_medida') }}                        as unidad_medida,
    cast(activo as boolean)                             as activo,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'PRODUCTOS') }}
where id_producto is not null
{{ deduplicar('id_producto') }}
