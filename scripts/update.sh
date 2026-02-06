#!/usr/bin/env bash
# =============================================================================
# srv-media — Mise à jour des images Docker
# =============================================================================
# Usage: ./scripts/update.sh [all|admin|media|arr|music|books|tools|monitoring]
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
    echo -e "${RED}[ERROR]${NC} Fichier .env introuvable."
    exit 1
fi

declare -A STACKS=(
    [admin]="compose/admin.yml"
    [media]="compose/media.yml"
    [arr]="compose/arr.yml"
    [music]="compose/music.yml"
    [books]="compose/books.yml"
    [tools]="compose/tools.yml"
    [monitoring]="compose/monitoring.yml"
)

update_stack() {
    local name="$1"
    local file="${STACKS[$name]}"
    echo -e "${BLUE}[UPDATE]${NC} Pull des images pour ${CYAN}${name}${NC}..."
    docker compose --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${file}" pull
    echo -e "${BLUE}[UPDATE]${NC} Recréation des containers ${CYAN}${name}${NC}..."
    docker compose --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${file}" up -d
    echo -e "${GREEN}[OK]${NC} ${name} mis à jour."
}

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]] || [[ "${TARGETS[0]}" == "all" ]]; then
    TARGETS=(admin media arr music books tools monitoring)
fi

echo ""
echo -e "${CYAN}=== srv-media — Mise à jour ===${NC}"
echo ""

for target in "${TARGETS[@]}"; do
    if [[ -n "${STACKS[$target]+x}" ]]; then
        update_stack "$target"
        echo ""
    else
        echo -e "${RED}[ERROR]${NC} Stack inconnue : '$target'"
    fi
done

# Nettoyage des anciennes images
echo -e "${BLUE}[CLEANUP]${NC} Suppression des images inutilisées..."
docker image prune -f
echo ""
echo -e "${GREEN}[OK]${NC} Mise à jour terminée."
