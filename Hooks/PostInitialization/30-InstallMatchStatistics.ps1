#Requires -Modules Logging

# LANCommander match statistics: install the SourceMod plugin
# (https://github.com/LANCommander/LANCommander.MatchStatistics.SourceMod) next to SourceMod, so the
# matches played on the server are reported to LANCommander.
#
# The plugin's addons/ folder is built into the image, in /opt/lancommander-stats. When the match
# statistics are on, this writes into <GAME_MOD>/ in Merged/, so into Overlay/:
#
#   addons/sourcemod/extensions/   The extension (lancommander.ext.*, and x64/ for 64-bit servers). Its
#                                  .interposer/ folder keeps the logs and the reports not delivered yet
#   addons/sourcemod/plugins/      The core plugin, the integrations (Get5 and Retakes only for
#                                  cstrike), and the game modules in disabled/
#   addons/sourcemod/configs/      lancommander_events.cfg
#   cfg/sourcemod/lancommander.cfg The MATCH_STATS_* settings as lc_* cvars. One that this hook didn't
#                                  write is left alone
#
# Turned off, the plugin's files are removed again. lancommander.cfg and .interposer/ are kept.

$header = '// Generated from the MATCH_STATS_* environment variables on every start'
$source = '/opt/lancommander-stats'

function ConvertTo-Bool([string] $Value) {
    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in 'true', '1', 'yes', 'on' }   { return '1' }
        { $_ -in 'false', '0', 'no', 'off' } { return '0' }
        default                              { return $null }
    }
}

function Get-Hash([string] $Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
}

function ConvertTo-Quoted([string] $Value) { '"' + $Value.Replace('"', '').Replace(';', '') + '"' }

$enabled = switch (ConvertTo-Bool "$Env:MATCH_STATS_ENABLED") {
    '1'     { $true }
    '0'     { $false }
    default { [bool]($Env:MATCH_STATS_SERVER_URL -and $Env:MATCH_STATS_TOKEN) }
}

if (-not $Env:GAME_MOD -or -not (Test-Path -LiteralPath "$source/addons" -PathType Container)) {
    Write-Log -Level Error "The match statistics plugin is missing from $source, or GAME_MOD is empty"
    return
}

$gameDir = Join-Path $Env:SERVER_ROOT $Env:GAME_MOD
$files = Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
    [System.IO.Path]::GetRelativePath($source, $_.FullName)
}

# Get5 and Retakes need SourceMod's Counter-Strike extension and fail to load in any other game
$csOnly = 'addons/sourcemod/plugins/lancommander_stats_get5.smx', 'addons/sourcemod/plugins/lancommander_stats_retakes.smx'
$skipped = if ($Env:GAME_MOD -notin 'cstrike', 'csgo') { $csOnly } else { @() }

function Remove-PluginFiles([string[]] $Files) {
    $removed = 0
    foreach ($file in $Files) {
        $target = Join-Path $gameDir $file
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -Force -LiteralPath $target
            $removed++
        }
    }
    $removed
}

if (-not $enabled) {
    if (Remove-PluginFiles $files) { Write-Log "Match statistics are off; removed the plugin from $Env:GAME_MOD/addons/sourcemod" }
    return
}

$smDir = Join-Path $gameDir 'addons/sourcemod'
if (-not (Test-Path -LiteralPath $smDir -PathType Container)) {
    Write-Log -Level Error "SourceMod isn't installed in $Env:GAME_MOD/addons, so the match statistics plugin can't be installed (set INSTALL_SOURCEMOD=true)"
    return
}

# The server runs as UID:GID and the extension writes .interposer/ next to itself. Not -R through
# Merged/, which would copy every file up into Overlay/
$owned = [System.Collections.Generic.HashSet[string]]::new()

[void](Remove-PluginFiles $skipped)

foreach ($file in $files | Where-Object { $_ -notin $skipped }) {
    $from = Join-Path $source $file
    $target = Join-Path $gameDir $file
    $dir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [void]$owned.Add($dir)
    if ((Get-Hash $target) -ne (Get-Hash $from)) {
        Copy-Item -Force -LiteralPath $from -Destination $target
        [void]$owned.Add($target)
    }
}

# Only settings that are set, so the others can come from server.cfg. The token stays in the
# environment: the plugin expands %MATCH_STATS_TOKEN% itself
$values = [ordered]@{
    'lc_enabled'       = '1'
    'lc_server_url'    = $(if ($Env:MATCH_STATS_SERVER_URL) { ConvertTo-Quoted $Env:MATCH_STATS_SERVER_URL.TrimEnd('/') })
    'lc_token'         = $(if ($Env:MATCH_STATS_TOKEN) { '"%MATCH_STATS_TOKEN%"' })
    'lc_game_id'       = $(if ($Env:MATCH_STATS_GAME_ID) { ConvertTo-Quoted $Env:MATCH_STATS_GAME_ID })
    'lc_server_id'     = $(if ($Env:MATCH_STATS_SERVER_ID) { ConvertTo-Quoted $Env:MATCH_STATS_SERVER_ID })
    'lc_reporter_name' = $(if ($Env:MATCH_STATS_REPORTER_NAME) { ConvertTo-Quoted $Env:MATCH_STATS_REPORTER_NAME })
    'lc_min_players'   = $Env:MATCH_STATS_MIN_PLAYERS
    'lc_mode'          = $(if ($Env:MATCH_STATS_MODE) { ConvertTo-Quoted $Env:MATCH_STATS_MODE })
    'lc_record_bots'   = $(if ($Env:MATCH_STATS_RECORD_BOTS) { ConvertTo-Bool $Env:MATCH_STATS_RECORD_BOTS })
    'lc_record_chat'   = $(if ($Env:MATCH_STATS_RECORD_CHAT) { ConvertTo-Bool $Env:MATCH_STATS_RECORD_CHAT })
    'lc_attach_demos'  = $(if ($Env:MATCH_STATS_ATTACH_DEMOS) { ConvertTo-Bool $Env:MATCH_STATS_ATTACH_DEMOS })
}

$lines = @("$header. Settings left out keep their defaults; set them in cfg/sourcemod/sourcemod.cfg")
foreach ($key in $values.Keys) {
    if ($values[$key]) { $lines += "$key $($values[$key])" }
}

$cfgDir = Join-Path $gameDir 'cfg/sourcemod'
$cfg = Join-Path $cfgDir 'lancommander.cfg'
if ((Test-Path -LiteralPath $cfg) -and -not "$(Get-Content -LiteralPath $cfg -TotalCount 1)".StartsWith($header)) {
    Write-Log -Level Warning "$Env:GAME_MOD/cfg/sourcemod/lancommander.cfg wasn't written by this image and is left alone, so the MATCH_STATS_* settings aren't applied. Delete it to have it generated"
} else {
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    [System.IO.File]::WriteAllText($cfg, ($lines -join "`n") + "`n")
    [void]$owned.Add($cfgDir)
    [void]$owned.Add($cfg)
}

chown "$($Env:UID):$($Env:GID)" @($owned)

foreach ($setting in 'MATCH_STATS_SERVER_URL', 'MATCH_STATS_TOKEN', 'MATCH_STATS_GAME_ID') {
    if (-not [Environment]::GetEnvironmentVariable($setting)) {
        Write-Log -Level Warning "Match statistics are on, but $setting is empty; set it here or as lc_* in cfg/sourcemod/sourcemod.cfg"
    }
}

Write-Log "Match statistics are on: the LANCommander plugin is installed in $Env:GAME_MOD/addons/sourcemod"
