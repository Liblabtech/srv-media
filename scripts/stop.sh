#!/usr/bin/env bash
# =============================================================================
# srv-media — Arrêt des stacks
# =============================================================================
# Usage: ./scripts/stop.sh [all|admin|media|arr|music|books|tools|monitoring]
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

declare -A STACKS=(
    [admin]="compose/admin.yml"
    [media]="compose/media.yml"
    [arr]="compose/arr.yml"
    [music]="compose/music.yml"
    [books]="compose/books.yml"
    [tools]="compose/tools.yml"
    [monitoring]="compose/monitoring.yml"
)

stop_stack() {
    local name="$1"
    local file="${STACKS[$name]}"
    echo -e "${BLUE}[STOP]${NC} Arrêt de ${CYAN}${name}${NC}..."
    docker compose --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${file}" down
    echo -e "${GREEN}[OK]${NC} ${name} arrêté."
}

stop_all() {
    for name in monitoring tools books music arr media admin; do
        stop_stack "$name"
    done
}

# --- Mode argument direct ---
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ "$arg" == "all" ]]; then
            stop_all
        elif [[ -n "${STACKS[$arg]+x}" ]]; then
            stop_stack "$arg"
        else
            echo -e "${RED}[ERROR]${NC} Stack inconnue : '$arg'"
            exit 1
        fi
    done
    exit 0
fi

# --- Mode interactif ---
echo ""
echo -e "${CYAN}=== srv-media — Arrêt ===${NC}"
echo ""
echo "  1) Tout arrêter"
echo "  2) Admin"
echo "  3) Media"
echo "  4) Arr Stack"
echo "  5) Musique"
echo "  6) Livres"
echo "  7) Outils"
echo "  8) Monitoring"
echo "  0) Quitter"
echo ""

STACK_KEYS=(admin media arr music books tools monitoring)

while true; do
    read -rp "$(echo -e "${YELLOW}Choix [0-8] : ${NC}")" choice
    case "$choice" in
        1) stop_all; break ;;
        [2-8])
            idx=$((choice - 2))
            stop_stack "${STACK_KEYS[$idx]}"
            echo ""
            read -rp "Arrêter une autre stack ? (o/N) : " again
            [[ ! "$again" =~ ^[oOyY]$ ]] && break
            ;;
        0) echo "Annulé."; exit 0 ;;
        *) echo -e "${RED}Choix invalide.${NC}" ;;
    esac
done
