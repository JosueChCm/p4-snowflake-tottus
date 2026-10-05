-- Silver | metodos_pago: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_metodo_pago as integer)                     as id_metodo_pago,
    {{ nombre_propio('descripcion') }}                  as metodo_pago,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'METODOS_PAGO') }}
where id_metodo_pago is not null
{{ deduplicar('id_metodo_pago') }}
