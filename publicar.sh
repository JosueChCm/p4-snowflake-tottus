#!/usr/bin/env bash
# Publica la rama actual en main: commit, push, Pull request y merge.
# Uso: bash publicar.sh "mensaje del cambio"
set -euo pipefail

MSG="${1:?Escribe un mensaje: bash publicar.sh \"descripcion del cambio\"}"
RAMA=$(git branch --show-current)

if [ "$RAMA" = "main" ]; then
  echo "Estás en main. Crea una rama primero: git checkout -b feature/<nombre>"
  exit 1
fi

git status --short
git add -A
git commit -m "$MSG" || echo "(sin cambios nuevos para commit)"
git push -u origin "$RAMA"

gh pr create --base main --head "$RAMA" --title "$MSG" --body "Cambio: $MSG" \
  || echo "(el Pull request ya existía)"
gh pr merge "$RAMA" --merge --delete-branch

git checkout main
git pull
echo "Listo: '$RAMA' está en main. Ahora en Snowsight: CALL OPS_DB.ADMIN.SP_EJECUTAR_DBT();"