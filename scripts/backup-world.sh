#!/bin/bash
# Project Zomboid world backup / restore.
# Usage: sudo ./scripts/backup-world.sh {backup|auto-backup|list|restore <name>|delete <name>}

set -u

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER_NAME="pz-server"
BACKUP_DIR="${PROJECT_DIR}/backups"
COMPOSE="docker compose -f ${PROJECT_DIR}/docker-compose.yml"
DATA_PATH="/opt/pz-server/Zomboid"   # data path inside the container
MAX_AUTO=10

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Archive the volume via a throwaway container sharing the server's volumes
# (--volumes-from: no need to know the volume name).
do_archive() {
    local out="$1"
    docker run --rm --volumes-from "${CONTAINER_NAME}" -v "${BACKUP_DIR}:/backup" alpine \
        tar czf "/backup/${out}" -C "${DATA_PATH}" .
}

backup() {
    mkdir -p "${BACKUP_DIR}"
    local name="zomboid_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo -e "${YELLOW}Stopping the server for a consistent backup...${NC}"
    ${COMPOSE} stop && sleep 3
    echo -e "${BLUE}Archiving...${NC}"
    do_archive "${name}"
    ${COMPOSE} start
    echo -e "${GREEN}✓ Backup: ${BACKUP_DIR}/${name} ($(du -h "${BACKUP_DIR}/${name}" | cut -f1))${NC}"
}

auto_backup() {
    mkdir -p "${BACKUP_DIR}"
    local name="zomboid_auto_$(date +%Y%m%d_%H%M%S).tar.gz"
    do_archive "${name}"   # hot, without stopping the server
    echo "$(date '+%F %T') - backup ${name} ($(du -h "${BACKUP_DIR}/${name}" | cut -f1))"
    # Rotation: keep the MAX_AUTO most recent
    ls -1t "${BACKUP_DIR}"/zomboid_auto_*.tar.gz 2>/dev/null | tail -n +$((MAX_AUTO + 1)) | xargs -r rm -f
}

list() {
    echo -e "${BLUE}Backups:${NC}"
    ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | awk '{print "  " $9 "  " $5}' || echo "  (none)"
}

restore() {
    local name="$1"
    [[ "${name}" != *.tar.gz ]] && name="${name}.tar.gz"
    [ -f "${BACKUP_DIR}/${name}" ] || { echo -e "${RED}Not found: ${name}${NC}"; exit 1; }
    echo -e "${RED}⚠️  This overwrites the current world!${NC}"
    read -p "Type 'yes' to confirm: " c; [ "${c}" = "yes" ] || { echo "Cancelled"; exit 0; }
    ${COMPOSE} stop && sleep 3
    docker run --rm --volumes-from "${CONTAINER_NAME}" -v "${BACKUP_DIR}:/backup" alpine \
        sh -c "rm -rf ${DATA_PATH:?}/* && tar xzf /backup/${name} -C ${DATA_PATH}"
    ${COMPOSE} start
    echo -e "${GREEN}✓ Restored: ${name}${NC}"
}

delete() {
    local name="$1"; [[ "${name}" != *.tar.gz ]] && name="${name}.tar.gz"
    rm -f "${BACKUP_DIR}/${name}" && echo -e "${GREEN}✓ Deleted: ${name}${NC}"
}

case "${1:-}" in
    backup)       backup ;;
    auto-backup)  auto_backup ;;
    list)         list ;;
    restore)      restore "${2:?name required}" ;;
    delete)       delete "${2:?name required}" ;;
    *) echo "Usage: $0 {backup|auto-backup|list|restore <name>|delete <name>}"; exit 1 ;;
esac
