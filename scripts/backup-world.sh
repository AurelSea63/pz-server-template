#!/bin/bash
# Sauvegarde / restauration du monde Project Zomboid.
# Usage: sudo ./scripts/backup-world.sh {backup|auto-backup|list|restore <nom>|delete <nom>}

set -u

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER_NAME="pz-server"
BACKUP_DIR="${PROJECT_DIR}/backups"
COMPOSE="docker compose -f ${PROJECT_DIR}/docker-compose.yml"
DATA_PATH="/opt/pz-server/Zomboid"   # chemin des données dans le conteneur
MAX_AUTO=10

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Archive le volume via un conteneur jetable qui partage les volumes du serveur
# (--volumes-from : pas besoin de connaître le nom du volume).
do_archive() {
    local out="$1"
    docker run --rm --volumes-from "${CONTAINER_NAME}" -v "${BACKUP_DIR}:/backup" alpine \
        tar czf "/backup/${out}" -C "${DATA_PATH}" .
}

backup() {
    mkdir -p "${BACKUP_DIR}"
    local name="zomboid_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo -e "${YELLOW}Arrêt du serveur pour une sauvegarde cohérente...${NC}"
    ${COMPOSE} stop && sleep 3
    echo -e "${BLUE}Archivage...${NC}"
    do_archive "${name}"
    ${COMPOSE} start
    echo -e "${GREEN}✓ Sauvegarde : ${BACKUP_DIR}/${name} ($(du -h "${BACKUP_DIR}/${name}" | cut -f1))${NC}"
}

auto_backup() {
    mkdir -p "${BACKUP_DIR}"
    local name="zomboid_auto_$(date +%Y%m%d_%H%M%S).tar.gz"
    do_archive "${name}"   # à chaud, sans couper le serveur
    echo "$(date '+%F %T') - backup ${name} ($(du -h "${BACKUP_DIR}/${name}" | cut -f1))"
    # Rotation : garder les MAX_AUTO plus récents
    ls -1t "${BACKUP_DIR}"/zomboid_auto_*.tar.gz 2>/dev/null | tail -n +$((MAX_AUTO + 1)) | xargs -r rm -f
}

list() {
    echo -e "${BLUE}Sauvegardes :${NC}"
    ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | awk '{print "  " $9 "  " $5}' || echo "  (aucune)"
}

restore() {
    local name="$1"
    [[ "${name}" != *.tar.gz ]] && name="${name}.tar.gz"
    [ -f "${BACKUP_DIR}/${name}" ] || { echo -e "${RED}Introuvable : ${name}${NC}"; exit 1; }
    echo -e "${RED}⚠️  Ceci écrase le monde actuel !${NC}"
    read -p "Taper 'oui' pour confirmer : " c; [ "${c}" = "oui" ] || { echo "Annulé"; exit 0; }
    ${COMPOSE} stop && sleep 3
    docker run --rm --volumes-from "${CONTAINER_NAME}" -v "${BACKUP_DIR}:/backup" alpine \
        sh -c "rm -rf ${DATA_PATH:?}/* && tar xzf /backup/${name} -C ${DATA_PATH}"
    ${COMPOSE} start
    echo -e "${GREEN}✓ Restauré : ${name}${NC}"
}

delete() {
    local name="$1"; [[ "${name}" != *.tar.gz ]] && name="${name}.tar.gz"
    rm -f "${BACKUP_DIR}/${name}" && echo -e "${GREEN}✓ Supprimé : ${name}${NC}"
}

case "${1:-}" in
    backup)       backup ;;
    auto-backup)  auto_backup ;;
    list)         list ;;
    restore)      restore "${2:?nom requis}" ;;
    delete)       delete "${2:?nom requis}" ;;
    *) echo "Usage: $0 {backup|auto-backup|list|restore <nom>|delete <nom>}"; exit 1 ;;
esac
