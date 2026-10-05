-- Silver | proveedores: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_proveedor as integer)                       as id_proveedor,
    {{ texto('razon_social') }}                         as razon_social,
    {{ texto('ruc') }}                                  as ruc,
    {{ nombre_propio('contacto') }}                     as contacto,
    {{ texto('telefono') }}                             as telefono,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'PROVEEDORES') }}
where id_proveedor is not null
{{ deduplicar('id_proveedor') }}
