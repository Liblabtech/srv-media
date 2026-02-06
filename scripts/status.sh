#!/usr/bin/env bash
# =============================================================================
# srv-media — État des containers
# =============================================================================
# Usage: ./scripts/status.sh
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

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          srv-media — État des services        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

for name in admin media arr music books tools monitoring; do
    file="${STACKS[$name]}"
    compose_file="${PROJECT_DIR}/${file}"

    if [[ ! -f "$compose_file" ]]; then
        continue
    fi

    echo -e "${YELLOW}── ${name^^} ──${NC}"

    # Vérifier si des containers de cette stack tournent
    output=$(docker compose --env-file "${PROJECT_DIR}/.env" -f "$compose_file" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)

    if [[ -z "$output" ]] || [[ $(echo "$output" | wc -l) -le 1 ]]; then
        echo -e "  ${RED}Aucun container actif${NC}"
    else
        echo "$output" | while IFS= read -r line; do
            if echo "$line" | grep -qi "up\|running\|healthy"; then
                echo -e "  ${GREEN}${line}${NC}"
            elif echo "$line" | grep -qi "exit\|dead\|unhealthy"; then
                echo -e "  ${RED}${line}${NC}"
            else
                echo "  $line"
            fi
        done
    fi
    echo ""
done

# Résumé
TOTAL=$(docker ps --filter "label=com.docker.compose.project" --format "{{.Names}}" 2>/dev/null | wc -l)
RUNNING=$(docker ps --filter "status=running" --filter "label=com.docker.compose.project" --format "{{.Names}}" 2>/dev/null | wc -l)
echo -e "${CYAN}Résumé :${NC} ${GREEN}${RUNNING}${NC} / ${TOTAL} containers actifs"
echo ""
