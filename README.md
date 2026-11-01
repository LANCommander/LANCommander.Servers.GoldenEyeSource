# GoldenEye: Source Server (Docker)

This repository provides a Dockerized **GoldenEye: Source** dedicated server. GE:S 5.0 ships only a Windows server, so the image runs the Windows build of the Source 2007 Dedicated Server (`srcds.exe`) under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Installs and updates the Source 2007 Dedicated Server (Steam app 310) with SteamCMD, anonymously
- Installs the `gesource` mod from the official GE:S server archive (5.0.6). The archive's sha256 is checked, and the mod is reinstalled only when the archive changes.
- Common server settings are environment variables
- The server console (`gesource/console.log`) is streamed to `docker logs`
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  goldeneyesource:
    image: lancommander/goldeneyesource:latest
    container_name: goldeneyesource

    ports:
      - "27015:27015/udp"
      - "27015:27015/tcp"

    volumes:
      - ./config:/config

    environment:
      GES_HOSTNAME: "My GoldenEye: Source Server"
      GES_MAP: "ge_archives"
      GES_MAX_PLAYERS: "16"
      GES_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

---

## Game Files

The server is installed in two parts:

1. **Source 2007 Dedicated Server**: SteamCMD downloads Steam app 310 (Windows depot, about 3 GB) into `config/Server/` on every start. Set `STEAM_APP_UPDATE=false` to skip the update once it is installed.
2. **GoldenEye: Source**: the `gesource/` folder comes from the official server archive, `GoldenEye_Source_v5.0.6_full_server_windows.7z`, listed on [geshl2.com/server-downloads](https://www.geshl2.com/server-downloads). ModDB, which hosts it, doesn't allow scripted downloads. So download it in a browser and put it at `config/GoldenEye_Source_v5.0.6_full_server_windows.7z`, or set `GES_ARCHIVE` to a URL where you host it. It is extracted to `Server/gesource/` on the first start. After that the archive can be deleted.

## Directory Layout (Host)

```text
.
└── config/
    ├── GoldenEye_Source_v5.0.6_full_server_windows.7z   # GE:S server archive (only needed for the install)
    ├── Server/            # srcds.exe, hl2/, bin/ (SteamCMD) and gesource/ (from the archive)
    ├── Overlay/           # Your files, layered on top of Server/ (e.g. gesource/cfg/server.cfg)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).

| Variable | Description | Default |
|----------|-------------|---------|
| `GES_ARCHIVE` | GE:S server archive (7z): a path in the container or an http(s) URL | `/config/GoldenEye_Source_v5.0.6_full_server_windows.7z` |
| `GES_ARCHIVE_SHA256` | Expected sha256 of the archive. Empty skips the check. | sha256 of the official 5.0.6 archive |
| `GES_PORT` | Game port (`-port`) | `27015` |
| `GES_MAP` | Starting map (`+map`) | `ge_archives` |
| `GES_MAX_PLAYERS` | `+maxplayers` | `16` |
| `GES_HOSTNAME` | `+hostname` | `GoldenEye: Source Server` |
| `GES_PASSWORD` | `+sv_password`. Empty means no password. | |
| `GES_RCON_PASSWORD` | `+rcon_password`. Empty disables RCON. | |
| `GES_LAN` | `+sv_lan`: `1` for LAN only, `0` for internet | `1` |
| `GES_SERVER_CFG` | `+servercfgfile`, run on every map load (in `gesource/cfg/`) | `server.cfg` |
| `GES_EXTRA_ARGS` | Extra srcds arguments, split on whitespace (e.g. `-insecure`) | |
| `STEAM_APP_ID` | Source 2007 Dedicated Server app | `310` |
| `STEAM_APP_UPDATE` | Install/update app 310 on start | `true` |
| `STEAM_VALIDATE` | Validate the install on every start | `false` |
| `STEAM_USERNAME` / `STEAM_PASSWORD` | SteamCMD login | `anonymous` / |
| `STEAM_BRANCH` / `STEAM_BRANCH_PASSWORD` | SteamCMD beta branch | |
| `STEAM_INSTALL_ATTEMPTS` | SteamCMD retries | `3` |
| `START_EXE` | Launcher | `/usr/local/bin/ges-server` |
| `START_ARGS` | Extra arguments, passed before the `GES_*` cvars. Prefer `GES_EXTRA_ARGS`: the base entrypoint splits a single-word `START_ARGS` into characters. | |

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/goldeneyesource:local .
```

---

## License

GoldenEye: Source, the Source Dedicated Server and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
