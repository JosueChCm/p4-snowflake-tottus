-- Gold | dim_sucursal (SCD2): una fila por versión de tienda
with s   as (select * from {{ ref('snap_sucursales') }}),
     fmt as (select * from {{ ref('stg_formatos_tienda') }})
select
    s.dbt_scd_id                                                        as sucursal_sk,
    s.id_sucursal,
    s.nombre_sucursal,
    fmt.nombre_formato                                                  as formato,
    s.distrito,
    s.ciudad,
    s.region,
    s.fecha_apertura,
    case when row_number() over (partition by s.id_sucursal order by s.dbt_valid_from) = 1
         then cast('1900-01-01' as timestamp_ntz(6))
         else s.dbt_valid_from end                                      as valido_desde,
    coalesce(s.dbt_valid_to, cast('9999-12-31' as timestamp_ntz(6)))    as valido_hasta,
    (s.dbt_valid_to is null)                                            as es_actual
from s
left join fmt on s.id_formato = fmt.id_formato
