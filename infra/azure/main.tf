# =====================================================================
# Proyecto 4 - DW Snowflake sobre Azure | Infraestructura de Azure
# Crea: lake ADLS Gen2 (bronze/silver/gold), Azure SQL (OLTP),
#       Data Factory, Key Vault y los permisos mínimos necesarios.
# Región: South Central US (misma región que la cuenta de Snowflake)
# =====================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
  }

  # Estado remoto. Los bloques backend no aceptan variables:
  # reemplaza "xx" por tus iniciales (igual que en el paso 3.1 del manual).
  backend "azurerm" {
    resource_group_name  = "rg-dw-p4"
    storage_account_name = "sttfstatep4jc"
    container_name       = "tfstate"
    key                  = "azure.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      # Al destruir, purga el Key Vault para poder recrearlo con el mismo nombre
      purge_soft_delete_on_destroy = true
    }
  }

  subscription_id = var.subscription_id

  # Los proveedores se registran a mano (ver README, paso 1): evita que
  # Terraform intente registrar decenas de servicios en la suscripción de estudiante.
  skip_provider_registration = true
}

# ---------------------------------------------------------------------
# Datos existentes
# ---------------------------------------------------------------------
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

data "azurerm_client_config" "actual" {}

locals {
  location = data.azurerm_resource_group.rg.location

  nombres = {
    lake      = "stdwtottus${var.sufijo}"
    sql       = "sql-tottus-${var.sufijo}-${var.sql_location}"
    adf       = "adf-tottus-p4-${var.sufijo}"
    key_vault = "kv-tottus-p4-${var.sufijo}"
  }

  capas = ["bronze", "silver", "gold"]

  tags = {
    proyecto = "p4-snowflake-tottus"
    curso    = "data-warehouse-undc-2026-ii"
    entorno  = "academico"
    iac      = "terraform"
  }
}

# =====================================================================
# 1. LAKE MEDALLION - ADLS Gen2 con un contenedor por capa
# =====================================================================
resource "azurerm_storage_account" "lake" {
  name                            = local.nombres.lake
  resource_group_name             = data.azurerm_resource_group.rg.name
  location                        = local.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  is_hns_enabled                  = true # ADLS Gen2: jerarquía real de carpetas
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "capa" {
  for_each              = toset(local.capas)
  name                  = each.key
  storage_account_name  = azurerm_storage_account.lake.name
  container_access_type = "private"
}

# =====================================================================
# 2. OLTP - Azure SQL Database (tier Basic)
# =====================================================================
resource "azurerm_mssql_server" "sql" {
  name                          = local.nombres.sql
  resource_group_name           = data.azurerm_resource_group.rg.name
  location                      = var.sql_location
  version                       = "12.0"
  administrator_login           = var.sql_admin_login
  administrator_login_password  = var.sql_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true # restringido por las reglas de firewall
  tags                          = local.tags
}

resource "azurerm_mssql_database" "oltp" {
  name                 = "tottus_oltp"
  server_id            = azurerm_mssql_server.sql.id
  sku_name             = "Basic" # se sube a S2 solo durante la carga masiva (manual, paso 4.4)
  max_size_gb          = 2
  collation            = "SQL_Latin1_General_CP1_CI_AS"
  storage_account_type = "Local" # backups locales: más barato
  tags                 = local.tags

  lifecycle {
    # El tier se cambia temporalmente por CLI; Terraform no debe revertirlo a mitad de una carga
    ignore_changes = [sku_name]
  }
}

# 0.0.0.0 = permitir servicios de Azure (Data Factory)
resource "azurerm_mssql_firewall_rule" "servicios_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "mi_pc" {
  name             = "PC-desarrollo"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = var.mi_ip
  end_ip_address   = var.mi_ip
}

# =====================================================================
# 3. ORQUESTADOR - Azure Data Factory con identidad administrada
# =====================================================================
resource "azurerm_data_factory" "adf" {
  name                   = local.nombres.adf
  resource_group_name    = data.azurerm_resource_group.rg.name
  location               = local.location
  public_network_enabled = true
  tags                   = local.tags

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    # La integración con GitHub se configura desde ADF Studio (manual, paso 5.4);
    # sin esto, Terraform intentaría eliminarla en cada apply.
    ignore_changes = [github_configuration, vsts_configuration, global_parameter]
  }
}

# =====================================================================
# 4. SECRETOS - Key Vault con autorización RBAC
# =====================================================================
resource "azurerm_key_vault" "kv" {
  name                       = local.nombres.key_vault
  resource_group_name        = data.azurerm_resource_group.rg.name
  location                   = local.location
  tenant_id                  = data.azurerm_client_config.actual.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags
}

# =====================================================================
# 5. PERMISOS (mínimo privilegio)
# =====================================================================

# --- Data Factory: escribe SOLO en el contenedor bronze ---
resource "azurerm_role_assignment" "adf_bronze" {
  scope                = azurerm_storage_container.capa["bronze"].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# --- Data Factory: lee secretos (contraseña SQL, llave de Snowflake) ---
resource "azurerm_role_assignment" "adf_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# --- Tú: administras secretos ---
resource "azurerm_role_assignment" "yo_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.actual.object_id
}

# --- Tú: ves y gestionas el contenido de los contenedores (portal y CLI) ---
resource "azurerm_role_assignment" "yo_lake" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.actual.object_id
}

# Nota: los permisos de la aplicación de Snowflake sobre bronze/silver/gold
# se asignan en la Fase 6 (paso 6.4), porque esa aplicación solo existe en
# el directorio después de aceptar el consentimiento de Snowflake.
