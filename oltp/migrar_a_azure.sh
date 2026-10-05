#!/usr/bin/env bash
# =====================================================================
# Proyecto 4 - DW Snowflake sobre Azure | Migración del OLTP a Azure
# migrar_a_azure.sh
# ---------------------------------------------------------------------
# 1. Exporta Tottus_OLTP (SQL Server local) a un archivo .bacpac
# 2. Sube temporalmente el tier de Azure SQL a S2 (importación rápida)
# 3. Abre el firewall para tu IP actual (regla temporal)
# 4. Importa el .bacpac en la base tottus_oltp creada por Terraform
#    (debe estar VACÍA)
# 5. Siempre, incluso si algo falla: vuelve a Basic y quita la regla
#
# Requisitos: sqlpackage, az (con sesión iniciada), curl
# Uso (desde Git Bash, en la raíz del repositorio):
#   export TF_VAR_sql_admin_password='...'
#   bash oltp/migrar_a_azure.sh
# =====================================================================
set -euo pipefail

# Git Bash convierte los argumentos que empiezan con "/" en rutas de Windows;
# sqlpackage usa ese formato (/Action:...), así que se desactiva la conversión.
export MSYS_NO_PATHCONV=1

# ------------------------- CONFIGURACIÓN -----------------------------
LOCAL_SERVER="${LOCAL_SERVER:-localhost}"           # instancia local (p. ej. localhost\SQLEXPRESS)
LOCAL_DB="Tottus_OLTP"
RG="rg-dw-p4"
AZ_SQL_SERVER="${AZ_SQL_SERVER:-sql-tottus-jc-centralus}"   # sin .database.windows.net
AZ_DB="tottus_oltp"
AZ_USER="${AZ_USER:-tottusadmin}"
REGLA_FW="migracion-temporal"
# ---------------------------------------------------------------------

: "${TF_VAR_sql_admin_password:?Define primero: export TF_VAR_sql_admin_password='...'}"

cd "$(dirname "$0")"
BACPAC="tottus_oltp.bacpac"

echo "== 0. Verificando herramientas"
for cmd in sqlpackage az curl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: falta '$cmd' en el PATH"; exit 1; }
done
az account show --query name -o tsv >/dev/null || { echo "ERROR: ejecuta 'az login'"; exit 1; }

limpiar() {
  echo "== 5. Limpieza: tier Basic y regla de firewall temporal"
  az sql db update -g "$RG" -s "$AZ_SQL_SERVER" -n "$AZ_DB" --service-objective Basic -o none || true
  az sql server firewall-rule delete -g "$RG" -s "$AZ_SQL_SERVER" -n "$REGLA_FW" -o none 2>/dev/null || true
  echo "   Tier actual: $(az sql db show -g "$RG" -s "$AZ_SQL_SERVER" -n "$AZ_DB" \
        --query currentServiceObjectiveName -o tsv)"
}

echo "== 1. Exportando $LOCAL_DB desde $LOCAL_SERVER a oltp/$BACPAC"
rm -f "$BACPAC"
sqlpackage /Action:Export \
  /SourceConnectionString:"Server=$LOCAL_SERVER;Database=$LOCAL_DB;Integrated Security=True;TrustServerCertificate=True;" \
  /TargetFile:"$BACPAC"
ls -lh "$BACPAC"

trap limpiar EXIT

echo "== 2. Subiendo $AZ_DB a S2 (solo durante la importación)"
az sql db update -g "$RG" -s "$AZ_SQL_SERVER" -n "$AZ_DB" --service-objective S2 -o none

echo "== 3. Abriendo firewall para la IP actual"
MI_IP="$(curl -s https://ifconfig.me)"
echo "   IP pública: $MI_IP"
az sql server firewall-rule create -g "$RG" -s "$AZ_SQL_SERVER" -n "$REGLA_FW" \
  --start-ip-address "$MI_IP" --end-ip-address "$MI_IP" -o none

echo "== 4. Importando en $AZ_SQL_SERVER/$AZ_DB (puede tardar varios minutos)"
sqlpackage /Action:Import \
  /SourceFile:"$BACPAC" \
  /TargetConnectionString:"Server=tcp:$AZ_SQL_SERVER.database.windows.net,1433;Initial Catalog=$AZ_DB;User ID=$AZ_USER;Password=$TF_VAR_sql_admin_password;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"

echo "== Migración completada. Ejecuta oltp/validaciones.sql en Azure y compara con la versión local."
