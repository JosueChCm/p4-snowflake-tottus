-- Gold | dim_empleado (tipo 1: estado actual)
select
    e.id_empleado                       as empleado_sk,
    e.id_empleado,
    e.nombres,
    e.cargo,
    e.id_sucursal,
    e.fecha_ingreso
from {{ ref('stg_empleados') }} e
