{#- Ley 29733: la masking policy se reaplica en cada corrida, porque dbt recrea la tabla -#}
{%- set tipo = 'iceberg table' if target.name == 'prod' else 'table' -%}
{{ config(post_hook=[
    "alter " ~ tipo ~ " {{ this }} modify column num_documento set masking policy GOLD_DB.MARTS.MP_DATO_PERSONAL"
]) }}

-- Gold | dim_cliente (SCD2) + fila "Cliente anónimo" para ventas sin cliente.
-- Privacidad: no expone la fecha de nacimiento, solo el rango de edad.
-- num_documento se enmascara con una masking policy (Fase 12).
with s as (select * from {{ ref('snap_clientes') }})
select
    s.dbt_scd_id                                                        as cliente_sk,
    s.id_cliente,
    s.nombres,
    s.tipo_documento,
    s.num_documento,
    case
        when s.fecha_nacimiento is null                                 then 'Sin dato'
        when datediff(year, s.fecha_nacimiento, current_date()) < 25    then '18-24'
        when datediff(year, s.fecha_nacimiento, current_date()) < 35    then '25-34'
        when datediff(year, s.fecha_nacimiento, current_date()) < 45    then '35-44'
        when datediff(year, s.fecha_nacimiento, current_date()) < 60    then '45-59'
        else '60+'
    end                                                                 as rango_edad,
    s.tiene_tarjeta_cmr,
    case when row_number() over (partition by s.id_cliente order by s.dbt_valid_from) = 1
         then cast('1900-01-01' as timestamp_ntz(6))
         else s.dbt_valid_from end                                      as valido_desde,
    coalesce(s.dbt_valid_to, cast('9999-12-31' as timestamp_ntz(6)))    as valido_hasta,
    (s.dbt_valid_to is null)                                            as es_actual
from s

union all

select
    '-1'                                    as cliente_sk,
    null                                    as id_cliente,
    'Cliente anónimo'                       as nombres,
    'N/A'                                   as tipo_documento,
    null                                    as num_documento,
    'Sin dato'                              as rango_edad,
    false                                   as tiene_tarjeta_cmr,
    cast('1900-01-01' as timestamp_ntz(6))  as valido_desde,
    cast('9999-12-31' as timestamp_ntz(6))  as valido_hasta,
    true                                    as es_actual
