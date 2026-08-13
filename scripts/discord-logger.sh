#!/bin/bash
# Discord Logger - sends server events to Discord via webhooks.
# Usage: ./discord-logger.sh {start|stop|connect|disconnect|death|raid|admin|backup} [args]

# Project root (portable, wherever the repo lives)
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
CONFIG_FILE="${PROJECT_DIR}/config/discord-webhooks.conf"

# Load URLs (.env) and settings (conf)
[ -f "${ENV_FILE}" ] && set -a && . "${ENV_FILE}" && set +a
[ -f "${CONFIG_FILE}" ] && . "${CONFIG_FILE}"

DISCORD_BOT_NAME="${DISCORD_BOT_NAME:-PZ Server}"

log_discord() {
    local title="$1" message="$2" color="${3:-3447003}" webhook="${4:-$DISCORD_WEBHOOK_URL}"

    [ -z "${webhook}" ] && return 0  # webhook not configured -> silently skip

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
    start)      [ "${LOG_SERVER_START:-1}" = "1" ]      && log_discord "🟢 Server started"     "The server is now online."     "65280"    "${DISCORD_ANNOUNCE_WEBHOOK}" ;;
    stop)       [ "${LOG_SERVER_STOP:-1}" = "1" ]       && log_discord "🔴 Server stopped"     "The server has stopped."       "16711680" "${DISCORD_ANNOUNCE_WEBHOOK}" ;;
    connect)    [ "${LOG_PLAYER_CONNECT:-1}" = "1" ]    && log_discord "👤 Connection"         "**$2** joined the server"      "65280"    "${DISCORD_CONNECT_WEBHOOK}" ;;
    disconnect) [ "${LOG_PLAYER_DISCONNECT:-1}" = "1" ] && log_discord "👤 Disconnection"      "**$2** left the server"        "16776960" "${DISCORD_CONNECT_WEBHOOK}" ;;
    death)      [ "${LOG_PLAYER_DEATH:-1}" = "1" ]      && log_discord "💀 Death"              "**$2** died $3"                "16711680" "${DISCORD_DEATH_WEBHOOK:-$DISCORD_EVENT_WEBHOOK}" ;;
    raid)       [ "${LOG_RAIDS:-1}" = "1" ]             && log_discord "🧟 Raid"               "$2"                            "16711680" "${DISCORD_EVENT_WEBHOOK}" ;;
    admin)      [ "${LOG_ADMIN_ACTIONS:-1}" = "1" ]     && log_discord "🔧 Admin action"       "**$2**: $3"                    "16776960" ;;
    backup)     [ "${LOG_BACKUPS:-1}" = "1" ]           && log_discord "💾 Backup"             "Backup: $2"                    "3447003" ;;
    *) echo "Usage: $0 {start|stop|connect|disconnect|death|raid|admin|backup} [args]"; exit 1 ;;
esac
