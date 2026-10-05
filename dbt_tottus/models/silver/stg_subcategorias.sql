-- Silver | subcategorias: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_subcategoria as integer)                    as id_subcategoria,
    {{ nombre_propio('nombre_subcategoria') }}          as nombre_subcategoria,
    cast(id_categoria as integer)                       as id_categoria,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'SUBCATEGORIAS') }}
where id_subcategoria is not null
{{ deduplicar('id_subcategoria') }}
