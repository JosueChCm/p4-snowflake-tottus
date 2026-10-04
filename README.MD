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

Los pasos siguientes (OLTP, Data Factory, Snowflake, dbt, Power BI) se documentan conforme avanza el proyecto.

## Avance

- [x] Fase 1 — Entorno local
- [ ] Fase 2 — Cuentas, repositorio y presupuesto
- [ ] Fase 3 — Infraestructura de Azure (Terraform)
- [ ] Fase 4 — OLTP creado y migrado a Azure
- [ ] Fase 5 — Ingesta a Bronze con Data Factory
- [ ] Fase 6 — Configuración de Snowflake
- [ ] Fase 7 — Bronze en Snowflake
- [ ] Fase 8 — dbt: Silver, snapshots y Gold
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
