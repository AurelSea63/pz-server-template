#!/bin/bash
# Watcher temps réel : notifie Discord en direct.
#  - Connexions / déconnexions / démarrage : lus sur la sortie du conteneur (docker logs).
#  - Morts : lues dans Zomboid/Logs/*_PerkLog.txt (lignes [Died][Hours Survived: N]).
# Se relance tout seul si le conteneur redémarre. Idéal via systemd (voir README).
#
# Usage : sudo ./scripts/discord-watcher.sh
# Nécessite : docker + curl sur l'hôte, webhooks renseignés (.env ou conf).

set -u
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGGER="${PROJECT_DIR}/scripts/discord-logger.sh"
CONTAINER="${PZ_CONTAINER:-pz-server}"

# Patterns (ajustables via variables d'env). Connexion = ligne 'coop player=X/Y username="Nom"'.
RE_CONNECT="${RE_CONNECT:-coop player=.*username=\"}"
RE_DISCONNECT="${RE_DISCONNECT:-Disconnected player|disconnected player}"
RE_READY="${RE_READY:-SERVER STARTED|server is listening}"

extract_user() {
    local u
    u=$(printf '%s' "$1" | grep -oiE '"[^"]{1,32}"' | head -1 | tr -d '"')
    [ -z "$u" ] && u=$(printf '%s' "$1" | grep -oiE 'username=[^ ,;]+' | head -1 | cut -d= -f2)
    printf '%s' "${u:-un joueur}"
}

# Heures (entier) -> "X jours et Y heures" (le log serveur n'a pas les minutes).
fmt_survival() {
    local h="$1" d rem out=""
    d=$((h / 24)); rem=$((h % 24))
    [ "$d" -gt 0 ] && { out="$d jour"; [ "$d" -gt 1 ] && out="${out}s"; }
    [ "$rem" -gt 0 ] && { [ -n "$out" ] && out="$out et "; out="${out}${rem} heure"; [ "$rem" -gt 1 ] && out="${out}s"; }
    [ -z "$out" ] && out="moins d'une heure"
    printf 'après avoir survécu %s' "$out"
}

notify() { "${LOGGER}" "$@" >/dev/null 2>&1 || true; }

# Chemin hôte du dossier Logs (via le montage du volume Zomboid — portable).
logs_dir() {
    local src
    src=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/opt/pz-server/Zomboid"}}{{.Source}}{{end}}{{end}}' "${CONTAINER}" 2>/dev/null)
    [ -n "$src" ] && printf '%s/Logs' "$src"
}

# Tâche de fond : suit le PerkLog courant et notifie les morts (avec temps de survie).
watch_deaths() {
    local dir f name hours
    while true; do
        dir=$(logs_dir); [ -z "$dir" ] && { sleep 15; continue; }
        f=$(ls -t "${dir}"/*_PerkLog.txt 2>/dev/null | head -1)
        [ -z "$f" ] && { sleep 15; continue; }
        # timeout : re-scanne le PerkLog le plus récent (nouveau fichier après un restart)
        timeout 600 tail -n0 -F "$f" 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                *"][Died][Hours Survived:"*)
                    name=$(printf '%s' "$line" | sed -nE 's/.*\[[0-9]{17}\]\[([^]]+)\].*\[Died\].*/\1/p')
                    hours=$(printf '%s' "$line" | sed -nE 's/.*Hours Survived: ([0-9]+).*/\1/p')
                    notify death "${name:-un joueur}" "$(fmt_survival "${hours:-0}")"
                    ;;
            esac
        done
    done
}

echo "[watcher] démarrage — conteneur=${CONTAINER}"
watch_deaths &                      # morts (via Logs/*_PerkLog.txt)
trap 'kill 0' EXIT                  # coupe la tâche de fond à la sortie

while true; do
    # --since=1s : au (re)démarrage on ne rejoue pas l'historique (évite les doublons)
    docker logs -f --since=1s "${CONTAINER}" 2>&1 | while IFS= read -r line; do
        if   echo "$line" | grep -qiE "${RE_CONNECT}";    then notify connect    "$(extract_user "$line")"
        elif echo "$line" | grep -qiE "${RE_DISCONNECT}"; then notify disconnect "$(extract_user "$line")"
        elif echo "$line" | grep -qiE "${RE_READY}";      then notify start
        fi
    done

    if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null)" != "true" ]; then
        notify stop
    fi
    echo "[watcher] flux interrompu, reconnexion dans 5 s..."
    sleep 5
done
