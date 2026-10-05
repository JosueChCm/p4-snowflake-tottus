-- Silver | formatos_tienda: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_formato as integer)                         as id_formato,
    {{ nombre_propio('nombre_formato') }}               as nombre_formato,
    {{ texto('descripcion') }}                          as descripcion,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'FORMATOS_TIENDA') }}
where id_formato is not null
{{ deduplicar('id_formato') }}
