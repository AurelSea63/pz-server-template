#!/bin/bash
# Project Zomboid Server Startup Script
set -e

PZ_HOME="/opt/pz-server"
PZ_GAME_DIR="${PZ_HOME}/pzserver"
PZ_DATA_DIR="${PZ_HOME}/Zomboid"
CONFIG_FILE="${PZ_HOME}/config/ServerTestServer.ini"

# The Zomboid volume is created as root by Docker. If we start as root, fix the
# permissions then drop to pzserver (security) via gosu.
if [ "$(id -u)" = "0" ]; then
    mkdir -p "${PZ_DATA_DIR}"
    chown -R pzserver:pzserver "${PZ_DATA_DIR}"
    exec gosu pzserver "$0" "$@"
fi

# Server id -> determines the .ini name read by PZ (<cachedir>/Server/<name>.ini)
SERVER_NAME="${PZ_SERVER_NAME_ID:-servertest}"
ADMIN_PASSWORD="${PZ_ADMIN_PASSWORD:-changeme}"

# Log colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# Make sure the PZ server is present in the image
if [ ! -f "${PZ_GAME_DIR}/start-server.sh" ]; then
    log_error "Project Zomboid server not found in ${PZ_GAME_DIR}"
    log_error "The image was probably built without downloading the game."
    log_error "Rebuild: docker compose build --no-cache"
    ls -la "${PZ_GAME_DIR}" 2>/dev/null || log_error "Directory does not exist"
    exit 1
fi

# Data directories
log_info "Preparing data directories..."
mkdir -p "${PZ_DATA_DIR}/Server"

# Copy the config to the location expected by the PZ launcher
TARGET_INI="${PZ_DATA_DIR}/Server/${SERVER_NAME}.ini"
if [ -f "${CONFIG_FILE}" ]; then
    cp -f "${CONFIG_FILE}" "${TARGET_INI}"
    # Inject secrets from the env (kept out of git, see .env).
    # NB: avoid the characters | & / in these passwords (sed delimiter).
    [ -n "${PZ_SERVER_PASSWORD}" ] && sed -i "s|^Password=.*|Password=${PZ_SERVER_PASSWORD}|" "${TARGET_INI}"
    [ -n "${PZ_RCON_PASSWORD}" ]   && sed -i "s|^RCONPassword=.*|RCONPassword=${PZ_RCON_PASSWORD}|" "${TARGET_INI}"
    log_success "Config applied: ${TARGET_INI}"
else
    log_warn "No config file found (${CONFIG_FILE}), PZ will generate defaults."
fi

# Sandbox managed by git: if config/<server>_SandboxVars.lua exists, it wins
SANDBOX_SRC="${PZ_HOME}/config/${SERVER_NAME}_SandboxVars.lua"
if [ -f "${SANDBOX_SRC}" ]; then
    cp -f "${SANDBOX_SRC}" "${PZ_DATA_DIR}/Server/${SERVER_NAME}_SandboxVars.lua"
    log_success "SandboxVars applied from config/ (git-versioned)"
fi

# Apply the Java heap from JAVA_OPTS (-Xmx...) to the PZ launcher (ProjectZomboid64.json)
PZ_JSON="${PZ_GAME_DIR}/ProjectZomboid64.json"
XMX=$(echo "${JAVA_OPTS}" | grep -oE '\-Xmx[0-9]+[gGmM]' | head -1)
if [ -n "${XMX}" ] && [ -f "${PZ_JSON}" ]; then
    sed -i -E "s/\"-Xmx[0-9]+[gGmM]\"/\"${XMX}\"/" "${PZ_JSON}" || true
    log_info "Java heap set to ${XMX}"
fi

# Check Java (the server bundles its own JRE, but we log the system version if available)
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | grep -oP 'version "\K[^"]*' || echo "bundled")
    log_success "Java ${JAVA_VERSION} available"
fi

log_info "=========================================="
log_info "Starting the Project Zomboid server"
log_info "=========================================="
log_info "Server    : ${SERVER_NAME}"
log_info "Home      : ${PZ_HOME}"
log_info "Game      : ${PZ_GAME_DIR}"
log_info "Data      : ${PZ_DATA_DIR}"
log_info "Java Opts : ${JAVA_OPTS}"
log_info "=========================================="

if [ "${ADMIN_PASSWORD}" = "changeme" ]; then
    log_warn "Default admin password ('changeme'). Set PZ_ADMIN_PASSWORD in .env!"
fi

# Graceful shutdown
trap 'log_info "Graceful shutdown requested..."; kill -TERM "$child" 2>/dev/null; wait "$child"; exit 0' SIGTERM SIGINT

# Launch via PZ's native launcher (handles classpath + bundled JRE)
cd "${PZ_GAME_DIR}"
./start-server.sh \
    -cachedir="${PZ_DATA_DIR}" \
    -servername "${SERVER_NAME}" \
    -adminpassword "${ADMIN_PASSWORD}" &
child=$!
wait "$child"
