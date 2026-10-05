{#
  Separación de capas por nombre:
  - prod: usa EXACTAMENTE la base y el esquema configurados
          (SILVER_DB.STAGING, SILVER_DB.SNAPSHOTS, GOLD_DB.MARTS)
  - dev:  todo va a DEV_DB, con el esquema prefijado por el del perfil
          (DEV_DB.DEV_JOSUE_STAGING, DEV_JOSUE_SNAPSHOTS, DEV_JOSUE_MARTS)
  Sin estas macros dbt generaría nombres como STAGING_STAGING.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}

{% macro generate_database_name(custom_database_name, node) -%}
    {%- if custom_database_name is not none and target.name == 'prod' -%}
        {{ custom_database_name | trim | upper }}
    {%- else -%}
        {{ target.database }}
    {%- endif -%}
{%- endmacro %}
