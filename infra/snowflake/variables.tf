# =====================================================================
# Variables de la infraestructura de Snowflake
# =====================================================================

variable "sf_organization" {
  description = "Organización de Snowflake (primera parte del identificador)."
  type        = string
  default     = "JULTITQ"
}

variable "sf_account" {
  description = "Nombre de cuenta de Snowflake (segunda parte del identificador)."
  type        = string
  default     = "IC99482"
}

variable "sf_user" {
  description = "Usuario con el que Terraform se conecta (con llave RSA registrada)."
  type        = string
  default     = "JOSUECH"
}

variable "sf_private_key_path" {
  description = "Ruta a la llave privada RSA (fuera del repositorio)."
  type        = string
  default     = "~/.snowflake/josue_key.p8"
}

variable "creditos_mensuales" {
  description = "Tope de créditos del monitor de recursos (suspende el warehouse al 90 %)."
  type        = number
  default     = 60
}
