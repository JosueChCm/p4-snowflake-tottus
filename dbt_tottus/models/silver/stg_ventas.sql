-- Silver | ventas (cabecera). En dev: solo los últimos meses (muestra coherente)
select
    cast(id_venta as integer)                           as id_venta,
    cast(id_sucursal as integer)                        as id_sucursal,
    cast(id_cliente as integer)                         as id_cliente,       -- NULL = venta sin cliente
    cast(id_empleado as integer)                        as id_empleado,
    cast(id_metodo_pago as integer)                     as id_metodo_pago,
    {{ ts6('fecha_venta') }}                            as fecha_venta,
    cast(total as number(12,2))                         as total,
    {{ columnas_auditoria() }}
from {{ source('bronze', 'VENTAS') }}
where id_venta is not null
  {{ filtro_muestra_ventas('fecha_venta') }}
{{ deduplicar('id_venta') }}
