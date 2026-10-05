-- Cantidades y precios deben ser positivos; el descuento no puede superar el monto bruto
select id_detalle_venta, cantidad, precio_cobrado, descuento, monto_bruto
from {{ ref('fact_ventas') }}
where cantidad <= 0
   or precio_cobrado < 0
   or descuento < 0
   or descuento > monto_bruto
