#!/bin/bash
# Discord Logger - envoie des événements serveur sur Discord via webhooks.
# Usage: ./discord-logger.sh {start|stop|connect|disconnect|death|raid|admin|backup} [args]

# Racine du projet (portable, quel que soit l'emplacement du repo)
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
CONFIG_FILE="${PROJECT_DIR}/config/discord-webhooks.conf"

# Charger les URLs (.env) et les réglages (conf)
[ -f "${ENV_FILE}" ] && set -a && . "${ENV_FILE}" && set +a
[ -f "${CONFIG_FILE}" ] && . "${CONFIG_FILE}"

DISCORD_BOT_NAME="${DISCORD_BOT_NAME:-PZ Server}"

log_discord() {
    local title="$1" message="$2" color="${3:-3447003}" webhook="${4:-$DISCORD_WEBHOOK_URL}"

    [ -z "${webhook}" ] && return 0  # webhook non configuré -> on ignore silencieusement

    local payload
    payload=$(cat <<EOF
{
  "username": "${DISCORD_BOT_NAME}",
  "embeds": [{
    "title": "${title}",
    "description": "${message}",
    "color": ${color},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
)
    curl -s -X POST "${webhook}" -H 'Content-Type: application/json' -d "${payload}" > /dev/null 2>&1
}

case "${1}" in
    start)      [ "${LOG_SERVER_START:-1}" = "1" ]      && log_discord "🟢 Serveur démarré"   "Le serveur vient de démarrer." "65280"    "${DISCORD_ANNOUNCE_WEBHOOK}" ;;
    stop)       [ "${LOG_SERVER_STOP:-1}" = "1" ]       && log_discord "🔴 Serveur arrêté"    "Le serveur s'est arrêté."      "16711680" "${DISCORD_ANNOUNCE_WEBHOOK}" ;;
    connect)    [ "${LOG_PLAYER_CONNECT:-1}" = "1" ]    && log_discord "👤 Connexion"          "**$2** a rejoint le serveur"   "65280"    "${DISCORD_CONNECT_WEBHOOK}" ;;
    disconnect) [ "${LOG_PLAYER_DISCONNECT:-1}" = "1" ] && log_discord "👤 Déconnexion"        "**$2** a quitté le serveur"    "16776960" "${DISCORD_CONNECT_WEBHOOK}" ;;
    death)      [ "${LOG_PLAYER_DEATH:-1}" = "1" ]      && log_discord "💀 Mort"               "**$2** est mort $3"            "16711680" "${DISCORD_DEATH_WEBHOOK:-$DISCORD_EVENT_WEBHOOK}" ;;
    raid)       [ "${LOG_RAIDS:-1}" = "1" ]             && log_discord "🧟 Raid"               "$2"                            "16711680" "${DISCORD_EVENT_WEBHOOK}" ;;
    admin)      [ "${LOG_ADMIN_ACTIONS:-1}" = "1" ]     && log_discord "🔧 Action admin"       "**$2** : $3"                   "16776960" ;;
    backup)     [ "${LOG_BACKUPS:-1}" = "1" ]           && log_discord "💾 Backup"             "Backup : $2"                   "3447003" ;;
    *) echo "Usage: $0 {start|stop|connect|disconnect|death|raid|admin|backup} [args]"; exit 1 ;;
esac
