#!/bin/bash
# Real-time watcher: reads the PZ container output and sends live Discord notifications.
#  - Connections / disconnections / startup: standard PZ log lines.
#  - Deaths: "[DEATHLOG] kills=.. hours=.. user=.." line emitted by the bundled DeathLog mod.
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

# Hours (integer) -> "X days and Y hours" (the game only provides hours).
fmt_survival() {
    local h="$1" d rem out=""
    d=$((h / 24)); rem=$((h % 24))
    [ "$d" -gt 0 ] && { out="$d day"; [ "$d" -gt 1 ] && out="${out}s"; }
    [ "$rem" -gt 0 ] && { [ -n "$out" ] && out="$out and "; out="${out}${rem} hour"; [ "$rem" -gt 1 ] && out="${out}s"; }
    [ -z "$out" ] && out="less than an hour"
    printf 'after surviving %s' "$out"
}

notify() { "${LOGGER}" "$@" >/dev/null 2>&1 || true; }

echo "[watcher] starting — container=${CONTAINER}"
while true; do
    # --since=1s: on (re)start we don't replay history (avoids duplicates)
    docker logs -f --since=1s "${CONTAINER}" 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -q "\[DEATHLOG\]"; then
            kills=$(printf '%s' "$line" | sed -nE 's/.*kills=([0-9]+).*/\1/p')
            hours=$(printf '%s' "$line" | sed -nE 's/.*hours=([0-9]+).*/\1/p')
            name=$(printf '%s' "$line"  | sed -nE 's/.*user=(.*)$/\1/p' | sed 's/[[:space:]]*$//')
            notify death "${name:-a player}" "$(fmt_survival "${hours:-0}") — ${kills:-0} zombies killed"
        elif echo "$line" | grep -qiE "${RE_CONNECT}";    then notify connect    "$(extract_user "$line")"
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
