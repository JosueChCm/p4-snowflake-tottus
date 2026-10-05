# Proyecto 4 — Data Warehouse en la Nube con Snowflake sobre Azure

**Curso:** Data Warehouse — VI ciclo, Ingeniería de Sistemas, Universidad Nacional de Cañete (UNDC), semestre 2026-II
**Docente:** Ing. Jhonatan Echaccaya
**Autor:** Josue Chulluncuy Cambillo
**Caso de negocio:** Tottus — ventas minoristas

## Descripción

Data Warehouse en Snowflake alimentado desde un OLTP en Azure SQL Database. Cada corrida realiza una
**carga completa** (full load: `TRUNCATE` + `COPY INTO`) y la historia de productos, clientes y tiendas se
conserva con **Snapshots de dbt (SCD2)**. Las capas Medallion están **físicamente separadas**: cada una vive
en su propio contenedor de ADLS Gen2 y en su propia base de datos de Snowflake.

## Arquitectura

```
Azure SQL Database (OLTP, 15 tablas)
        │  Azure Data Factory — Copy (Parquet, una carpeta por corrida)
        ▼
ADLS Gen2 · contenedor bronze  ──►  Snowflake BRONZE_DB.RAW   (TRUNCATE + COPY INTO)
                                            │  dbt: stg_* + snapshots SCD2
                                            ▼
ADLS Gen2 · contenedor silver  ◄──  Snowflake SILVER_DB       (tablas Iceberg)
                                            │  dbt: modelo estrella
                                            ▼
ADLS Gen2 · contenedor gold    ◄──  Snowflake GOLD_DB.MARTS   (tablas Iceberg)
                                            │
                                            ▼
                                   Power BI Service (DirectQuery)
```

| Capa   | Contenedor ADLS | Base Snowflake                     | Contenido                              |
|--------|-----------------|------------------------------------|----------------------------------------|
| Bronze | `bronze`        | `BRONZE_DB.RAW`                    | Copia exacta del OLTP + auditoría      |
| Silver | `silver`        | `SILVER_DB.STAGING` / `.SNAPSHOTS` | Datos limpios + historia SCD2          |
| Gold   | `gold`          | `GOLD_DB.MARTS`                    | Estrella: dimensiones + `fact_ventas`  |

**Región de todo el proyecto:** Azure South Central US (`southcentralus`) — Snowflake `AZURE_SOUTHCENTRALUS`.

## Tecnologías

| Componente      | Herramienta                                         |
|-----------------|-----------------------------------------------------|
| Origen OLTP     | Azure SQL Database (tier Basic)                     |
| Lake Medallion  | Azure Data Lake Storage Gen2                        |
| Orquestación    | Azure Data Factory                                  |
| Secretos        | Azure Key Vault                                     |
| IaC             | Terraform (Azure + Snowflake)                       |
| Data Warehouse  | Snowflake Enterprise · tablas Apache Iceberg (v2)   |
| Transformación  | dbt-core (desarrollo) + dbt Projects on Snowflake   |
| Versionado      | Git + GitHub                                        |
| Dashboard       | Power BI Service (DirectQuery)                      |

## Estructura del repositorio

```
p4-snowflake-tottus/
├── infra/azure/        Terraform de Azure (lake, SQL, ADF, Key Vault, permisos)
├── infra/snowflake/    Terraform de Snowflake (warehouse, bases, esquemas, roles)
├── oltp/               DDL, generador de datos, carga a Azure, validaciones, script de demo
├── adf/                Data Factory versionado (integración Git)
├── snowflake/          Scripts SQL: integraciones, grants, Bronze, despliegue, seguridad
├── dbt_tottus/         Proyecto dbt (Silver, snapshots, Gold, tests)
├── powerbi/            Reporte y medidas DAX
└── docs/               Diagramas, diccionario de datos, informe
```

## Requisitos locales

Git, Azure CLI, Terraform ≥ 1.7, Python 3.11/3.12, ODBC Driver 18 for SQL Server,
Azure Data Studio, Power BI Desktop.

## Puesta en marcha

### 1. Registrar los proveedores de Azure (una sola vez por suscripción)

```bash
for NS in Microsoft.Storage Microsoft.Sql Microsoft.DataFactory Microsoft.KeyVault; do
  az provider register --namespace $NS
done
az provider list --query "[?namespaceState=='Registered'].namespace" -o tsv | \
  grep -E "Storage|Sql|DataFactory|KeyVault"
```

### 2. Resource group y cuenta del estado de Terraform

```bash
az group create --name rg-dw-p4 --location southcentralus

az storage account create -n sttfstatep4xx -g rg-dw-p4 -l southcentralus \
   --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false
az storage container create --name tfstate --account-name sttfstatep4xx --auth-mode key

YO=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id $YO --assignee-principal-type User \
   --role "Storage Blob Data Contributor" \
   --scope $(az storage account show -n sttfstatep4xx -g rg-dw-p4 --query id -o tsv)
```

> Reemplaza `xx` por tus iniciales en minúsculas aquí **y** en el bloque `backend` de `infra/azure/main.tf`.

### 3. Infraestructura de Azure

```bash
cd infra/azure
cp terraform.tfvars.example terraform.tfvars      # completar valores
export TF_VAR_sql_admin_password='Una-Contraseña-Larga-123!'
terraform init
terraform fmt && terraform validate
terraform plan -out p4.plan
terraform apply p4.plan
terraform output

az keyvault secret set --vault-name "$(terraform output -raw key_vault_name)" \
   --name sql-admin-password --value "$TF_VAR_sql_admin_password"
```

### 4. OLTP: adaptar la base del Proyecto 2 y migrarla a Azure

El origen es la base **Tottus_OLTP** del Proyecto 2 (SQL Server local, 15 tablas), adaptada para este proyecto.

| Orden | Archivo | Dónde se ejecuta | Qué hace |
|-------|---------|------------------|----------|
| 1 | `oltp/01_adaptar_scd2.sql` | SSMS · base **local** | Compatibilidad 160, columna `updated_at DATETIME2(6)` en las 15 tablas, relleno histórico, triggers SCD2 (Productos, Clientes, Sucursales) e índices |
| 2 | `oltp/02_ampliar_volumen.sql` | SSMS · base **local** | Lleva `Ventas` a 110 000 filas y `Detalle_Venta` a ≈ 800 000, con datos coherentes |
| 3 | `oltp/validaciones.sql` | SSMS · base **local** | Conteos y totales de referencia (guardar captura) |
| 4 | `oltp/migrar_a_azure.sh` | Git Bash | Exporta `.bacpac` e importa en `tottus_oltp` de Azure (S2 temporal, vuelve a Basic) |
| 5 | `oltp/validaciones.sql` | Azure Data Studio · base **Azure** | Debe dar los mismos resultados que el paso 3 |
| — | `oltp/inserts_demo.sql` | Azure Data Studio · base **Azure** | Solo en la exposición: 3 ventas + cambio de precio |

```bash
# Herramienta de migración (una vez)
dotnet tool install -g microsoft.sqlpackage

# Migración (desde la raíz del repositorio)
export TF_VAR_sql_admin_password='...'
export AZ_SQL_SERVER=sql-tottus-jc-centralus     # nombre real (terraform output)
bash oltp/migrar_a_azure.sh
```

Modelo del OLTP:

| Grupo | Tablas |
|-------|--------|
| Ventas | `Ventas`, `Detalle_Venta`, `Devoluciones` |
| Compras | `Compras_Proveedor`, `Detalle_Compra` |
| Producto | `Productos` (SCD2), `Subcategorias`, `Categorias`, `Marcas`, `Proveedores` |
| Tiendas y personas | `Sucursales` (SCD2), `Formatos_Tienda`, `Empleados`, `Clientes` (SCD2), `Metodos_Pago` |

### 5. Ingesta a Bronze con Data Factory

Configurado en ADF Studio (exportado en `adf/`): servicios vinculados `ls_keyvault`, `ls_sql_oltp`,
`ls_adls_lake`; datasets `ds_sql_tabla` y `ds_parquet_bronze`; canalización `pl_ingesta_bronze`
(ForEach de 15 tablas → Copy, DIU 4). Cada corrida escribe en
`bronze/<tabla>/carga=<yyyyMMdd_HHmmss>/<tabla>.parquet`; si `carga_id` llega vacío se genera
con la hora de inicio (zona Lima).

### 6. Snowflake (cuenta `JULTITQ-IC99482`, región AZURE_SOUTHCENTRALUS)

| Orden | Archivo | Dónde / rol | Qué hace |
|-------|---------|-------------|----------|
| 1 | `infra/snowflake/*.tf` | Git Bash · `terraform apply` | Monitor de recursos, `WH_TOTTUS`, bases BRONZE/SILVER/GOLD/OPS/DEV, esquemas y roles |
| 2 | `snowflake/01_integraciones.sql` (partes 1 y 2) | Snowsight · ACCOUNTADMIN | Storage integration (bronze) y external volumes (silver, gold); muestra las URL de consentimiento |
| 3 | Consentimiento | Navegador | Abrir `AZURE_CONSENT_URL` y aceptar |
| 4 | `snowflake/asignar_permisos_azure.sh` | Git Bash | Reader en bronze, Contributor en silver y gold para la app de Snowflake |
| 5 | `snowflake/02_grants.sql` | Snowsight · ACCOUNTADMIN | Permisos por capa y usuarios `SVC_ADF`, `SVC_PBI` |
| 6 | `snowflake/prueba_humo_iceberg.sql` | Snowsight | Escribe Iceberg en silver y gold: valida la arquitectura |
| 7 | `snowflake/03_bronze.sql` | Snowsight · ROL_INGESTA | Stage, 15 tablas Bronze y `SP_CARGAR_BRONZE` (TRUNCATE + COPY INTO) |

```bash
cd infra/snowflake
terraform init
terraform validate
terraform plan -out sf.plan
terraform apply sf.plan
```

La llave privada (`~/.snowflake/josue_key.p8`) nunca se sube al repositorio.

### 7. dbt: Silver, snapshots SCD2 y Gold

```
dbt_tottus/
├── dbt_project.yml          capas: silver -> SILVER_DB.STAGING · snapshots -> SILVER_DB.SNAPSHOTS · gold -> GOLD_DB.MARTS
├── profiles.yml             perfil para dbt Projects on Snowflake (sin secretos)
├── profiles_local.example.yml  plantilla de ~/.dbt/profiles.yml (dev y prod)
├── macros/                  nombres_capas.sql (separación de capas), limpieza.sql (ts6, texto, deduplicar…)
├── models/sources.yml       15 tablas de BRONZE_DB.RAW (freshness con _LOAD_TS)
├── models/silver/           15 stg_* + _silver.yml (unique, not_null, relationships)
├── snapshots/snapshots.yml  snap_productos, snap_clientes, snap_sucursales (timestamp, hard_deletes)
├── models/gold/             dim_fecha, dim_producto, dim_cliente, dim_sucursal, dim_empleado,
│                            dim_metodo_pago, fact_ventas, fact_devoluciones + _gold.yml
└── tests/                   vigencia única, sin solapes, conciliación de filas y montos, valores positivos
```

| Target | Dónde corre | Destino | Formato | Datos |
|--------|-------------|---------|---------|-------|
| `dev`  | tu PC (dbt-core) | `DEV_DB.DEV_JOSUE_*` | tablas nativas | últimos 3 meses de ventas |
| `prod` | Snowflake (dbt Projects, disparado por ADF) | `SILVER_DB`, `GOLD_DB` | Iceberg en `silver` / `gold` | completo |

```bash
mkdir -p ~/.dbt && cp dbt_tottus/profiles_local.example.yml ~/.dbt/profiles.yml   # ajustar ruta de la llave
export DBT_PROFILES_DIR=~/.dbt
cd dbt_tottus
dbt debug
dbt build                       # dev: modelos + snapshots + tests
dbt docs generate && dbt docs serve
dbt build --target prod         # una vez: valida Iceberg con datos completos
```

### 8. dbt en la nube, orquestación y bitácora

| Orden | Archivo | Dónde / rol | Qué hace |
|-------|---------|-------------|----------|
| 1 | `snowflake/05_bitacora.sql` | Snowsight · ROL_ORQ | Tabla `LOG_CORRIDAS`, `SP_REGISTRAR_CORRIDA` y vista `V_CORRIDAS` (duración) |
| 2 | `snowflake/06_seguridad.sql` (parte 1) | Snowsight · ACCOUNTADMIN | Masking policy del DNI (la aplica dbt con un post-hook) |
| 3 | `snowflake/04_deploy_dbt.sql` | Snowsight | Repositorio Git en Snowflake, `DBT PROJECT` y `SP_EJECUTAR_DBT` |
| 4 | `adf/ls_snowflake.json` | ADF Studio | Servicio vinculado Snowflake (SVC_ADF, llave en Key Vault) |
| 5 | `adf/pl_p4_full.json` | ADF Studio | Orquestador de punta a punta |

Flujo de `pl_p4_full`:

```
set_carga_id → sc_log_inicio → ep_ingesta_bronze → sc_cargar_bronze → sc_dbt_build → sc_log_ok
                                                                           └─(falla/omitida)→ sc_log_error → fail_corrida
```

### 9. Dashboard, seguridad y evidencias

- `powerbi/medidas_dax.txt` — conexión DirectQuery, relaciones, 19 medidas y 6 páginas.
- `snowflake/06_seguridad.sql` — pruebas de enmascaramiento y acceso por rol; auditoría con `ACCOUNT_USAGE`.
- `snowflake/07_validaciones.sql` — conciliación Bronze = Silver = Gold, historia SCD2, duración de corridas.
- `docs/diccionario_datos.md` — capas, tablas y columnas (marca de datos sensibles, Ley 29733).
- `docs/guion_demo.md` — guion de la prueba en vivo y preguntas probables.

## Seguridad aplicada

| Control | Implementación |
|---------|----------------|
| Separación de capas | Un contenedor y una base por capa; `ROL_POWERBI` solo lee `GOLD_DB.MARTS` |
| Datos personales | `MP_DATO_PERSONAL` enmascara el DNI; la fecha de nacimiento no pasa a Gold (solo rango de edad) |
| Secretos | Key Vault (contraseña SQL, llave privada de SVC_ADF); nada en el repositorio |
| Autenticación | Identidades administradas (ADF) y pares de llaves RSA (Terraform, dbt, ADF) |
| Mínimo privilegio | Snowflake: Reader en bronze, Contributor en silver/gold; ADF solo escribe en bronze |
| Auditoría | `_LOAD_TS`, `_SOURCE_FILE`, `LOG_CORRIDAS`, monitor de ADF, `ACCESS_HISTORY`, `LOGIN_HISTORY` |
| Costos | Presupuesto con alertas, DIU 4, SQL Basic, `RM_TOTTUS` (suspende al 90 %), `AUTO_SUSPEND = 60` |

## Avance

- [x] Fase 1 — Entorno local
- [x] Fase 2 — Cuentas, repositorio y presupuesto
- [x] Fase 3 — Infraestructura de Azure (Terraform)
- [x] Fase 4 — OLTP creado y migrado a Azure
- [x] Fase 5 — Ingesta a Bronze con Data Factory
- [x] Fase 6 — Configuración de Snowflake
- [x] Fase 7 — Bronze en Snowflake
- [x] Fase 8 — dbt: Silver, snapshots y Gold
- [ ] Fase 9 — dbt en la nube
- [ ] Fase 10 — Orquestación completa
- [ ] Fase 11 — Dashboard en Power BI
- [ ] Fase 12 — Seguridad y privacidad
- [ ] Fase 13 — Validación y documentación

## Seguridad

- Ninguna credencial se guarda en el repositorio: contraseñas y llaves van en variables de entorno o en Azure Key Vault.
- `.gitignore` excluye estados de Terraform, archivos `.tfvars`, llaves `.p8` y los datos generados.
- Los servicios se autentican con identidades administradas (ADF) y pares de llaves RSA (Snowflake).

## Costos

Proyecto diseñado para operar con USD 100 de Azure for Students: ADF sin triggers frecuentes, DIU = 2,
SQL en tier Basic y todo el cómputo pesado en Snowflake. Presupuesto con alertas al 25 %, 50 % y 75 %.
