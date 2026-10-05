#!/usr/bin/env bash
# =====================================================================
# Proyecto 4 - DW Snowflake sobre Azure
# asignar_permisos_azure.sh
# ---------------------------------------------------------------------
# Da a la aplicación de Snowflake los permisos MÍNIMOS por contenedor:
#   bronze -> Storage Blob Data Reader       (solo lee los Parquet)
#   silver -> Storage Blob Data Contributor  (escribe Iceberg)
#   gold   -> Storage Blob Data Contributor  (escribe Iceberg)
#
# Requisito previo: haber abierto la AZURE_CONSENT_URL y aceptado
# (01_integraciones.sql, parte 2).
#
# Uso (Git Bash o Cloud Shell):
#   bash snowflake/asignar_permisos_azure.sh "<AZURE_MULTI_TENANT_APP_NAME>"
#   Ej.: bash snowflake/asignar_permisos_azure.sh "abc123xyz_1712345678901"
# =====================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1   # evita que Git Bash convierta los /subscriptions/... en rutas de Windows

RG="rg-dw-p4"
LAKE="stdwtottusjc"
APP_NAME_COMPLETO="${1:?Indica el AZURE_MULTI_TENANT_APP_NAME devuelto por Snowflake}"

# El nombre visible en Entra ID es la parte anterior al guion bajo
APP_NAME="${APP_NAME_COMPLETO%%_*}"
echo "Buscando la aplicación de Snowflake: $APP_NAME"

SF_SP=$(az ad sp list --display-name "$APP_NAME" --query "[0].id" -o tsv)
if [[ -z "$SF_SP" ]]; then
  echo "ERROR: no se encontró la aplicación '$APP_NAME'."
  echo "¿Abriste la AZURE_CONSENT_URL y pulsaste Aceptar? Espera 1-2 minutos y repite."
  exit 1
fi
echo "Service principal: $SF_SP"

LAKE_ID=$(az storage account show -n "$LAKE" -g "$RG" --query id -o tsv)
C="$LAKE_ID/blobServices/default/containers"

asignar() {
  local rol="$1" contenedor="$2"
  echo " -> $rol sobre $contenedor"
  az role assignment create \
    --assignee-object-id "$SF_SP" --assignee-principal-type ServicePrincipal \
    --role "$rol" --scope "$C/$contenedor" -o none
}

asignar "Storage Blob Data Reader"      bronze
asignar "Storage Blob Data Contributor" silver
asignar "Storage Blob Data Contributor" gold

echo
echo "Permisos actuales de la aplicación de Snowflake:"
az role assignment list --assignee "$SF_SP" --all \
  --query "[].{rol:roleDefinitionName, contenedor:scope}" -o table | sed 's#.*/containers/#  #'

echo
echo "Listo. Espera 5-10 minutos y ejecuta la PARTE 3 de 01_integraciones.sql."
