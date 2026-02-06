#!/usr/bin/env bash
# =============================================================================
# srv-media — Setup : création des dossiers, permissions, génération .env
# =============================================================================
# Usage: sudo ./scripts/setup.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Répertoire du projet ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Vérifications ---
if [[ $EUID -ne 0 ]]; then
    log_error "Ce script doit être exécuté en root (sudo)."
    exit 1
fi

if ! command -v docker &>/dev/null; then
    log_error "Docker n'est pas installé. Lancez d'abord : sudo ./scripts/install.sh"
    exit 1
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       srv-media — Configuration Setup        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Collecte des paramètres (interactif avec valeurs par défaut)
# =============================================================================

# PUID / PGID
DEFAULT_PUID=$(id -u "${SUDO_USER:-$USER}")
DEFAULT_PGID=$(id -g "${SUDO_USER:-$USER}")
read -rp "$(echo -e "${BLUE}PUID${NC} [$DEFAULT_PUID] : ")" INPUT_PUID
PUID="${INPUT_PUID:-$DEFAULT_PUID}"
read -rp "$(echo -e "${BLUE}PGID${NC} [$DEFAULT_PGID] : ")" INPUT_PGID
PGID="${INPUT_PGID:-$DEFAULT_PGID}"

# Timezone
DEFAULT_TZ="Europe/Paris"
if [[ -f /etc/timezone ]]; then
    DEFAULT_TZ=$(cat /etc/timezone)
elif command -v timedatectl &>/dev/null; then
    DEFAULT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo "Europe/Paris")
fi
read -rp "$(echo -e "${BLUE}Timezone${NC} [$DEFAULT_TZ] : ")" INPUT_TZ
TZ="${INPUT_TZ:-$DEFAULT_TZ}"

# Chemins
read -rp "$(echo -e "${BLUE}Chemin des données (DATA_PATH)${NC} [/data] : ")" INPUT_DATA
DATA_PATH="${INPUT_DATA:-/data}"
read -rp "$(echo -e "${BLUE}Chemin des configs (CONFIG_PATH)${NC} [/opt/srv-media/config] : ")" INPUT_CONFIG
CONFIG_PATH="${INPUT_CONFIG:-/opt/srv-media/config}"

# IP du serveur
DEFAULT_IP=$(hostname -I | awk '{print $1}')
read -rp "$(echo -e "${BLUE}IP du serveur${NC} [$DEFAULT_IP] : ")" INPUT_IP
SERVER_IP="${INPUT_IP:-$DEFAULT_IP}"

# Plex Claim
echo ""
log_warn "Token Plex Claim : https://www.plex.tv/claim (expire en 4 min)"
read -rp "$(echo -e "${BLUE}Plex Claim Token${NC} (vide si pas maintenant) : ")" PLEX_CLAIM

# Transmission
read -rp "$(echo -e "${BLUE}Transmission user${NC} (vide = pas d'auth) : ")" TRANSMISSION_USER
read -rp "$(echo -e "${BLUE}Transmission password${NC} (vide = pas d'auth) : ")" TRANSMISSION_PASS

# NPM
echo ""
log_info "Configuration Nginx Proxy Manager :"
read -rp "$(echo -e "${BLUE}NPM email admin${NC} [admin@example.com] : ")" INPUT_NPM_EMAIL
NPM_EMAIL="${INPUT_NPM_EMAIL:-admin@example.com}"
read -rp "$(echo -e "${BLUE}NPM mot de passe${NC} [changeme] : ")" INPUT_NPM_PASS
NPM_PASSWORD="${INPUT_NPM_PASS:-changeme}"
read -rp "$(echo -e "${BLUE}Email Let's Encrypt${NC} [$NPM_EMAIL] : ")" INPUT_LE_EMAIL
NPM_LETSENCRYPT_EMAIL="${INPUT_LE_EMAIL:-$NPM_EMAIL}"

# Cloudflare
echo ""
log_info "Configuration Cloudflare DNS Challenge (pour SSL wildcard) :"
read -rp "$(echo -e "${BLUE}Cloudflare email${NC} : ")" CF_API_EMAIL
read -rp "$(echo -e "${BLUE}Cloudflare API Token${NC} : ")" CF_API_TOKEN

# Grafana
read -rp "$(echo -e "${BLUE}Grafana admin password${NC} [admin] : ")" INPUT_GF_PASS
GF_SECURITY_ADMIN_PASSWORD="${INPUT_GF_PASS:-admin}"

echo ""
log_info "=== Création de la structure ==="

# =============================================================================
# Création des dossiers de données
# =============================================================================

log_info "Création des dossiers de données dans ${DATA_PATH}..."
mkdir -p "${DATA_PATH}/torrents/movies"
mkdir -p "${DATA_PATH}/torrents/tv"
mkdir -p "${DATA_PATH}/torrents/music"
mkdir -p "${DATA_PATH}/torrents/books"
mkdir -p "${DATA_PATH}/media/movies"
mkdir -p "${DATA_PATH}/media/tv"
mkdir -p "${DATA_PATH}/media/music"
mkdir -p "${DATA_PATH}/media/books"
mkdir -p "${DATA_PATH}/media/comics"
mkdir -p "${DATA_PATH}/media/youtube"
mkdir -p "${DATA_PATH}/media/podcasts"
log_ok "Dossiers de données créés."

# =============================================================================
# Création des dossiers de config
# =============================================================================

SERVICES=(
    jellyfin plex tautulli jellyseerr
    sonarr radarr lidarr bazarr prowlarr transmission flaresolverr
    navidrome airsonic
    calibre calibre-web komga
    czkawka rclone
    prometheus grafana
    portainer npm
)

log_info "Création des dossiers de config dans ${CONFIG_PATH}..."
for svc in "${SERVICES[@]}"; do
    mkdir -p "${CONFIG_PATH}/${svc}"
done
# Sous-dossiers spéciaux
mkdir -p "${CONFIG_PATH}/npm/letsencrypt"
mkdir -p "${CONFIG_PATH}/airsonic/playlists"
log_ok "Dossiers de config créés (${#SERVICES[@]} services)."

# =============================================================================
# Permissions
# =============================================================================

log_info "Application des permissions (${PUID}:${PGID})..."
chown -R "${PUID}:${PGID}" "${DATA_PATH}"
chown -R "${PUID}:${PGID}" "${CONFIG_PATH}"
chmod -R 775 "${DATA_PATH}"
chmod -R 775 "${CONFIG_PATH}"
log_ok "Permissions appliquées."

# =============================================================================
# Réseau Docker
# =============================================================================

if docker network inspect media-network &>/dev/null; then
    log_ok "Réseau Docker 'media-network' existe déjà."
else
    log_info "Création du réseau Docker 'media-network'..."
    docker network create media-network
    log_ok "Réseau 'media-network' créé."
fi

# =============================================================================
# Détection hardware transcoding
# =============================================================================

HW_TRANSCODE="false"
if [[ -e /dev/dri ]]; then
    HW_TRANSCODE="true"
    log_ok "GPU détecté (/dev/dri) — Hardware transcoding activé."
else
    log_warn "Pas de GPU détecté — Hardware transcoding désactivé."
    log_warn "Commentez les lignes 'devices:' dans compose/media.yml si besoin."
fi

# =============================================================================
# Vérification filesystem unique (hardlinks)
# =============================================================================

if [[ -d "${DATA_PATH}/torrents" ]] && [[ -d "${DATA_PATH}/media" ]]; then
    FS_TORRENTS=$(df "${DATA_PATH}/torrents" --output=source | tail -1)
    FS_MEDIA=$(df "${DATA_PATH}/media" --output=source | tail -1)
    if [[ "$FS_TORRENTS" == "$FS_MEDIA" ]]; then
        log_ok "Hardlinks OK — torrents et media sur le même filesystem ($FS_TORRENTS)."
    else
        log_warn "ATTENTION : torrents ($FS_TORRENTS) et media ($FS_MEDIA) sont sur des filesystems différents !"
        log_warn "Les hardlinks ne fonctionneront pas. Les fichiers seront copiés au lieu d'être liés."
    fi
fi

# =============================================================================
# Génération du fichier .env
# =============================================================================

log_info "Génération du fichier .env..."
cat > "${PROJECT_DIR}/.env" << EOF
# =============================================================================
# srv-media — Configuration (généré par setup.sh le $(date '+%Y-%m-%d %H:%M:%S'))
# =============================================================================

# User / Group
PUID=${PUID}
PGID=${PGID}

# Timezone
TZ=${TZ}

# Chemins
DATA_PATH=${DATA_PATH}
CONFIG_PATH=${CONFIG_PATH}

# IP serveur
SERVER_IP=${SERVER_IP}

# Plex
PLEX_CLAIM=${PLEX_CLAIM}
PLEX_ADVERTISE_IP=http://${SERVER_IP}:32400

# Jellyfin
JELLYFIN_PUBLISHED_SERVER_URL=http://${SERVER_IP}:8096

# Transmission
TRANSMISSION_USER=${TRANSMISSION_USER}
TRANSMISSION_PASS=${TRANSMISSION_PASS}

# NPM (Nginx Proxy Manager)
NPM_URL=http://${SERVER_IP}:81
NPM_EMAIL=${NPM_EMAIL}
NPM_PASSWORD=${NPM_PASSWORD}
NPM_LETSENCRYPT_EMAIL=${NPM_LETSENCRYPT_EMAIL}

# Cloudflare DNS Challenge
CF_API_EMAIL=${CF_API_EMAIL}
CF_API_TOKEN=${CF_API_TOKEN}

# Proxy setup
PROXY_DELAY=5

# Watchtower
WATCHTOWER_SCHEDULE=0 0 4 * * *

# Grafana
GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}

# Ports
DASHBOARD_HTTP_PORT=32768
DASHBOARD_HTTPS_PORT=32769
PORTAINER_HTTP_PORT=9000
PORTAINER_HTTPS_PORT=9443
DOZZLE_PORT=9999
NPM_HTTP_PORT=80
NPM_HTTPS_PORT=443
NPM_ADMIN_PORT=81
JELLYFIN_PORT=8096
JELLYFIN_HTTPS_PORT=8920
PLEX_PORT=32400
TAUTULLI_PORT=8181
JELLYSEERR_PORT=5055
SONARR_PORT=8989
RADARR_PORT=7878
LIDARR_PORT=8686
BAZARR_PORT=6767
PROWLARR_PORT=9696
FLARESOLVERR_PORT=8191
TRANSMISSION_PORT=9091
TRANSMISSION_PEER_PORT=51413
NAVIDROME_PORT=4533
AIRSONIC_PORT=4040
CALIBRE_PORT=8083
CALIBRE_WEB_PORT=8084
KOMGA_PORT=25600
CZKAWKA_PORT=5800
METUBE_PORT=8081
RCLONE_PORT=5572
PROMETHEUS_PORT=9080
GRAFANA_PORT=3000

# Restart policy
RESTART_POLICY=unless-stopped
EOF

log_ok "Fichier .env généré dans ${PROJECT_DIR}/.env"

# =============================================================================
# Résumé
# =============================================================================

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            Setup terminé avec succès          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}PUID/PGID${NC}     : ${PUID}:${PGID}"
echo -e "  ${GREEN}Timezone${NC}      : ${TZ}"
echo -e "  ${GREEN}Données${NC}       : ${DATA_PATH}"
echo -e "  ${GREEN}Configs${NC}       : ${CONFIG_PATH}"
echo -e "  ${GREEN}IP serveur${NC}    : ${SERVER_IP}"
echo -e "  ${GREEN}HW Transcode${NC}  : ${HW_TRANSCODE}"
echo -e "  ${GREEN}Réseau Docker${NC} : media-network"
echo ""
echo -e "  ${YELLOW}Prochaine étape :${NC} ./scripts/start.sh"
echo ""
