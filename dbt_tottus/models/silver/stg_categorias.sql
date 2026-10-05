-- Silver | categorias: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_categoria as integer)                       as id_categoria,
    {{ nombre_propio('nombre_categoria') }}             as nombre_categoria,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'CATEGORIAS') }}
where id_categoria is not null
{{ deduplicar('id_categoria') }}
