#!/usr/bin/env bash
# =============================================================================
# srv-media — Backup des configurations
# =============================================================================
# Usage: ./scripts/backup.sh [--stop]
#   --stop : Arrête les containers avant le backup pour cohérence des données
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

source "${PROJECT_DIR}/.env"

STOP_BEFORE=false
BACKUP_DIR="${PROJECT_DIR}/backups"

for arg in "$@"; do
    case "$arg" in
        --stop) STOP_BEFORE=true ;;
    esac
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/srv-media-config-${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

echo ""
echo -e "${CYAN}=== srv-media — Backup ===${NC}"
echo ""
echo -e "  ${BLUE}Source${NC}  : ${CONFIG_PATH}"
echo -e "  ${BLUE}Dest${NC}    : ${BACKUP_FILE}"
echo -e "  ${BLUE}Stop${NC}    : ${STOP_BEFORE}"
echo ""

# Arrêt optionnel
if [[ "$STOP_BEFORE" == true ]]; then
    echo -e "${YELLOW}[WARN]${NC} Arrêt des containers pour backup cohérent..."
    "${SCRIPT_DIR}/stop.sh" all
    echo ""
fi

# Backup
echo -e "${BLUE}[BACKUP]${NC} Création de l'archive..."
tar -czf "${BACKUP_FILE}" -C "${CONFIG_PATH}" .

# Également sauvegarder le .env
cp "${PROJECT_DIR}/.env" "${BACKUP_DIR}/.env.backup-${TIMESTAMP}"

BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | awk '{print $1}')
echo -e "${GREEN}[OK]${NC} Backup créé : ${BACKUP_FILE} (${BACKUP_SIZE})"

# Redémarrage si arrêté
if [[ "$STOP_BEFORE" == true ]]; then
    echo ""
    echo -e "${BLUE}[INFO]${NC} Redémarrage des containers..."
    "${SCRIPT_DIR}/start.sh" all
fi

# Nettoyage des vieux backups (garder les 5 derniers)
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/srv-media-config-*.tar.gz 2>/dev/null | wc -l)
if [[ "$BACKUP_COUNT" -gt 5 ]]; then
    echo ""
    echo -e "${BLUE}[CLEANUP]${NC} Suppression des anciens backups (garder 5)..."
    ls -1t "${BACKUP_DIR}"/srv-media-config-*.tar.gz | tail -n +6 | xargs rm -f
    echo -e "${GREEN}[OK]${NC} Nettoyage terminé."
fi

echo ""
echo -e "${GREEN}Backup terminé.${NC}"
