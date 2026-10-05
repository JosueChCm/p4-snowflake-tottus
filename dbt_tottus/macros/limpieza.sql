{# =====================================================================
   Helpers de limpieza usados en los modelos stg_*
   ===================================================================== #}

{# Timestamp compatible con Apache Iceberg (precisión de microsegundos) #}
{% macro ts6(columna) -%}
    cast({{ columna }} as timestamp_ntz(6))
{%- endmacro %}

{# Texto limpio: sin espacios sobrantes; '' se convierte en NULL #}
{% macro texto(columna) -%}
    nullif(trim(cast({{ columna }} as varchar)), '')
{%- endmacro %}

{# Texto en formato Nombre Propio #}
{% macro nombre_propio(columna) -%}
    initcap(nullif(trim(cast({{ columna }} as varchar)), ''))
{%- endmacro %}

{# Texto en mayúsculas (códigos, categorías cortas) #}
{% macro mayus(columna) -%}
    upper(nullif(trim(cast({{ columna }} as varchar)), ''))
{%- endmacro %}

{# Columnas de auditoría que conserva toda tabla stg_* #}
{% macro columnas_auditoria() -%}
    {{ ts6('updated_at') }}                                  as updated_at,
    {{ ts6("convert_timezone('UTC', _load_ts)") }}           as _load_ts,
    cast(_source_file as varchar)                            as _source_file
{%- endmacro %}

{# Deduplicación por clave: conserva la versión más reciente #}
{% macro deduplicar(clave) -%}
    qualify row_number() over (partition by {{ clave }} order by updated_at desc, _load_ts desc) = 1
{%- endmacro %}

{# Filtro de muestra para dev: últimos N meses de ventas #}
{% macro filtro_muestra_ventas(columna_fecha) -%}
    {%- if target.name == 'dev' -%}
    and {{ columna_fecha }} >= (
        select dateadd(month, -{{ var('meses_muestra_dev') }}, max(fecha_venta))
        from {{ source('bronze', 'VENTAS') }}
    )
    {%- endif -%}
{%- endmacro %}
