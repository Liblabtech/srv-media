# srv-media

Stack Media Server Docker complète, prête a l'emploi. Git clone, configure, lance.

## Services (26)

| Categorie | Services | Ports |
|-----------|----------|-------|
| **Admin** | Dashboard, Portainer, Dozzle, Watchtower, NPM | 32768, 9000, 9999, -, 80/443/81 |
| **Media** | Jellyfin, Plex, Tautulli, Jellyseerr | 8096, 32400, 8181, 5055 |
| **Arr Stack** | Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Transmission, FlareSolverr | 8989, 7878, 8686, 6767, 9696, 9091, 8191 |
| **Musique** | Navidrome, Airsonic | 4533, 4040 |
| **Livres** | Calibre, Calibre-Web, Komga | 8083, 8084, 25600 |
| **Outils** | Czkawka, MeTube, Rclone | 5800, 8081, 5572 |
| **Monitoring** | Prometheus, Grafana | 9080, 3000 |

## Quickstart

```bash
# 1. Cloner
git clone https://github.com/VOTRE_USER/srv-media.git
cd srv-media

# 2. Preparer la machine (Ansible : update, docker, montages, users, dossiers)
./scripts/prepare.sh

# 3. Configurer l'environnement
./scripts/setup.sh

# 4. Demarrer les services
./scripts/start.sh

# 5. Configurer les proxy hosts + SSL
./scripts/setup-proxy.sh
```

## Structure du projet

```
srv-media/
├── .env.example              # Template de configuration
├── compose/
│   ├── admin.yml             # Dashboard, Portainer, Dozzle, Watchtower, NPM
│   ├── media.yml             # Jellyfin, Plex, Tautulli, Jellyseerr
│   ├── arr.yml               # Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, Transmission, FlareSolverr
│   ├── music.yml             # Navidrome, Airsonic
│   ├── books.yml             # Calibre, Calibre-Web, Komga
│   ├── tools.yml             # Czkawka, MeTube, Rclone
│   └── monitoring.yml        # Prometheus, Grafana
├── config/
│   ├── dashboard/index.html  # Page d'accueil
│   ├── nginx-dashboard/      # Config nginx dashboard
│   └── prometheus/           # Config Prometheus
├── proxy/
│   └── proxy-hosts.json      # Liste des proxy hosts NPM
├── ansible/
│   ├── playbook.yml          # Preparation machine
│   ├── inventory.yml.example # Inventaire Ansible
│   └── vars.yml.example      # Variables Ansible
└── scripts/
    ├── prepare.sh            # Preparation machine (interactif, Ansible)
    ├── install.sh            # Installer Docker
    ├── setup.sh              # Creer dossiers, generer .env
    ├── start.sh              # Demarrer (interactif)
    ├── stop.sh               # Arreter (interactif)
    ├── restart.sh            # Redemarrer (stack ou service)
    ├── update.sh             # MAJ images Docker
    ├── status.sh             # Etat des containers
    ├── backup.sh             # Backup des configs
    └── setup-proxy.sh        # Creer proxy hosts NPM + SSL Cloudflare
```

## Structure des donnees

Basee sur les recommandations [TRaSH Guides](https://trash-guides.info/Hardlinks/How-to-setup-for/Docker/) pour supporter les **hardlinks** (zero copie, instant).

```
/data/
├── torrents/          # Downloads Transmission
│   ├── movies/
│   ├── tv/
│   ├── music/
│   └── books/
└── media/             # Bibliotheques organisees
    ├── movies/
    ├── tv/
    ├── music/
    ├── books/
    ├── comics/
    ├── youtube/
    └── podcasts/
```

> **Important** : `torrents/` et `media/` doivent etre sur le **meme filesystem** pour que les hardlinks fonctionnent.

## Scripts

| Script | Description |
|--------|-------------|
| `prepare.sh` | Prepare la machine via Ansible (update, docker, montages SMB/NFS/iSCSI, users, fstab) |
| `install.sh` | Installe Docker CE + Compose (Debian/Ubuntu) |
| `setup.sh` | Cree les dossiers, permissions, genere le `.env` interactivement |
| `start.sh` | Demarre les stacks (menu interactif ou `./start.sh all`) |
| `stop.sh` | Arrete les stacks (menu interactif ou `./stop.sh all`) |
| `restart.sh` | Redemarre une stack ou un service (`./restart.sh sonarr`) |
| `update.sh` | Pull les images et recree les containers |
| `status.sh` | Affiche l'etat de tous les containers |
| `backup.sh` | Backup tar.gz des configs (`--stop` pour coherence) |
| `setup-proxy.sh` | Cree les proxy hosts dans NPM + certificat SSL wildcard Cloudflare |

## Configuration des services (post-install)

### Connexions inter-services

Les containers communiquent via le reseau Docker `media-network` par nom de container :

| De | Vers | URL interne |
|----|------|-------------|
| Prowlarr | Sonarr | `http://sonarr:8989` |
| Prowlarr | Radarr | `http://radarr:7878` |
| Prowlarr | Lidarr | `http://lidarr:8686` |
| Prowlarr | FlareSolverr | `http://flaresolverr:8191` |
| Sonarr | Transmission | `http://transmission:9091` |
| Radarr | Transmission | `http://transmission:9091` |
| Lidarr | Transmission | `http://transmission:9091` |
| Bazarr | Sonarr | `http://sonarr:8989` |
| Bazarr | Radarr | `http://radarr:7878` |
| Jellyseerr | Jellyfin | `http://jellyfin:8096` |
| Jellyseerr | Sonarr | `http://sonarr:8989` |
| Jellyseerr | Radarr | `http://radarr:7878` |
| Tautulli | Plex | `http://plex:32400` |

### Root Folders (dans les apps *arr)

| App | Root Folder | Categorie Transmission |
|-----|-------------|------------------------|
| Sonarr | `/data/media/tv` | `tv` |
| Radarr | `/data/media/movies` | `movies` |
| Lidarr | `/data/media/music` | `music` |

### Acces externes (*.lib-lab.cloud)

| Service | URL externe |
|---------|-------------|
| Dashboard | `https://dashboard.media.lib-lab.cloud` |
| Portainer | `https://portainer.media.lib-lab.cloud` |
| Dozzle | `https://dozzle.lib-lab.cloud` |
| Jellyfin | `https://jellyfin.lib-lab.cloud` |
| Tautulli | `https://tautulli.lib-lab.cloud` |
| Jellyseerr | `https://jellyseerr.lib-lab.cloud` |
| Sonarr | `https://sonarr.lib-lab.cloud` |
| Radarr | `https://radarr.lib-lab.cloud` |
| Lidarr | `https://lidarr.lib-lab.cloud` |
| Bazarr | `https://bazarr.lib-lab.cloud` |
| Prowlarr | `https://prowlarr.lib-lab.cloud` |
| Transmission | `https://transmission.lib-lab.cloud` |
| FlareSolverr | `https://flaresolverr.lib-lab.cloud` |
| Navidrome | `https://navidrome.lib-lab.cloud` |
| Airsonic | `https://airsonic.lib-lab.cloud` |
| Calibre | `https://calibre.lib-lab.cloud` |
| Calibre-Web | `https://calibre-web.lib-lab.cloud` |
| Komga | `https://komga.lib-lab.cloud` |
| Czkawka | `https://czkawka.lib-lab.cloud` |
| MeTube | `https://metube.lib-lab.cloud` |
| Rclone | `https://rclone.lib-lab.cloud` |
| Prometheus | `https://prometheus.media.lib-lab.cloud` |
| Grafana | `https://grafana.media.lib-lab.cloud` |

## Ansible (preparation machine)

Le playbook `ansible/playbook.yml` gere :

- **system** : `apt update && upgrade`, paquets de base, timezone, locales
- **docker** : Installation Docker CE + Compose plugin, groupe docker
- **mounts** : Montages SMB/CIFS, NFS, iSCSI + ajout automatique dans `/etc/fstab`
- **dirs** : Creation de la structure `/data` + `/opt/srv-media/config`
- **network** : Reseau Docker `media-network`
- **project** : Clone du repo

```bash
# Tout executer
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml

# Seulement les montages
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml --tags mounts

# Seulement Docker
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml --tags docker
```

## Maintenance

```bash
# Mettre a jour toutes les images
./scripts/update.sh

# Backup des configs
./scripts/backup.sh

# Backup coherent (arrete les containers avant)
./scripts/backup.sh --stop

# Voir l'etat
./scripts/status.sh
```
