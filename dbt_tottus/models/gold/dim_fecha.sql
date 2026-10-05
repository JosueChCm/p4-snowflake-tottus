-- Gold | dim_fecha: un día por fila (2018-2028), generada con SQL (sin paquetes)
with dias as (
    select dateadd(day, row_number() over (order by seq4()) - 1, '2018-01-01'::date) as fecha
    from table(generator(rowcount => 4018))
)
select
    cast(to_char(fecha, 'YYYYMMDD') as integer)            as fecha_sk,
    fecha,
    year(fecha)                                             as anio,
    quarter(fecha)                                          as trimestre,
    month(fecha)                                            as mes,
    decode(month(fecha), 1,'Enero', 2,'Febrero', 3,'Marzo', 4,'Abril', 5,'Mayo', 6,'Junio',
           7,'Julio', 8,'Agosto', 9,'Septiembre', 10,'Octubre', 11,'Noviembre', 12,'Diciembre')
                                                            as nombre_mes,
    to_char(fecha, 'YYYY-MM')                               as anio_mes,
    day(fecha)                                              as dia,
    dayofweekiso(fecha)                                     as dia_semana,
    decode(dayofweekiso(fecha), 1,'Lunes', 2,'Martes', 3,'Miércoles', 4,'Jueves',
           5,'Viernes', 6,'Sábado', 7,'Domingo')            as nombre_dia,
    dayofweekiso(fecha) in (6, 7)                           as es_fin_de_semana
from dias
