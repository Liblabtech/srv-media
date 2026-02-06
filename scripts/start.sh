#!/usr/bin/env bash
# =============================================================================
# srv-media — Démarrage des stacks
# =============================================================================
# Usage: ./scripts/start.sh [all|admin|media|arr|music|books|tools|monitoring]
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

# Vérifier .env
if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
    echo -e "${RED}[ERROR]${NC} Fichier .env introuvable. Lancez d'abord : ./scripts/setup.sh"
    exit 1
fi

# Map des catégories → fichiers compose
declare -A STACKS=(
    [admin]="compose/admin.yml"
    [media]="compose/media.yml"
    [arr]="compose/arr.yml"
    [music]="compose/music.yml"
    [books]="compose/books.yml"
    [tools]="compose/tools.yml"
    [monitoring]="compose/monitoring.yml"
)

STACK_LABELS=(
    "admin:Admin (Dashboard, Portainer, Dozzle, Watchtower, NPM)"
    "media:Media (Jellyfin, Plex, Tautulli, Jellyseerr)"
    "arr:Arr Stack (Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Transmission, FlareSolverr)"
    "music:Musique (Navidrome, Airsonic)"
    "books:Livres (Calibre, Calibre-Web, Komga)"
    "tools:Outils (Czkawka, MeTube, Rclone)"
    "monitoring:Monitoring (Prometheus, Grafana)"
)

start_stack() {
    local name="$1"
    local file="${STACKS[$name]}"
    echo -e "${BLUE}[START]${NC} Démarrage de ${CYAN}${name}${NC}..."
    docker compose --env-file "${PROJECT_DIR}/.env" -f "${PROJECT_DIR}/${file}" up -d
    echo -e "${GREEN}[OK]${NC} ${name} démarré."
}

start_all() {
    for name in admin media arr music books tools monitoring; do
        start_stack "$name"
    done
}

show_urls() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           Services disponibles                ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # Charger l'IP depuis .env
    source "${PROJECT_DIR}/.env"
    local IP="${SERVER_IP:-localhost}"

    echo -e "  ${GREEN}Dashboard${NC}      : http://${IP}:${DASHBOARD_HTTP_PORT:-32768}"
    echo -e "  ${GREEN}Portainer${NC}      : http://${IP}:${PORTAINER_HTTP_PORT:-9000}"
    echo -e "  ${GREEN}Dozzle${NC}         : http://${IP}:${DOZZLE_PORT:-9999}"
    echo -e "  ${GREEN}NPM Admin${NC}      : http://${IP}:${NPM_ADMIN_PORT:-81}"
    echo -e "  ${GREEN}Jellyfin${NC}       : http://${IP}:${JELLYFIN_PORT:-8096}"
    echo -e "  ${GREEN}Plex${NC}           : http://${IP}:${PLEX_PORT:-32400}/web"
    echo -e "  ${GREEN}Tautulli${NC}       : http://${IP}:${TAUTULLI_PORT:-8181}"
    echo -e "  ${GREEN}Jellyseerr${NC}     : http://${IP}:${JELLYSEERR_PORT:-5055}"
    echo -e "  ${GREEN}Sonarr${NC}         : http://${IP}:${SONARR_PORT:-8989}"
    echo -e "  ${GREEN}Radarr${NC}         : http://${IP}:${RADARR_PORT:-7878}"
    echo -e "  ${GREEN}Lidarr${NC}         : http://${IP}:${LIDARR_PORT:-8686}"
    echo -e "  ${GREEN}Bazarr${NC}         : http://${IP}:${BAZARR_PORT:-6767}"
    echo -e "  ${GREEN}Prowlarr${NC}       : http://${IP}:${PROWLARR_PORT:-9696}"
    echo -e "  ${GREEN}Transmission${NC}   : http://${IP}:${TRANSMISSION_PORT:-9091}"
    echo -e "  ${GREEN}FlareSolverr${NC}   : http://${IP}:${FLARESOLVERR_PORT:-8191}"
    echo -e "  ${GREEN}Navidrome${NC}      : http://${IP}:${NAVIDROME_PORT:-4533}"
    echo -e "  ${GREEN}Airsonic${NC}       : http://${IP}:${AIRSONIC_PORT:-4040}"
    echo -e "  ${GREEN}Calibre${NC}        : http://${IP}:${CALIBRE_PORT:-8083}"
    echo -e "  ${GREEN}Calibre-Web${NC}    : http://${IP}:${CALIBRE_WEB_PORT:-8084}"
    echo -e "  ${GREEN}Komga${NC}          : http://${IP}:${KOMGA_PORT:-25600}"
    echo -e "  ${GREEN}Czkawka${NC}        : http://${IP}:${CZKAWKA_PORT:-5800}"
    echo -e "  ${GREEN}MeTube${NC}         : http://${IP}:${METUBE_PORT:-8081}"
    echo -e "  ${GREEN}Rclone${NC}         : http://${IP}:${RCLONE_PORT:-5572}"
    echo -e "  ${GREEN}Prometheus${NC}     : http://${IP}:${PROMETHEUS_PORT:-9080}"
    echo -e "  ${GREEN}Grafana${NC}        : http://${IP}:${GRAFANA_PORT:-3000}"
    echo ""
}

# --- Mode argument direct ---
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ "$arg" == "all" ]]; then
            start_all
        elif [[ -n "${STACKS[$arg]+x}" ]]; then
            start_stack "$arg"
        else
            echo -e "${RED}[ERROR]${NC} Stack inconnue : '$arg'"
            echo "  Stacks disponibles : all admin media arr music books tools monitoring"
            exit 1
        fi
    done
    show_urls
    exit 0
fi

# --- Mode interactif ---
echo ""
echo -e "${CYAN}=== srv-media — Démarrage ===${NC}"
echo ""
echo "  1) Tout démarrer"
echo "  2) Admin (Dashboard, Portainer, Dozzle, Watchtower, NPM)"
echo "  3) Media (Jellyfin, Plex, Tautulli, Jellyseerr)"
echo "  4) Arr Stack (Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Transmission, FlareSolverr)"
echo "  5) Musique (Navidrome, Airsonic)"
echo "  6) Livres (Calibre, Calibre-Web, Komga)"
echo "  7) Outils (Czkawka, MeTube, Rclone)"
echo "  8) Monitoring (Prometheus, Grafana)"
echo "  0) Quitter"
echo ""

STACK_KEYS=(admin media arr music books tools monitoring)

while true; do
    read -rp "$(echo -e "${YELLOW}Choix [0-8] : ${NC}")" choice
    case "$choice" in
        1)
            start_all
            show_urls
            break
            ;;
        [2-8])
            idx=$((choice - 2))
            start_stack "${STACK_KEYS[$idx]}"
            echo ""
            read -rp "Démarrer une autre stack ? (o/N) : " again
            if [[ ! "$again" =~ ^[oOyY]$ ]]; then
                show_urls
                break
            fi
            ;;
        0)
            echo "Annulé."
            exit 0
            ;;
        *)
            echo -e "${RED}Choix invalide.${NC}"
            ;;
    esac
done
