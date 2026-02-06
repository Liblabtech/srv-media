#!/usr/bin/env bash
# =============================================================================
# srv-media — Redémarrage des stacks
# =============================================================================
# Usage: ./scripts/restart.sh [all|admin|media|arr|music|books|tools|monitoring]
#        ./scripts/restart.sh <service_name>  (ex: sonarr, jellyfin)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
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

# Map service → compose file
declare -A SERVICE_MAP=(
    [nginx-dashboard]=admin [portainer]=admin [dozzle]=admin [watchtower]=admin [nginx-proxy-manager]=admin
    [jellyfin]=media [plex]=media [tautulli]=media [jellyseerr]=media
    [sonarr]=arr [radarr]=arr [lidarr]=arr [bazarr]=arr [prowlarr]=arr [transmission]=arr [flaresolverr]=arr
    [navidrome]=music [airsonic]=music
    [calibre]=books [calibre-web]=books [komga]=books
    [czkawka]=tools [metube]=tools [rclone]=tools
    [prometheus]=monitoring [grafana]=monitoring
)

if [[ $# -eq 0 ]]; then
    echo -e "${CYAN}Usage :${NC}"
    echo "  ./scripts/restart.sh all                    # Tout redémarrer"
    echo "  ./scripts/restart.sh media                  # Redémarrer la stack media"
    echo "  ./scripts/restart.sh sonarr                 # Redémarrer un service spécifique"
    exit 0
fi

for arg in "$@"; do
    if [[ "$arg" == "all" ]]; then
        echo -e "${BLUE}[RESTART]${NC} Redémarrage complet..."
        "${SCRIPT_DIR}/stop.sh" all
        "${SCRIPT_DIR}/start.sh" all
    elif [[ -n "${STACKS[$arg]+x}" ]]; then
        echo -e "${BLUE}[RESTART]${NC} Redémarrage de la stack ${CYAN}${arg}${NC}..."
        docker compose --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${STACKS[$arg]}" down
        docker compose --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${STACKS[$arg]}" up -d
        echo -e "${GREEN}[OK]${NC} ${arg} redémarré."
    elif [[ -n "${SERVICE_MAP[$arg]+x}" ]]; then
        local_stack="${SERVICE_MAP[$arg]}"
        echo -e "${BLUE}[RESTART]${NC} Redémarrage du service ${CYAN}${arg}${NC}..."
        docker compose --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${STACKS[$local_stack]}" restart "$arg"
        echo -e "${GREEN}[OK]${NC} ${arg} redémarré."
    else
        echo -e "${RED}[ERROR]${NC} Inconnu : '$arg'"
        echo "  Stacks : all admin media arr music books tools monitoring"
        echo "  Services : ${!SERVICE_MAP[*]}"
        exit 1
    fi
done
