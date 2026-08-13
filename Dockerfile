# Project Zomboid Server - Dedicated (Build 41/42)
# Ubuntu 22.04 + SteamCMD + serveur PZ (app 380870) téléchargé au build
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PZ_USER=pzserver \
    PZ_HOME=/opt/pz-server \
    STEAMCMD_DIR=/opt/steamcmd \
    JAVA_OPTS="-Xmx6g -Xms2g -XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:+ParallelRefProcEnabled"

# Dépendances : le serveur PZ embarque son propre JRE, mais on garde les libs 32-bit
# et les utilitaires nécessaires à SteamCMD.
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    unzip \
    ca-certificates \
    tzdata \
    procps \
    libc6-i386 \
    lib32gcc-s1 \
    lib32stdc++6 \
    lib32z1 \
    && rm -rf /var/lib/apt/lists/*

# Utilisateur de service non-root
RUN useradd -m -s /bin/bash ${PZ_USER} && \
    mkdir -p ${PZ_HOME} ${STEAMCMD_DIR} && \
    chown -R ${PZ_USER}:${PZ_USER} ${PZ_HOME} ${STEAMCMD_DIR}

# Installer SteamCMD
RUN cd ${STEAMCMD_DIR} && \
    wget -q https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xzf steamcmd_linux.tar.gz && \
    rm steamcmd_linux.tar.gz && \
    chown -R ${PZ_USER}:${PZ_USER} ${STEAMCMD_DIR}

# Télécharger le serveur PZ EN TANT QUE pzserver (fichiers possédés par le bon user).
# +force_install_dir DOIT précéder +login.
# SteamCMD échoue souvent au 1er essai avec "Missing configuration" juste après son
# auto-update : on réessaie jusqu'à 5 fois, puis on vérifie que le launcher existe
# (sinon le build échoue bruyamment au lieu de produire une image sans le jeu).
USER ${PZ_USER}
RUN set -e; \
    for i in 1 2 3 4 5; do \
      echo "== SteamCMD tentative $i =="; \
      ${STEAMCMD_DIR}/steamcmd.sh \
        +force_install_dir ${PZ_HOME}/pzserver \
        +login anonymous \
        +app_update 380870 validate \
        +quit && break; \
      echo "SteamCMD tentative $i échouée, nouvel essai dans 10s..."; \
      sleep 10; \
    done; \
    test -f ${PZ_HOME}/pzserver/start-server.sh

# gosu (drop de privilèges à l'entrypoint). RUN séparé et placé après l'étape
# lourde du téléchargement pour préserver le cache du jeu lors des rebuilds.
USER root
RUN apt-get update && apt-get install -y gosu && rm -rf /var/lib/apt/lists/*

# Copier scripts (en root pour les permissions)
COPY ./scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh && \
    chown -R ${PZ_USER}:${PZ_USER} ${PZ_HOME}

WORKDIR ${PZ_HOME}

# Seules les données du monde sont persistées (le jeu est dans l'image)
VOLUME ["${PZ_HOME}/Zomboid"]

# Ports du serveur (UDP = jeu, TCP = admin/RCON)
EXPOSE 16210/tcp 16210/udp 16211/tcp 16211/udp

# Le conteneur démarre en root : l'entrypoint corrige les permissions du volume
# Zomboid (créé root par Docker) puis redescend en pzserver via gosu.

# Health check : le process serveur (GameServer) doit tourner
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD pgrep -f "zombie.network.GameServer" > /dev/null || exit 1

# Lancement
ENTRYPOINT ["/usr/local/bin/start-server.sh"]
