---
sidebar_label: Docker
---

# GoldenEye: Source Docker Container

This Docker container runs a GoldenEye: Source dedicated server. It is built on the WINE image. GE:S has only a Windows server, so the container runs the Windows Source 2007 Dedicated Server (`srcds.exe -game gesource`) under Wine.

## Quick Start

```yaml
services:
  goldeneyesource:
    image: lancommander/goldeneyesource:latest
    container_name: goldeneyesource

    ports:
      - 27015:27015/udp
      - 27015:27015/tcp

    volumes:
      - "/data/Servers/GoldenEye - Source/Deathmatch:/config"

    environment:
      GES_HOSTNAME: "My GoldenEye: Source Server"
      GES_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Before the first start, download `GoldenEye_Source_v5.0.6_full_server_windows.7z` from [geshl2.com/server-downloads](https://www.geshl2.com/server-downloads) and put it in the `/config` volume. ModDB, which hosts it, doesn't allow scripted downloads. You can instead set `GES_ARCHIVE` to an http(s) URL where you host the file.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallGoldenEyeSource.ps1`:
   - runs SteamCMD with `+@sSteamCmdForcePlatformType windows +app_update 310` into `Server/`. The Linux build of app 310 can't load the GE:S server DLLs, so the hook always installs the Windows depot.
   - checks the GE:S archive against `GES_ARCHIVE_SHA256`, extracts it with 7-Zip and moves its `gesource/` folder to `Server/gesource/`. The archive's hash is saved in `Server/gesource/.lancommander-archive`. The mod is reinstalled only when `GES_ARCHIVE_SHA256` (or, with no hash, `GES_ARCHIVE`) changes. Delete the marker to force a reinstall.
   - chowns `Server/` to the server user and remounts the overlay, so the new files show up in `Merged/`.
3. `PostInitialization/25-InstallSourceMod.ps1` installs the Windows builds of Metamod:Source and SourceMod into `gesource/addons/`, if they aren't there yet (`INSTALL_SOURCEMOD`).
4. `PostInitialization/30-InstallMatchStatistics.ps1` installs the LANCommander match statistics plugin when it's turned on (`MATCH_STATS_*`), or removes it.
5. `START_EXE` (`/usr/local/bin/ges-server`) runs `wine-run srcds.exe -console -game gesource -condebug -port <GES_PORT> +maxplayers ... +map <GES_MAP>` under Xvfb. It also follows `gesource/console.log` to stdout.

The first start downloads about 3 GB from Steam and extracts the 2 GB GE:S archive, so it takes several minutes. Later starts skip the extraction.

A successful start ends with:

```
Attempting to load scenario: deathmatch
Loading scenario DeathMatch from disk
Successfully loaded scenario deathmatch!
```

### Why Wine

The archive also contains a Linux `gesource/bin/server_i486.so`, but it isn't usable. Running on the Linux build of app 310, it needs `libldap_r-2.4.so.2` (no longer in Debian 12). With that supplied, it still aborts during the map load (`free(): invalid pointer`, `Invalid scenario ''`). The GE:S team's own Linux guide runs the Windows server under Wine, as this image does.

## Configuration Options

### Ports

- **27015/udp**: game traffic and server queries (`GES_PORT`)
- **27015/tcp**: RCON

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### Maps

`ge_archives`, `ge_aztec`, `ge_basement`, `ge_bunker`, `ge_casino`, `ge_caverns`, `ge_caves`, `ge_complex`, `ge_control`, `ge_cradle`, `ge_dam`, `ge_depot`, `ge_egyptian`, `ge_facility`, `ge_facility_backzone`, `ge_runway`, `ge_silo`, `ge_transition`. N64-style versions: `ge_archives_classic`, `ge_basement_classic`, `ge_bunker_classic`, `ge_complex_classic`, `ge_facility_classic`, `ge_library_classic`, `ge_stack_classic`, `ge_temple_classic`.

### Server Configuration

Put config files in `Overlay/gesource/cfg/`, so they're layered over the installed files. The archive ships several ready-made configs (`server_dm_only.cfg`, `server_teamplay.cfg`, `server_n64_classic.cfg`, ...), which you can select with `GES_SERVER_CFG`.

- `server.cfg` (or `GES_SERVER_CFG`) runs on every map load
- `valve.rc` runs once at server start
- `cfg/<gameplay>.cfg` runs when that gameplay mode loads
- `mapcycle.txt` / `gameplaycycle.txt` hold the legacy map and gameplay cycles

See the [GE:S server configuration reference](https://docs.geshl2.com/server/configure/reference/).

The `GES_*` variables are passed as command-line cvars, which run before `server.cfg`. So a value that `server.cfg` sets for the same cvar (e.g. `hostname`) wins.

### Hooks

| Hook | When |
|------|------|
| `PreSteamInstallGame` / `PostSteamInstallGame` | Around the SteamCMD install of app 310 |
| `PreInstallGoldenEyeSource` / `PostInstallGoldenEyeSource` | Around the GE:S archive install |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |
| `PreInstallSourceMod` / `PostInstallSourceMod` | Around the Metamod:Source and SourceMod install |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

### SourceMod and Match Statistics

[Metamod:Source and SourceMod](https://www.sourcemod.net/) are installed into `gesource/addons/` (in `Overlay/`) on the first start.
They're the Windows builds, because `srcds.exe` runs under Wine. They aren't updated afterwards: delete
`Overlay/gesource/addons/metamod` or `Overlay/gesource/addons/sourcemod` to have them installed again. Put plugins in
`Overlay/gesource/addons/sourcemod/plugins/`. SourceMod has no gamedata for GoldenEye: Source, so plugins that need SDK Tools'
game-specific functions may not work.

| Variable | Description | Default |
|----------|-------------|---------|
| `INSTALL_SOURCEMOD` | Install Metamod:Source and SourceMod | `true` |
| `METAMOD_MAJOR_VERSION` / `METAMOD_VERSION` | Metamod:Source build | `1.12` / `1.12.0-git1229` |
| `SOURCEMOD_MAJOR_VERSION` / `SOURCEMOD_VERSION` | SourceMod build | `1.12` / `1.12.0-git7259` |
| `METAMOD_URL` / `SOURCEMOD_URL` | Download these instead | |

The server can report the matches played on it to LANCommander, with the
[LANCommander match statistics plugin](https://github.com/LANCommander/LANCommander.MatchStatistics.SourceMod).
The plugin is built into the image and needs SourceMod. It is turned on when `MATCH_STATS_SERVER_URL` and
`MATCH_STATS_TOKEN` are set, and is then copied into `gesource/addons/sourcemod/` on every start. There is no GoldenEye: Source module, so the
plugin records what every Source game shares: players, kills, damage, spawns, chat and the standings. Turned off, the plugin's files are removed again.

| Variable | Description | Default |
|----------|-------------|---------|
| `MATCH_STATS_ENABLED` | `auto`: on when `MATCH_STATS_SERVER_URL` and `MATCH_STATS_TOKEN` are set. `true` or `false` | `auto` |
| `MATCH_STATS_SERVER_URL` | The LANCommander server, e.g. `http://lancommander.lan:1337` | *(empty)* |
| `MATCH_STATS_TOKEN` | A LANCommander access token with the **Report matches** scope (Profile → Access Tokens). It isn't written to any file | *(empty)* |
| `MATCH_STATS_GAME_ID` | The game's id in LANCommander | *(empty)* |
| `MATCH_STATS_SERVER_ID` | This server's id in LANCommander, if LANCommander manages it | *(empty)* |
| `MATCH_STATS_REPORTER_NAME` | How the server is named in LANCommander | *(hostname)* |
| `MATCH_STATS_MIN_PLAYERS` | Human players needed before a match is recorded | *(1)* |
| `MATCH_STATS_MODE` | The mode reported. Empty lets the game module decide | *(empty)* |
| `MATCH_STATS_RECORD_BOTS` | Record bots as players (`true`/`false`) | *(true)* |
| `MATCH_STATS_RECORD_CHAT` | Record chat messages (`true`/`false`) | *(false)* |
| `MATCH_STATS_ATTACH_DEMOS` | Upload SourceTV demos recorded with `tv_record` (`true`/`false`) | *(true)* |

The settings are written to `gesource/cfg/sourcemod/lancommander.cfg` as `lc_*` cvars on every start. Settings left
empty aren't written, so they and the plugin's other `lc_*` cvars (see its README) can be set in
`gesource/cfg/sourcemod/sourcemod.cfg` instead. A `lancommander.cfg` you put in `Overlay/gesource/cfg/sourcemod/` yourself
is left alone.

`sm_lc_status` over RCON shows the match being recorded and how delivery is going. Reports that couldn't be
delivered yet are kept in `Overlay/gesource/addons/sourcemod/extensions/.interposer/Matches/` and sent once LANCommander
can be reached.

## Troubleshooting

- **`GoldenEye: Source is not installed and GES_ARCHIVE (...) was not found`**: the archive isn't at the `GES_ARCHIVE` path. Check the file name and that it's inside the `/config` volume.
- **`sha256 mismatch`**: the archive isn't the official 5.0.6 server archive, or the download is incomplete. If you use another release on purpose, set `GES_ARCHIVE_SHA256` to its hash, or to empty to skip the check.
- **About 20% CPU when idle**: this is normal for srcds under Wine.
- **No output in `docker logs` after `Starting: srcds.exe ...`**: srcds writes its console to `gesource/console.log` only after the engine has started. The first start under Wine can take a minute.
