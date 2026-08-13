# Project Zomboid Dedicated Server (Build 41/42)
# Ubuntu 22.04 + SteamCMD + PZ server (app 380870) downloaded at build time
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PZ_USER=pzserver \
    PZ_HOME=/opt/pz-server \
    STEAMCMD_DIR=/opt/steamcmd \
    JAVA_OPTS="-Xmx6g -Xms2g -XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:+ParallelRefProcEnabled"

# Dependencies: the PZ server bundles its own JRE, but we keep the 32-bit libs
# and the utilities SteamCMD needs.
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

# Non-root service user
RUN useradd -m -s /bin/bash ${PZ_USER} && \
    mkdir -p ${PZ_HOME} ${STEAMCMD_DIR} && \
    chown -R ${PZ_USER}:${PZ_USER} ${PZ_HOME} ${STEAMCMD_DIR}

# Install SteamCMD
RUN cd ${STEAMCMD_DIR} && \
    wget -q https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz && \
    tar -xzf steamcmd_linux.tar.gz && \
    rm steamcmd_linux.tar.gz && \
    chown -R ${PZ_USER}:${PZ_USER} ${STEAMCMD_DIR}

# Download the PZ server AS pzserver (files owned by the right user).
# +force_install_dir MUST come before +login.
# SteamCMD often fails on the 1st try with "Missing configuration" right after its
# self-update: we retry up to 5 times, then check the launcher exists
# (so the build fails loudly instead of producing an image without the game).
USER ${PZ_USER}
RUN set -e; \
    for i in 1 2 3 4 5; do \
      echo "== SteamCMD attempt $i =="; \
      ${STEAMCMD_DIR}/steamcmd.sh \
        +force_install_dir ${PZ_HOME}/pzserver \
        +login anonymous \
        +app_update 380870 validate \
        +quit && break; \
      echo "SteamCMD attempt $i failed, retrying in 10s..."; \
      sleep 10; \
    done; \
    test -f ${PZ_HOME}/pzserver/start-server.sh

# gosu (privilege drop at the entrypoint). Separate RUN placed after the heavy
# download step to preserve the game cache across rebuilds.
USER root
RUN apt-get update && apt-get install -y gosu && rm -rf /var/lib/apt/lists/*

# Copy scripts (as root for permissions)
COPY ./scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh && \
    chown -R ${PZ_USER}:${PZ_USER} ${PZ_HOME}

WORKDIR ${PZ_HOME}

# Only the world data is persisted (the game lives in the image)
VOLUME ["${PZ_HOME}/Zomboid"]

# Server ports (UDP = game, TCP = admin/RCON)
EXPOSE 16210/tcp 16210/udp 16211/tcp 16211/udp

# The container starts as root: the entrypoint fixes the Zomboid volume
# permissions (created root by Docker) then drops to pzserver via gosu.

# Health check: the server process (GameServer) must be running
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD pgrep -f "zombie.network.GameServer" > /dev/null || exit 1

# Launch
ENTRYPOINT ["/usr/local/bin/start-server.sh"]
