# =====================================================================
# Salidas: valores que usarás en las fases siguientes (ninguno es secreto)
# Consultar con: terraform output
# =====================================================================

output "region" {
  value = local.location
}

output "storage_lake_name" {
  description = "Nombre del lake (01_integraciones.sql y Data Factory)."
  value       = azurerm_storage_account.lake.name
}

output "lake_blob_urls_snowflake" {
  description = "URLs para la storage integration y los external volumes de Snowflake."
  value = {
    for capa in local.capas :
    capa => "azure://${azurerm_storage_account.lake.name}.blob.core.windows.net/${capa}/"
  }
}

output "storage_lake_id" {
  description = "ID del lake (asignación de roles a Snowflake en el paso 6.4)."
  value       = azurerm_storage_account.lake.id
}

output "sql_server_fqdn" {
  description = "Servidor para Azure Data Studio y cargar_azure.py."
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "sql_database_name" {
  value = azurerm_mssql_database.oltp.name
}

output "data_factory_name" {
  value = azurerm_data_factory.adf.name
}

output "data_factory_principal_id" {
  description = "Identidad administrada de ADF."
  value       = azurerm_data_factory.adf.identity[0].principal_id
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "tenant_id" {
  description = "Tenant de Azure (AZURE_TENANT_ID en los scripts de Snowflake)."
  value       = data.azurerm_client_config.actual.tenant_id
}
