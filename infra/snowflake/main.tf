# =====================================================================
# Proyecto 4 - DW Snowflake sobre Azure | Infraestructura de Snowflake
# Cuenta: JULTITQ-IC99482 (AZURE_SOUTHCENTRALUS)
# Crea: monitor de recursos, warehouse X-Small, 5 bases de datos,
#       esquemas por capa y roles funcionales.
# Las integraciones con Azure y los grants detallados van en
# snowflake/01_integraciones.sql y snowflake/02_grants.sql
# (requieren un consentimiento manual en Azure).
# =====================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 1.0"
    }
  }

  # Mismo contenedor de estado que Azure, con otra clave
  backend "azurerm" {
    resource_group_name  = "rg-dw-p4"
    storage_account_name = "sttfstatep4jc"
    container_name       = "tfstate"
    key                  = "snowflake.tfstate"
    use_azuread_auth     = true
  }
}

provider "snowflake" {
  organization_name = var.sf_organization
  account_name      = var.sf_account
  user              = var.sf_user
  role              = "ACCOUNTADMIN"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(pathexpand(var.sf_private_key_path))

  # Si "terraform plan" indica que un recurso es una "preview feature",
  # descomenta y agrega el nombre que muestre el mensaje, por ejemplo:
  # preview_features_enabled = ["snowflake_resource_monitor_resource"]
}

locals {
  bases = {
    BRONZE_DB = "Capa Bronze: copia exacta del OLTP (full load)"
    SILVER_DB = "Capa Silver: datos limpios y snapshots SCD2 (Iceberg en contenedor silver)"
    GOLD_DB   = "Capa Gold: modelo estrella (Iceberg en contenedor gold)"
    OPS_DB    = "Operación: repositorio Git, proyecto dbt y bitácora de corridas"
    DEV_DB    = "Desarrollo local de dbt (target dev)"
  }

  esquemas = {
    "BRONZE_DB.RAW"       = { db = "BRONZE_DB", name = "RAW", comment = "Tablas crudas del OLTP Tottus" }
    "SILVER_DB.STAGING"   = { db = "SILVER_DB", name = "STAGING", comment = "Modelos stg_* de dbt" }
    "SILVER_DB.SNAPSHOTS" = { db = "SILVER_DB", name = "SNAPSHOTS", comment = "Snapshots SCD2 de dbt" }
    "GOLD_DB.MARTS"       = { db = "GOLD_DB", name = "MARTS", comment = "Dimensiones y hechos" }
    "OPS_DB.ADMIN"        = { db = "OPS_DB", name = "ADMIN", comment = "Objetos de despliegue y auditoría" }
  }

  roles = {
    ROL_INGESTA = "Carga BRONZE_DB desde el contenedor bronze"
    ROL_DBT     = "Transforma: lee Bronze, escribe Silver, Gold y DEV_DB"
    ROL_ORQ     = "Orquestación desde ADF: hereda ROL_INGESTA y ROL_DBT"
    ROL_POWERBI = "Solo lectura de GOLD_DB.MARTS"
  }
}

# ---------------------------------------------------------------------
# Control de costos
# ---------------------------------------------------------------------
resource "snowflake_resource_monitor" "rm" {
  name            = "RM_TOTTUS"
  credit_quota    = var.creditos_mensuales
  notify_triggers = [50, 75]
  suspend_trigger = 90
}

resource "snowflake_warehouse" "wh" {
  name                = "WH_TOTTUS"
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = "true"
  initially_suspended = true
  resource_monitor    = snowflake_resource_monitor.rm.name
  comment             = "Warehouse único del Proyecto 4"
}

# ---------------------------------------------------------------------
# Bases de datos y esquemas (una base por capa = separación de capas)
# ---------------------------------------------------------------------
resource "snowflake_database" "db" {
  for_each = local.bases
  name     = each.key
  comment  = each.value
}

resource "snowflake_schema" "sch" {
  for_each = local.esquemas
  database = snowflake_database.db[each.value.db].name
  name     = each.value.name
  comment  = each.value.comment
}

# ---------------------------------------------------------------------
# Roles funcionales (cuelgan de SYSADMIN, buena práctica de Snowflake)
# ---------------------------------------------------------------------
resource "snowflake_account_role" "rol" {
  for_each = local.roles
  name     = each.key
  comment  = each.value
}

resource "snowflake_grant_account_role" "a_sysadmin" {
  for_each         = local.roles
  role_name        = snowflake_account_role.rol[each.key].name
  parent_role_name = "SYSADMIN"
}

# ROL_ORQ = ROL_INGESTA + ROL_DBT
resource "snowflake_grant_account_role" "orq_ingesta" {
  role_name        = snowflake_account_role.rol["ROL_INGESTA"].name
  parent_role_name = snowflake_account_role.rol["ROL_ORQ"].name
}

resource "snowflake_grant_account_role" "orq_dbt" {
  role_name        = snowflake_account_role.rol["ROL_DBT"].name
  parent_role_name = snowflake_account_role.rol["ROL_ORQ"].name
}

# Tu usuario recibe los roles de trabajo
resource "snowflake_grant_account_role" "usuario" {
  for_each  = toset(["ROL_ORQ", "ROL_POWERBI"])
  role_name = snowflake_account_role.rol[each.key].name
  user_name = var.sf_user
}
