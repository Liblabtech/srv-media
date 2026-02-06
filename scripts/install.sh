#!/usr/bin/env bash
# =============================================================================
# srv-media — Installation de Docker CE + Docker Compose
# =============================================================================
# Usage: sudo ./scripts/install.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Vérifications ---
if [[ $EUID -ne 0 ]]; then
    log_error "Ce script doit être exécuté en root (sudo)."
    exit 1
fi

# Détecter le vrai user (celui qui a lancé sudo)
REAL_USER="${SUDO_USER:-$USER}"

log_info "=== srv-media — Installation Docker ==="
echo ""

# --- Docker Engine ---
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version)
    log_ok "Docker déjà installé : $DOCKER_VERSION"
else
    log_info "Installation de Docker CE..."

    # Prérequis
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    # Clé GPG Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Repo Docker
    ARCH=$(dpkg --print-architecture)
    DISTRO=$(. /etc/os-release && echo "$ID")
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$DISTRO $CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list

    # Installation
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    log_ok "Docker CE installé : $(docker --version)"
fi

# --- Docker Compose ---
if docker compose version &>/dev/null; then
    log_ok "Docker Compose : $(docker compose version --short)"
else
    log_error "Docker Compose plugin non trouvé. Réessayez l'installation."
    exit 1
fi

# --- Outils supplémentaires ---
log_info "Installation des outils nécessaires (curl, jq)..."
apt-get install -y -qq curl jq
log_ok "curl et jq installés."

# --- Groupe docker ---
if id -nG "$REAL_USER" | grep -qw docker; then
    log_ok "L'utilisateur '$REAL_USER' est déjà dans le groupe docker."
else
    log_info "Ajout de '$REAL_USER' au groupe docker..."
    usermod -aG docker "$REAL_USER"
    log_ok "Utilisateur '$REAL_USER' ajouté au groupe docker."
    log_warn "Déconnectez-vous et reconnectez-vous pour que le changement prenne effet."
fi

# --- Démarrage du service ---
systemctl enable docker
systemctl start docker
log_ok "Service Docker activé et démarré."

echo ""
log_info "=== Installation terminée ==="
echo ""
echo -e "  Docker Engine  : ${GREEN}$(docker --version)${NC}"
echo -e "  Docker Compose : ${GREEN}$(docker compose version --short)${NC}"
echo -e "  Utilisateur    : ${GREEN}$REAL_USER${NC} (groupe docker)"
echo ""
echo -e "  ${YELLOW}Prochaine étape :${NC} ./scripts/setup.sh"
echo ""
