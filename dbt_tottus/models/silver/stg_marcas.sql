-- Silver | marcas: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_marca as integer)                           as id_marca,
    {{ texto('nombre_marca') }}                         as nombre_marca,
    cast(es_marca_propia as boolean)                    as es_marca_propia,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'MARCAS') }}
where id_marca is not null
{{ deduplicar('id_marca') }}
