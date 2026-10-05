output "warehouse" {
  value = snowflake_warehouse.wh.name
}

output "bases_de_datos" {
  value = keys(local.bases)
}

output "esquemas" {
  value = keys(local.esquemas)
}

output "roles" {
  value = keys(local.roles)
}
