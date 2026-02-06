#!/usr/bin/env bash
# =============================================================================
# srv-media — Préparation interactive de la machine via Ansible
# =============================================================================
# Ce script guide l'utilisateur dans la configuration d'Ansible puis lance
# le playbook de préparation du serveur.
#
# Usage: ./scripts/prepare.sh
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${PROJECT_DIR}/ansible"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  srv-media — Préparation du serveur (Ansible)     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Étape 1 : Vérifier / Installer Ansible
# =============================================================================

echo -e "${BLUE}[1/5]${NC} Vérification d'Ansible..."

if command -v ansible-playbook &>/dev/null; then
    log_ok "Ansible installé : $(ansible --version | head -1)"
else
    log_warn "Ansible n'est pas installé."
    read -rp "$(echo -e "${YELLOW}Installer Ansible ? (O/n) : ${NC}")" install_ansible
    if [[ "${install_ansible,,}" != "n" ]]; then
        if command -v pip3 &>/dev/null; then
            pip3 install ansible
        elif command -v apt &>/dev/null; then
            sudo apt update && sudo apt install -y ansible
        else
            log_error "Impossible d'installer Ansible automatiquement."
            echo "  Installez manuellement : pip3 install ansible  OU  apt install ansible"
            exit 1
        fi
        log_ok "Ansible installé."
    else
        log_error "Ansible est requis. Annulé."
        exit 1
    fi
fi

# Installer les collections nécessaires
log_info "Installation des collections Ansible requises..."
ansible-galaxy collection install community.general community.docker ansible.posix --force 2>/dev/null || true
log_ok "Collections installées."

# =============================================================================
# Étape 2 : Configuration de l'inventaire
# =============================================================================

echo ""
echo -e "${BLUE}[2/5]${NC} Configuration de l'inventaire..."

INVENTORY_FILE="${ANSIBLE_DIR}/inventory.yml"

if [[ -f "$INVENTORY_FILE" ]]; then
    log_ok "Inventaire existant trouvé : $INVENTORY_FILE"
    read -rp "$(echo -e "${YELLOW}Reconfigurer l'inventaire ? (o/N) : ${NC}")" reconfig
    [[ "${reconfig,,}" != "o" ]] && SKIP_INVENTORY=true || SKIP_INVENTORY=false
else
    SKIP_INVENTORY=false
fi

if [[ "$SKIP_INVENTORY" == false ]]; then
    echo ""
    read -rp "$(echo -e "${BLUE}Mode d'exécution ?${NC} (1=local, 2=distant) [1] : ")" mode
    MODE="${mode:-1}"

    if [[ "$MODE" == "1" ]]; then
        cat > "$INVENTORY_FILE" << 'INVENTORY'
---
all:
  hosts:
    media-server:
      ansible_connection: local
      ansible_become: true
INVENTORY
        log_ok "Inventaire configuré en mode LOCAL."
    else
        read -rp "$(echo -e "${BLUE}IP/hostname du serveur${NC} : ")" server_host
        read -rp "$(echo -e "${BLUE}Utilisateur SSH${NC} [root] : ")" ssh_user
        ssh_user="${ssh_user:-root}"
        read -rp "$(echo -e "${BLUE}Clé SSH${NC} [~/.ssh/id_ed25519] : ")" ssh_key
        ssh_key="${ssh_key:-~/.ssh/id_ed25519}"

        cat > "$INVENTORY_FILE" << INVENTORY
---
all:
  hosts:
    media-server:
      ansible_host: ${server_host}
      ansible_user: ${ssh_user}
      ansible_become: true
      ansible_ssh_private_key_file: ${ssh_key}
INVENTORY
        log_ok "Inventaire configuré pour ${server_host}."
    fi
fi

# =============================================================================
# Étape 3 : Configuration des variables
# =============================================================================

echo ""
echo -e "${BLUE}[3/5]${NC} Configuration des variables..."

VARS_FILE="${ANSIBLE_DIR}/vars.yml"

if [[ -f "$VARS_FILE" ]]; then
    log_ok "Variables existantes trouvées : $VARS_FILE"
    read -rp "$(echo -e "${YELLOW}Reconfigurer les variables ? (o/N) : ${NC}")" reconfig_vars
    [[ "${reconfig_vars,,}" != "o" ]] && SKIP_VARS=true || SKIP_VARS=false
else
    SKIP_VARS=false
fi

if [[ "$SKIP_VARS" == false ]]; then
    echo ""

    # Utilisateur
    read -rp "$(echo -e "${BLUE}Nom de l'utilisateur media${NC} [media] : ")" input_user
    MEDIA_USER="${input_user:-media}"
    read -rp "$(echo -e "${BLUE}UID${NC} [1000] : ")" input_uid
    MEDIA_UID="${input_uid:-1000}"
    read -rp "$(echo -e "${BLUE}GID${NC} [1000] : ")" input_gid
    MEDIA_GID="${input_gid:-1000}"

    # Chemins
    read -rp "$(echo -e "${BLUE}Chemin des données${NC} [/data] : ")" input_data
    DATA_PATH="${input_data:-/data}"
    read -rp "$(echo -e "${BLUE}Chemin des configs${NC} [/opt/srv-media/config] : ")" input_config
    CONFIG_PATH="${input_config:-/opt/srv-media/config}"

    # Timezone
    DEFAULT_TZ="Europe/Paris"
    if [[ -f /etc/timezone ]]; then
        DEFAULT_TZ=$(cat /etc/timezone)
    fi
    read -rp "$(echo -e "${BLUE}Timezone${NC} [$DEFAULT_TZ] : ")" input_tz
    TIMEZONE="${input_tz:-$DEFAULT_TZ}"

    # Montages
    echo ""
    echo -e "${CYAN}── Configuration des montages réseau ──${NC}"
    echo ""

    # SMB
    SMB_MOUNTS="[]"
    read -rp "$(echo -e "${BLUE}Ajouter des montages SMB/CIFS ? (o/N) : ${NC}")" add_smb
    if [[ "${add_smb,,}" == "o" ]]; then
        SMB_ENTRIES=""
        while true; do
            echo ""
            read -rp "  Source SMB (ex: //192.168.1.10/media) : " smb_source
            read -rp "  Point de montage (ex: /data) : " smb_mount
            read -rp "  Username SMB : " smb_user
            read -rp "  Password SMB : " smb_pass
            read -rp "  Options [uid=1000,gid=1000,iocharset=utf8,vers=3.0,nofail,_netdev] : " smb_opts
            smb_opts="${smb_opts:-uid=${MEDIA_UID},gid=${MEDIA_GID},iocharset=utf8,vers=3.0,nofail,_netdev}"
            smb_name=$(echo "$smb_mount" | tr '/' '-' | sed 's/^-//')

            SMB_ENTRIES="${SMB_ENTRIES}
    - name: ${smb_name}
      source: \"${smb_source}\"
      mount_point: ${smb_mount}
      fs_type: cifs
      options: \"username=${smb_user},password=${smb_pass},${smb_opts}\""

            read -rp "  Ajouter un autre montage SMB ? (o/N) : " more_smb
            [[ "${more_smb,,}" != "o" ]] && break
        done
        SMB_MOUNTS="${SMB_ENTRIES}"
    fi

    # NFS
    NFS_MOUNTS="[]"
    read -rp "$(echo -e "${BLUE}Ajouter des montages NFS ? (o/N) : ${NC}")" add_nfs
    if [[ "${add_nfs,,}" == "o" ]]; then
        NFS_ENTRIES=""
        while true; do
            echo ""
            read -rp "  Source NFS (ex: 192.168.1.10:/volume1/data) : " nfs_source
            read -rp "  Point de montage (ex: /data) : " nfs_mount
            read -rp "  Options [rw,hard,intr,nofail,_netdev] : " nfs_opts
            nfs_opts="${nfs_opts:-rw,hard,intr,nofail,_netdev}"
            nfs_name=$(echo "$nfs_mount" | tr '/' '-' | sed 's/^-//')

            NFS_ENTRIES="${NFS_ENTRIES}
    - name: ${nfs_name}
      source: \"${nfs_source}\"
      mount_point: ${nfs_mount}
      fs_type: nfs
      options: \"${nfs_opts}\""

            read -rp "  Ajouter un autre montage NFS ? (o/N) : " more_nfs
            [[ "${more_nfs,,}" != "o" ]] && break
        done
        NFS_MOUNTS="${NFS_ENTRIES}"
    fi

    # iSCSI
    ISCSI_TARGETS="[]"
    read -rp "$(echo -e "${BLUE}Ajouter des cibles iSCSI ? (o/N) : ${NC}")" add_iscsi
    if [[ "${add_iscsi,,}" == "o" ]]; then
        ISCSI_ENTRIES=""
        while true; do
            echo ""
            read -rp "  Portail iSCSI (ex: 192.168.1.10:3260) : " iscsi_portal
            read -rp "  Target IQN (ex: iqn.2024-01.com.nas:data) : " iscsi_target
            read -rp "  Device (ex: /dev/sdb1) : " iscsi_device
            read -rp "  Point de montage (ex: /data) : " iscsi_mount
            read -rp "  Filesystem [ext4] : " iscsi_fs
            iscsi_fs="${iscsi_fs:-ext4}"
            iscsi_name=$(echo "$iscsi_mount" | tr '/' '-' | sed 's/^-//')

            ISCSI_ENTRIES="${ISCSI_ENTRIES}
    - name: ${iscsi_name}
      portal: \"${iscsi_portal}\"
      target: \"${iscsi_target}\"
      device: \"${iscsi_device}\"
      mount_point: ${iscsi_mount}
      fs_type: ${iscsi_fs}
      options: \"defaults,_netdev,nofail\""

            read -rp "  Ajouter une autre cible iSCSI ? (o/N) : " more_iscsi
            [[ "${more_iscsi,,}" != "o" ]] && break
        done
        ISCSI_TARGETS="${ISCSI_ENTRIES}"
    fi

    # Écrire le fichier vars.yml
    cat > "$VARS_FILE" << EOF
---
# Généré par prepare.sh le $(date '+%Y-%m-%d %H:%M:%S')

media_user: ${MEDIA_USER}
media_group: ${MEDIA_USER}
media_uid: ${MEDIA_UID}
media_gid: ${MEDIA_GID}

data_path: ${DATA_PATH}
config_path: ${CONFIG_PATH}
project_path: /opt/srv-media

timezone: ${TIMEZONE}

extra_packages:
  - htop
  - iotop
  - ncdu
  - tree
  - tmux
  - vim
  - net-tools
EOF

    # Ajouter les montages SMB
    if [[ "$SMB_MOUNTS" != "[]" ]]; then
        cat >> "$VARS_FILE" << EOF

smb_mounts:${SMB_MOUNTS}
EOF
    else
        echo -e "\nsmb_mounts: []" >> "$VARS_FILE"
    fi

    # Ajouter les montages NFS
    if [[ "$NFS_MOUNTS" != "[]" ]]; then
        cat >> "$VARS_FILE" << EOF

nfs_mounts:${NFS_MOUNTS}
EOF
    else
        echo -e "\nnfs_mounts: []" >> "$VARS_FILE"
    fi

    # Ajouter les cibles iSCSI
    if [[ "$ISCSI_TARGETS" != "[]" ]]; then
        cat >> "$VARS_FILE" << EOF

iscsi_targets:${ISCSI_ENTRIES}
EOF
    else
        echo -e "\niscsi_targets: []" >> "$VARS_FILE"
    fi

    log_ok "Variables sauvegardées dans $VARS_FILE"
fi

# =============================================================================
# Étape 4 : Choix des tags
# =============================================================================

echo ""
echo -e "${BLUE}[4/5]${NC} Que souhaitez-vous exécuter ?"
echo ""
echo "  1) Tout (update + docker + montages + dossiers + réseau)"
echo "  2) Système uniquement (update, paquets, timezone, utilisateur)"
echo "  3) Docker uniquement"
echo "  4) Montages uniquement (SMB/NFS/iSCSI + fstab)"
echo "  5) Dossiers + permissions uniquement"
echo "  6) Personnalisé (choisir les tags)"
echo ""

read -rp "$(echo -e "${YELLOW}Choix [1-6] : ${NC}")" tag_choice

case "$tag_choice" in
    1) TAGS="" ;;
    2) TAGS="--tags system" ;;
    3) TAGS="--tags docker" ;;
    4) TAGS="--tags mounts" ;;
    5) TAGS="--tags dirs" ;;
    6)
        echo "  Tags disponibles : system, docker, mounts, dirs, network, project"
        read -rp "  Tags (séparés par des virgules) : " custom_tags
        TAGS="--tags ${custom_tags}"
        ;;
    *) TAGS="" ;;
esac

# =============================================================================
# Étape 5 : Exécution du playbook
# =============================================================================

echo ""
echo -e "${BLUE}[5/5]${NC} Exécution du playbook Ansible..."
echo ""

CMD="ansible-playbook -i ${ANSIBLE_DIR}/inventory.yml ${ANSIBLE_DIR}/playbook.yml ${TAGS}"

echo -e "${CYAN}Commande :${NC} $CMD"
echo ""
read -rp "$(echo -e "${YELLOW}Lancer l'exécution ? (O/n) : ${NC}")" confirm
if [[ "${confirm,,}" == "n" ]]; then
    echo ""
    log_warn "Annulé. Vous pouvez lancer manuellement :"
    echo "  $CMD"
    exit 0
fi

echo ""
eval "$CMD"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Préparation du serveur terminée !           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${YELLOW}Prochaines étapes :${NC}"
echo "    1. cd /opt/srv-media  (ou le chemin du projet)"
echo "    2. ./scripts/setup.sh   (configurer les variables .env)"
echo "    3. ./scripts/start.sh   (démarrer les services)"
echo "    4. ./scripts/setup-proxy.sh  (configurer les proxy hosts)"
echo ""
