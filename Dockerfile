# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

# GoldenEye: Source ships a Windows server only, so it runs under Wine on top of the Windows build
# of the Source 2007 Dedicated Server (Steam app 310).

# ----------------------------
# Server settings
#   - STEAM_*: Source 2007 Dedicated Server, installed with SteamCMD (Windows depot, anonymous)
#   - GES_ARCHIVE: the official GE:S server archive (7z), as a URL or a path inside the container.
#     ModDB doesn't allow scripted downloads, so the default is a file you place in /config.
#   - GES_ARCHIVE_SHA256: checked before extracting; empty skips the check
#   - GES_*: server settings, passed as +cvar arguments by ges-server
# ----------------------------
ENV STEAM_APP_ID="310" \
    STEAM_APP_UPDATE="true" \
    STEAM_VALIDATE="false" \
    STEAM_USERNAME="anonymous" \
    STEAM_PASSWORD="" \
    STEAM_BRANCH="" \
    STEAM_BRANCH_PASSWORD="" \
    STEAM_INSTALL_ATTEMPTS="3" \
    GES_ARCHIVE="/config/GoldenEye_Source_v5.0.6_full_server_windows.7z" \
    GES_ARCHIVE_SHA256="79643189e9d6549e13ed9545d2277cb34bac05fff645d44d9de1f0ab030610d3" \
    GES_PORT="27015" \
    GES_MAP="ge_archives" \
    GES_MAX_PLAYERS="16" \
    GES_HOSTNAME="GoldenEye: Source Server" \
    GES_PASSWORD="" \
    GES_RCON_PASSWORD="" \
    GES_LAN="1" \
    GES_SERVER_CFG="server.cfg" \
    GES_EXTRA_ARGS="" \
    START_EXE="/usr/local/bin/ges-server" \
    START_ARGS=""

# ----------------------------
# SteamCMD (32-bit Linux client, installs the Windows depot) and 7-Zip for the GE:S archive
# ----------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
        lib32gcc-s1 \
        lib32stdc++6 \
        libc6-i386 \
        p7zip-full; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    \
    mkdir -p /opt/steamcmd; \
    curl -fsSL --retry 3 "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
      | tar -xz -C /opt/steamcmd; \
    chmod +x /opt/steamcmd/steamcmd.sh

COPY Scripts/ges-server /usr/local/bin/ges-server
RUN chmod +x /usr/local/bin/ges-server

COPY Hooks/ "${BASE_HOOKS}/"

# 27015/udp: game + server queries. 27015/tcp: RCON.
EXPOSE 27015/udp 27015/tcp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
