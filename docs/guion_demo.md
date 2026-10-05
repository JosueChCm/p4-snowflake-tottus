# Guion de la prueba en vivo (≈ 6 minutos)

**Antes de empezar (10 min antes):**
- [ ] Agregar la IP de la red actual al firewall de Azure SQL
      (`az sql server firewall-rule create ... --start-ip-address $(curl -s ifconfig.me) ...`).
- [ ] SSMS conectado a **Azure** (`sql-tottus-jc-centralus`) con `oltp/inserts_demo.sql` abierto.
- [ ] ADF Studio en `pl_p4_full`; Snowsight con `snowflake/07_validaciones.sql`; Power BI Service abierto.
- [ ] Anotar el ID del producto que el script elegirá (el más vendido) o fijarlo en `@id_producto`.

| Min. | Acción | Qué mostrar / decir |
|------|--------|---------------------|
| 0:00 | Power BI: página Resumen e Historial de precios | Estado inicial: N° Ventas y versiones del producto |
| 0:30 | SSMS (Azure): ejecutar `inserts_demo.sql` | 3 ventas nuevas + precio +15 % (el trigger actualiza `updated_at`) |
| 1:00 | ADF: `pl_p4_full` → Agregar desencadenador → Desencadenar ahora | Se genera `carga_id` automático |
| 1:30 | Monitor de ADF | Actividades: log → ingesta → full load → dbt → log |
| 2:00 | Portal: contenedor `bronze` | Nueva carpeta `carga=…` (historia cruda inmutable) |
| 3:00 | Contenedores `silver` y `gold` | Capas físicamente separadas (Iceberg: data + metadata) |
| ≈4:00 | Snowsight: historia del producto (`07_validaciones.sql`, sección 4) | Versión anterior cerrada (`VALIDO_HASTA`), nueva vigente |
| ≈4:30 | Power BI: Actualizar | N° Ventas +3; nueva versión en Historial de precios |
| 5:00 | Snowsight con `ROL_POWERBI` (`06_seguridad.sql`, 2c y 2d) | DNI enmascarado; sin acceso a Bronze/Silver |
| 5:30 | `SELECT * FROM OPS_DB.ADMIN.V_CORRIDAS` | Duración de punta a punta registrada |

**Preguntas probables:**
- *¿Por qué full load si existe CDC?* — Simplicidad y consistencia: cada corrida es una foto completa;
  el costo es reescribir Bronze/Silver, y la historia se conserva en los snapshots SCD2 y en las carpetas de bronze.
- *¿timestamp o check en el snapshot?* — `timestamp`, porque el OLTP mantiene `updated_at` con triggers; `check`
  compararía columnas y sería más costoso.
- *¿Por qué Iceberg?* — Para que Silver y Gold vivan como archivos en sus contenedores (separación física y
  formato abierto, legible por otros motores).
- *¿Estrella o copo de nieve?* — Estrella: menos joins para Power BI; Snowflake comprime por columnas.
