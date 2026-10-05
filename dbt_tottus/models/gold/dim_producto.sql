-- Gold | dim_producto (SCD2): una fila por VERSIÓN de producto
-- La primera versión arranca en 1900-01-01 para cubrir las ventas anteriores al primer snapshot.
with s   as (select * from {{ ref('snap_productos') }}),
     sub as (select * from {{ ref('stg_subcategorias') }}),
     cat as (select * from {{ ref('stg_categorias') }}),
     mar as (select * from {{ ref('stg_marcas') }}),
     pro as (select * from {{ ref('stg_proveedores') }})
select
    s.dbt_scd_id                                                        as producto_sk,
    s.id_producto,
    s.nombre_producto,
    sub.nombre_subcategoria                                             as subcategoria,
    cat.nombre_categoria                                                as categoria,
    mar.nombre_marca                                                    as marca,
    coalesce(mar.es_marca_propia, false)                                as es_marca_propia,
    pro.razon_social                                                    as proveedor,
    s.unidad_medida,
    s.precio_unitario                                                   as precio_lista,
    s.activo,
    case when row_number() over (partition by s.id_producto order by s.dbt_valid_from) = 1
         then cast('1900-01-01' as timestamp_ntz(6))
         else s.dbt_valid_from end                                      as valido_desde,
    coalesce(s.dbt_valid_to, cast('9999-12-31' as timestamp_ntz(6)))    as valido_hasta,
    (s.dbt_valid_to is null)                                            as es_actual
from s
left join sub on s.id_subcategoria = sub.id_subcategoria
left join cat on sub.id_categoria  = cat.id_categoria
left join mar on s.id_marca        = mar.id_marca
left join pro on s.id_proveedor    = pro.id_proveedor
