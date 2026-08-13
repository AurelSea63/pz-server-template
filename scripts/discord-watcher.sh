#!/bin/bash
# Watcher temps réel : lit les logs du conteneur PZ en continu et notifie Discord.
# Se relance tout seul si le conteneur redémarre. Idéal via systemd (voir README).
#
# Usage : sudo ./scripts/discord-watcher.sh
# Nécessite : docker + curl sur l'hôte, et les webhooks renseignés (.env ou conf).
#
# NB : PZ ne logge PAS les morts sur stdout -> non gérées ici (voir Logs/ du serveur).

set -u
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOGGER="${PROJECT_DIR}/scripts/discord-logger.sh"
CONTAINER="${PZ_CONTAINER:-pz-server}"

# Patterns de détection (ajustables via variables d'env si votre version diffère).
# Connexion : la ligne 'coop player=X/Y username="Nom"' porte le pseudo.
RE_CONNECT="${RE_CONNECT:-coop player=.*username=\"}"
RE_DISCONNECT="${RE_DISCONNECT:-Disconnected player|disconnected player}"
RE_READY="${RE_READY:-SERVER STARTED|server is listening}"

extract_user() {
    local u
    u=$(printf '%s' "$1" | grep -oiE '"[^"]{1,32}"' | head -1 | tr -d '"')
    [ -z "$u" ] && u=$(printf '%s' "$1" | grep -oiE 'username=[^ ,;]+' | head -1 | cut -d= -f2)
    printf '%s' "${u:-un joueur}"
}

notify() { "${LOGGER}" "$@" >/dev/null 2>&1 || true; }

echo "[watcher] démarrage — conteneur=${CONTAINER}"
while true; do
    # --since=1s : au (re)démarrage on ne rejoue pas l'historique (évite les doublons)
    docker logs -f --since=1s "${CONTAINER}" 2>&1 | while IFS= read -r line; do
        if   echo "$line" | grep -qiE "${RE_CONNECT}";    then notify connect    "$(extract_user "$line")"
        elif echo "$line" | grep -qiE "${RE_DISCONNECT}"; then notify disconnect "$(extract_user "$line")"
        elif echo "$line" | grep -qiE "${RE_READY}";      then notify start
        fi
    done

    # Flux coupé : le conteneur est-il réellement arrêté (vs simple redémarrage) ?
    if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null)" != "true" ]; then
        notify stop
    fi
    echo "[watcher] flux interrompu, reconnexion dans 5 s..."
    sleep 5
done
