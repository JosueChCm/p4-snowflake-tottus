# =====================================================================
# Variables de la infraestructura de Azure
# Los valores van en terraform.tfvars (ignorado por Git);
# la contraseña de SQL, en la variable de entorno TF_VAR_sql_admin_password.
# =====================================================================

variable "subscription_id" {
  description = "ID de la suscripción de Azure for Students (az account show --query id -o tsv)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id debe ser un GUID de 36 caracteres."
  }
}

variable "resource_group_name" {
  description = "Resource group creado a mano en southcentralus (paso 2.2 del manual)."
  type        = string
  default     = "rg-dw-p4"
}

variable "sufijo" {
  description = "Tus iniciales en minúsculas; hacen únicos los nombres (p. ej. 'jc' -> stdwtottusjc)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.sufijo))
    error_message = "sufijo: de 2 a 6 caracteres, solo minúsculas y números (sin guiones)."
  }
}

variable "mi_ip" {
  description = "Tu IP pública para el firewall de Azure SQL (curl ifconfig.me)."
  type        = string

  validation {
    condition     = can(cidrhost("${var.mi_ip}/32", 0))
    error_message = "mi_ip debe ser una dirección IPv4 válida, p. ej. 190.12.34.56."
  }
}

variable "sql_admin_login" {
  description = "Usuario administrador del servidor SQL."
  type        = string
  default     = "tottusadmin"
}

variable "sql_admin_password" {
  description = "Contraseña del administrador SQL. Definir con: export TF_VAR_sql_admin_password='...'"
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.sql_admin_password) >= 12 &&
      can(regex("[A-Z]", var.sql_admin_password)) &&
      can(regex("[a-z]", var.sql_admin_password)) &&
      can(regex("[0-9]", var.sql_admin_password))
    )
    error_message = "La contraseña necesita al menos 12 caracteres, con mayúsculas, minúsculas y números."
  }
}

variable "sql_location" {
  description = "Región del OLTP. Separada porque la suscripción no permite Azure SQL en southcentralus."
  type        = string
  default     = "centralus"
}
