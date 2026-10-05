-- Falla si dos versiones de un mismo producto se solapan en el tiempo
with v as (
    select id_producto, valido_desde, valido_hasta,
           lead(valido_desde) over (partition by id_producto order by valido_desde) as siguiente_desde
    from {{ ref('dim_producto') }}
)
select * from v
where siguiente_desde is not null and siguiente_desde < valido_hasta
