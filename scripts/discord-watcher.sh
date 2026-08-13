#!/bin/bash
# Real-time watcher: sends live Discord notifications.
#  - Connections / disconnections / startup: read from the container output (docker logs).
#  - Deaths: read from Zomboid/Logs/*_PerkLog.txt ([Died][Hours Survived: N] lines).
# Restarts itself if the container restarts. Best run via systemd (see README).
#
# Usage: sudo ./scripts/discord-watcher.sh
# Requires: docker + curl on the host, webhooks set (.env or conf).

set -u
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGGER="${PROJECT_DIR}/scripts/discord-logger.sh"
CONTAINER="${PZ_CONTAINER:-pz-server}"

# Detection patterns (overridable via env vars). Connect = 'coop player=X/Y username="Name"' line.
RE_CONNECT="${RE_CONNECT:-coop player=.*username=\"}"
RE_DISCONNECT="${RE_DISCONNECT:-Disconnected player|disconnected player}"
RE_READY="${RE_READY:-SERVER STARTED|server is listening}"

extract_user() {
    local u
    u=$(printf '%s' "$1" | grep -oiE '"[^"]{1,32}"' | head -1 | tr -d '"')
    [ -z "$u" ] && u=$(printf '%s' "$1" | grep -oiE 'username=[^ ,;]+' | head -1 | cut -d= -f2)
    printf '%s' "${u:-a player}"
}

# Hours (integer) -> "X days and Y hours" (the server log has no minutes).
fmt_survival() {
    local h="$1" d rem out=""
    d=$((h / 24)); rem=$((h % 24))
    [ "$d" -gt 0 ] && { out="$d day"; [ "$d" -gt 1 ] && out="${out}s"; }
    [ "$rem" -gt 0 ] && { [ -n "$out" ] && out="$out and "; out="${out}${rem} hour"; [ "$rem" -gt 1 ] && out="${out}s"; }
    [ -z "$out" ] && out="less than an hour"
    printf 'after surviving %s' "$out"
}

notify() { "${LOGGER}" "$@" >/dev/null 2>&1 || true; }

# Host path of the Logs folder (via the Zomboid volume mount — portable).
logs_dir() {
    local src
    src=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/opt/pz-server/Zomboid"}}{{.Source}}{{end}}{{end}}' "${CONTAINER}" 2>/dev/null)
    [ -n "$src" ] && printf '%s/Logs' "$src"
}

# Background task: follow the current PerkLog and notify deaths (with survival time).
watch_deaths() {
    local dir f name hours
    while true; do
        dir=$(logs_dir); [ -z "$dir" ] && { sleep 15; continue; }
        f=$(ls -t "${dir}"/*_PerkLog.txt 2>/dev/null | head -1)
        [ -z "$f" ] && { sleep 15; continue; }
        # timeout: periodically re-scan for the newest PerkLog (new file after a restart)
        timeout 600 tail -n0 -F "$f" 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                *"][Died][Hours Survived:"*)
                    name=$(printf '%s' "$line" | sed -nE 's/.*\[[0-9]{17}\]\[([^]]+)\].*\[Died\].*/\1/p')
                    hours=$(printf '%s' "$line" | sed -nE 's/.*Hours Survived: ([0-9]+).*/\1/p')
                    notify death "${name:-a player}" "$(fmt_survival "${hours:-0}")"
                    ;;
            esac
        done
    done
}

echo "[watcher] starting — container=${CONTAINER}"
watch_deaths &                      # deaths (via Logs/*_PerkLog.txt)
trap 'kill 0' EXIT                  # stop the background task on exit

while true; do
    # --since=1s: on (re)start we don't replay history (avoids duplicates)
    docker logs -f --since=1s "${CONTAINER}" 2>&1 | while IFS= read -r line; do
        if   echo "$line" | grep -qiE "${RE_CONNECT}";    then notify connect    "$(extract_user "$line")"
        elif echo "$line" | grep -qiE "${RE_DISCONNECT}"; then notify disconnect "$(extract_user "$line")"
        elif echo "$line" | grep -qiE "${RE_READY}";      then notify start
        fi
    done

    if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null)" != "true" ]; then
        notify stop
    fi
    echo "[watcher] stream interrupted, reconnecting in 5s..."
    sleep 5
done
