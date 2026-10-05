-- Silver | empleados: tipado explícito, limpieza de texto, deduplicación
select
    cast(id_empleado as integer)                        as id_empleado,
    {{ nombre_propio('nombres') }}                      as nombres,
    {{ nombre_propio('cargo') }}                        as cargo,
    cast(id_sucursal as integer)                        as id_sucursal,
    cast(fecha_ingreso as date)                         as fecha_ingreso,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'EMPLEADOS') }}
where id_empleado is not null
{{ deduplicar('id_empleado') }}
