#Requires -Modules Hooks
#Requires -Modules Logging

# Installs Metamod:Source and SourceMod (their Windows builds, since srcds.exe runs under Wine) into
# <GAME_MOD>/addons in Merged/, so into Overlay/. Runs after 20-InstallGoldenEyeSource.ps1, and only when they
# aren't installed yet: to update them, delete Overlay/<GAME_MOD>/addons/metamod or
# Overlay/<GAME_MOD>/addons/sourcemod.

if ($Env:INSTALL_SOURCEMOD -notin @('true', '1')) {
    Write-Log "INSTALL_SOURCEMOD is not enabled. Skipping SourceMod installation."
    return
}

$gameDir = Join-Path $Env:SERVER_ROOT $Env:GAME_MOD
$addons  = Join-Path $gameDir 'addons'

$metaModUrl = if ($Env:METAMOD_URL) { $Env:METAMOD_URL } else {
    "https://mms.alliedmods.net/mmsdrop/${Env:METAMOD_MAJOR_VERSION}/mmsource-${Env:METAMOD_VERSION}-windows.zip"
}
$sourceModUrl = if ($Env:SOURCEMOD_URL) { $Env:SOURCEMOD_URL } else {
    "https://sm.alliedmods.net/smdrop/${Env:SOURCEMOD_MAJOR_VERSION}/sourcemod-${Env:SOURCEMOD_VERSION}-windows.zip"
}

function Install-Archive([string] $Name, [string] $Url) {
    $archive = "/tmp/$Name.zip"
    Write-Log "Downloading $Name from $Url"
    curl -fsSL --retry 3 --output $archive $Url
    if ($LASTEXITCODE -ne 0) {
        Write-Log -Level Error "Failed to download $Name from $Url"
        return $false
    }
    Write-Log "Extracting $Name to $gameDir"
    Expand-Archive -Path $archive -DestinationPath $gameDir -Force
    Remove-Item -Force $archive
    return $true
}

$installed = $false

if (-not (Test-Path -Path (Join-Path $addons 'metamod'))) {
    Invoke-Hook "PreInstallSourceMod"
    if (-not (Install-Archive 'mmsource' $metaModUrl)) { return }
    # srcds.exe is 32-bit, so metamod.vdf loads Metamod:Source; the 64-bit entry only fails to load
    Remove-Item -Path (Join-Path $addons 'metamod_x64.vdf') -Force -ErrorAction SilentlyContinue
    $installed = $true
}

if (-not (Test-Path -Path (Join-Path $addons 'sourcemod'))) {
    if (-not $installed) { Invoke-Hook "PreInstallSourceMod" }
    if (-not (Install-Archive 'sourcemod' $sourceModUrl)) { return }
    $installed = $true
}

if ($installed) {
    # The server runs as UID:GID and SourceMod writes its logs and data next to itself. Only the
    # new folders, which are all in Overlay/
    chown -R "$($Env:UID):$($Env:GID)" $addons (Join-Path $gameDir 'cfg/sourcemod')
    Write-Log "Installed Metamod:Source and SourceMod in $Env:GAME_MOD/addons"
    Invoke-Hook "PostInstallSourceMod"
} else {
    Write-Log "Metamod:Source and SourceMod are already installed"
}
