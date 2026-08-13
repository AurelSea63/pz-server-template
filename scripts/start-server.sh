#!/bin/bash
# Project Zomboid Server Startup Script
set -e

PZ_HOME="/opt/pz-server"
PZ_GAME_DIR="${PZ_HOME}/pzserver"
PZ_DATA_DIR="${PZ_HOME}/Zomboid"
CONFIG_FILE="${PZ_HOME}/config/ServerTestServer.ini"

# Le volume Zomboid est créé root par Docker. Si on démarre en root, on corrige
# les permissions puis on redescend en pzserver (sécurité) via gosu.
if [ "$(id -u)" = "0" ]; then
    mkdir -p "${PZ_DATA_DIR}"
    chown -R pzserver:pzserver "${PZ_DATA_DIR}"
    exec gosu pzserver "$0" "$@"
fi

# Identifiant serveur -> détermine le nom du .ini lu par PZ (<cachedir>/Server/<name>.ini)
SERVER_NAME="${PZ_SERVER_NAME_ID:-servertest}"
ADMIN_PASSWORD="${PZ_ADMIN_PASSWORD:-changeme}"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# Vérifier que le serveur PZ est bien présent dans l'image
if [ ! -f "${PZ_GAME_DIR}/start-server.sh" ]; then
    log_error "Serveur Project Zomboid introuvable dans ${PZ_GAME_DIR}"
    log_error "L'image a probablement été construite sans télécharger le jeu."
    log_error "Reconstruire : docker compose build --no-cache"
    ls -la "${PZ_GAME_DIR}" 2>/dev/null || log_error "Répertoire inexistant"
    exit 1
fi

# Répertoires de données
log_info "Préparation des répertoires de données..."
mkdir -p "${PZ_DATA_DIR}/Server"

# Copier la config vers l'emplacement attendu par le lanceur PZ
TARGET_INI="${PZ_DATA_DIR}/Server/${SERVER_NAME}.ini"
if [ -f "${CONFIG_FILE}" ]; then
    cp -f "${CONFIG_FILE}" "${TARGET_INI}"
    # Injecter les secrets depuis l'env (gardés hors git, cf. .env).
    # NB: éviter les caractères | & / dans ces mots de passe (délimiteur sed).
    [ -n "${PZ_SERVER_PASSWORD}" ] && sed -i "s|^Password=.*|Password=${PZ_SERVER_PASSWORD}|" "${TARGET_INI}"
    [ -n "${PZ_RCON_PASSWORD}" ]   && sed -i "s|^RCONPassword=.*|RCONPassword=${PZ_RCON_PASSWORD}|" "${TARGET_INI}"
    log_success "Config appliquée : ${TARGET_INI}"
else
    log_warn "Aucun fichier de config trouvé (${CONFIG_FILE}), PZ générera les valeurs par défaut."
fi

# Sandbox géré par git : si config/<serveur>_SandboxVars.lua existe, il fait foi
SANDBOX_SRC="${PZ_HOME}/config/${SERVER_NAME}_SandboxVars.lua"
if [ -f "${SANDBOX_SRC}" ]; then
    cp -f "${SANDBOX_SRC}" "${PZ_DATA_DIR}/Server/${SERVER_NAME}_SandboxVars.lua"
    log_success "SandboxVars appliqué depuis config/ (versionné git)"
fi

# Appliquer le heap Java depuis JAVA_OPTS (-Xmx...) au lanceur PZ (ProjectZomboid64.json)
PZ_JSON="${PZ_GAME_DIR}/ProjectZomboid64.json"
XMX=$(echo "${JAVA_OPTS}" | grep -oE '\-Xmx[0-9]+[gGmM]' | head -1)
if [ -n "${XMX}" ] && [ -f "${PZ_JSON}" ]; then
    sed -i -E "s/\"-Xmx[0-9]+[gGmM]\"/\"${XMX}\"/" "${PZ_JSON}" || true
    log_info "Heap Java positionné à ${XMX}"
fi

# Vérifier Java (le serveur embarque son JRE, mais on log la version système si dispo)
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | grep -oP 'version "\K[^"]*' || echo "embarqué")
    log_success "Java ${JAVA_VERSION} disponible"
fi

log_info "=========================================="
log_info "Démarrage du serveur Project Zomboid"
log_info "=========================================="
log_info "Serveur   : ${SERVER_NAME}"
log_info "Home      : ${PZ_HOME}"
log_info "Jeu       : ${PZ_GAME_DIR}"
log_info "Data      : ${PZ_DATA_DIR}"
log_info "Java Opts : ${JAVA_OPTS}"
log_info "=========================================="

if [ "${ADMIN_PASSWORD}" = "changeme" ]; then
    log_warn "Mot de passe admin par défaut ('changeme'). Définis PZ_ADMIN_PASSWORD dans docker-compose.yml !"
fi

# Fermeture gracieuse
trap 'log_info "Fermeture gracieuse demandée..."; kill -TERM "$child" 2>/dev/null; wait "$child"; exit 0' SIGTERM SIGINT

# Lancer via le lanceur natif de PZ (gère classpath + JRE embarqué)
cd "${PZ_GAME_DIR}"
./start-server.sh \
    -cachedir="${PZ_DATA_DIR}" \
    -servername "${SERVER_NAME}" \
    -adminpassword "${ADMIN_PASSWORD}" &
child=$!
wait "$child"
