-- Gold | dim_metodo_pago (tipo 1)
select
    id_metodo_pago                      as metodo_pago_sk,
    id_metodo_pago,
    metodo_pago
from {{ ref('stg_metodos_pago') }}
