-- Silver | clientes: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_cliente as integer)                         as id_cliente,
    {{ nombre_propio('nombres') }}                      as nombres,
    {{ mayus('tipo_documento') }}                       as tipo_documento,
    {{ texto('num_documento') }}                        as num_documento,      -- dato personal (se enmascara en Gold)
    cast(fecha_nacimiento as date)                      as fecha_nacimiento,   -- dato personal (Gold solo expone rango de edad)
    coalesce(cast(tiene_tarjeta_cmr as boolean), false) as tiene_tarjeta_cmr,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'CLIENTES') }}
where id_cliente is not null
{{ deduplicar('id_cliente') }}
