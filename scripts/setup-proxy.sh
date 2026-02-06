#!/usr/bin/env bash
# =============================================================================
# srv-media — Configuration automatique des Proxy Hosts dans NPM
# =============================================================================
# Crée les proxy hosts + certificat SSL wildcard Cloudflare via l'API NPM
#
# Usage: ./scripts/setup-proxy.sh
# Prérequis: NPM doit être démarré et accessible, jq installé
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
PROXY_HOSTS_FILE="${PROJECT_DIR}/proxy/proxy-hosts.json"

# --- Vérifications ---
if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
    echo -e "${RED}[ERROR]${NC} Fichier .env introuvable."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} jq n'est pas installé. Lancez : sudo apt install jq"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} curl n'est pas installé."
    exit 1
fi

if [[ ! -f "$PROXY_HOSTS_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} Fichier proxy-hosts.json introuvable : $PROXY_HOSTS_FILE"
    exit 1
fi

source "${PROJECT_DIR}/.env"

NPM_API="${NPM_URL}/api"
DELAY="${PROXY_DELAY:-5}"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    srv-media — Setup Proxy Hosts NPM          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Étape 1 : Authentification NPM
# =============================================================================

echo -e "${BLUE}[1/4]${NC} Authentification à NPM (${NPM_URL})..."

# Attendre que NPM soit prêt
MAX_RETRIES=30
RETRY=0
while [[ $RETRY -lt $MAX_RETRIES ]]; do
    if curl -sf "${NPM_API}/" &>/dev/null; then
        break
    fi
    RETRY=$((RETRY + 1))
    echo -e "  Attente de NPM... (${RETRY}/${MAX_RETRIES})"
    sleep 5
done

if [[ $RETRY -ge $MAX_RETRIES ]]; then
    echo -e "${RED}[ERROR]${NC} NPM n'est pas accessible après ${MAX_RETRIES} tentatives."
    exit 1
fi

TOKEN_RESPONSE=$(curl -sf -X POST "${NPM_API}/tokens" \
    -H "Content-Type: application/json" \
    -d "{
        \"identity\": \"${NPM_EMAIL}\",
        \"secret\": \"${NPM_PASSWORD}\"
    }")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token // empty')

if [[ -z "$TOKEN" ]]; then
    echo -e "${RED}[ERROR]${NC} Échec d'authentification NPM."
    echo -e "  Réponse : $TOKEN_RESPONSE"
    echo -e "  ${YELLOW}Note : Si c'est la première connexion, utilisez admin@example.com / changeme${NC}"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Authentifié avec succès."

AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# =============================================================================
# Étape 2 : Création du certificat SSL wildcard (Cloudflare DNS Challenge)
# =============================================================================

echo ""
echo -e "${BLUE}[2/4]${NC} Création du certificat SSL wildcard via Cloudflare DNS..."

# Vérifier si un certificat wildcard existe déjà
EXISTING_CERTS=$(curl -sf -H "$AUTH_HEADER" "${NPM_API}/nginx/certificates" || echo "[]")
CERT_ID=$(echo "$EXISTING_CERTS" | jq -r '.[] | select(.domain_names | contains(["*.lib-lab.cloud"])) | .id // empty' 2>/dev/null | head -1)

if [[ -n "$CERT_ID" ]]; then
    echo -e "${GREEN}[OK]${NC} Certificat wildcard existant trouvé (ID: ${CERT_ID})."
else
    echo -e "${BLUE}[INFO]${NC} Création d'un nouveau certificat wildcard..."

    CERT_RESPONSE=$(curl -sf -X POST "${NPM_API}/nginx/certificates" \
        -H "$AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "{
            \"provider\": \"letsencrypt\",
            \"nice_name\": \"Wildcard lib-lab.cloud\",
            \"domain_names\": [\"*.lib-lab.cloud\", \"*.media.lib-lab.cloud\"],
            \"meta\": {
                \"letsencrypt_email\": \"${NPM_LETSENCRYPT_EMAIL}\",
                \"letsencrypt_agree\": true,
                \"dns_challenge\": true,
                \"dns_provider\": \"cloudflare\",
                \"dns_provider_credentials\": \"dns_cloudflare_email = ${CF_API_EMAIL}\\ndns_cloudflare_api_key = ${CF_API_TOKEN}\",
                \"propagation_seconds\": 30
            }
        }")

    CERT_ID=$(echo "$CERT_RESPONSE" | jq -r '.id // empty')

    if [[ -z "$CERT_ID" ]]; then
        echo -e "${RED}[ERROR]${NC} Échec de création du certificat."
        echo -e "  Réponse : $CERT_RESPONSE"
        echo -e ""
        echo -e "${YELLOW}[WARN]${NC} Continuation sans SSL. Les proxy hosts seront créés sans certificat."
        CERT_ID=""
    else
        echo -e "${GREEN}[OK]${NC} Certificat créé (ID: ${CERT_ID})."

        # Attendre la validation DNS
        echo -e "${BLUE}[INFO]${NC} Attente de la validation DNS (peut prendre 1-2 min)..."
        CERT_READY=false
        for i in $(seq 1 24); do
            sleep 10
            CERT_STATUS=$(curl -sf -H "$AUTH_HEADER" "${NPM_API}/nginx/certificates/${CERT_ID}" || echo "{}")
            CERT_PROVIDER=$(echo "$CERT_STATUS" | jq -r '.provider // empty')
            if [[ "$CERT_PROVIDER" == "letsencrypt" ]]; then
                CERT_EXPIRES=$(echo "$CERT_STATUS" | jq -r '.expires_on // empty')
                if [[ -n "$CERT_EXPIRES" ]]; then
                    CERT_READY=true
                    echo -e "${GREEN}[OK]${NC} Certificat validé (expire : ${CERT_EXPIRES})."
                    break
                fi
            fi
            echo -e "  Attente... (${i}/24)"
        done

        if [[ "$CERT_READY" != true ]]; then
            echo -e "${YELLOW}[WARN]${NC} Timeout en attendant le certificat. Il sera peut-être prêt plus tard."
        fi
    fi
fi

# =============================================================================
# Étape 3 : Création des proxy hosts
# =============================================================================

echo ""
echo -e "${BLUE}[3/4]${NC} Création des proxy hosts..."

TOTAL=$(jq '. | length' "$PROXY_HOSTS_FILE")
SUCCESS=0
FAILED=0
SKIPPED=0

for i in $(seq 0 $((TOTAL - 1))); do
    DOMAIN=$(jq -r ".[$i].domain" "$PROXY_HOSTS_FILE")
    FORWARD_HOST=$(jq -r ".[$i].forward_host" "$PROXY_HOSTS_FILE")
    FORWARD_PORT=$(jq -r ".[$i].forward_port" "$PROXY_HOSTS_FILE")

    # Vérifier si le proxy host existe déjà
    EXISTING=$(curl -sf -H "$AUTH_HEADER" "${NPM_API}/nginx/proxy-hosts" | \
        jq -r ".[] | select(.domain_names[] == \"${DOMAIN}\") | .id // empty" 2>/dev/null | head -1)

    if [[ -n "$EXISTING" ]]; then
        echo -e "  [$(($i + 1))/${TOTAL}] ${YELLOW}~${NC} ${DOMAIN} (existe déjà, ID: ${EXISTING})"
        SKIPPED=$((SKIPPED + 1))
    else
        # Construire le payload
        SSL_CONFIG=""
        if [[ -n "$CERT_ID" ]]; then
            SSL_CONFIG="\"certificate_id\": ${CERT_ID}, \"ssl_forced\": true, \"http2_support\": true, \"hsts_enabled\": true, \"hsts_subdomains\": false,"
        fi

        RESPONSE=$(curl -sf -X POST "${NPM_API}/nginx/proxy-hosts" \
            -H "$AUTH_HEADER" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\": [\"${DOMAIN}\"],
                \"forward_scheme\": \"http\",
                \"forward_host\": \"${FORWARD_HOST}\",
                \"forward_port\": ${FORWARD_PORT},
                ${SSL_CONFIG}
                \"block_exploits\": true,
                \"allow_websocket_upgrade\": true,
                \"access_list_id\": 0,
                \"meta\": {
                    \"letsencrypt_agree\": false,
                    \"dns_challenge\": false
                },
                \"advanced_config\": \"\",
                \"locations\": [],
                \"caching_enabled\": false
            }" 2>&1)

        HOST_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)

        if [[ -n "$HOST_ID" ]]; then
            echo -e "  [$(($i + 1))/${TOTAL}] ${GREEN}+${NC} ${DOMAIN} → ${FORWARD_HOST}:${FORWARD_PORT}"
            SUCCESS=$((SUCCESS + 1))
        else
            echo -e "  [$(($i + 1))/${TOTAL}] ${RED}x${NC} ${DOMAIN} — Erreur"
            FAILED=$((FAILED + 1))
        fi
    fi

    # Pause entre chaque création
    if [[ $i -lt $((TOTAL - 1)) ]]; then
        sleep "${DELAY}"
    fi
done

# =============================================================================
# Étape 4 : Résumé
# =============================================================================

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              Résumé                           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Créés${NC}    : ${SUCCESS}"
echo -e "  ${YELLOW}Existants${NC} : ${SKIPPED}"
echo -e "  ${RED}Échoués${NC}  : ${FAILED}"
echo -e "  ${BLUE}Total${NC}    : ${TOTAL}"

if [[ -n "$CERT_ID" ]]; then
    echo -e "  ${GREEN}SSL${NC}      : Certificat wildcard ID ${CERT_ID}"
else
    echo -e "  ${YELLOW}SSL${NC}      : Pas de certificat (configurer manuellement)"
fi

echo ""
echo -e "${GREEN}Setup proxy terminé.${NC}"
echo ""
