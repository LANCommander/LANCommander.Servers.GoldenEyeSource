#Requires -Modules Hooks
#Requires -Modules Logging
#Requires -Modules OverlayFS

# Installs the server in two parts:
#   1. Source 2007 Dedicated Server (Steam app 310) with SteamCMD. GE:S has only a Windows server,
#      so SteamCMD is forced to the Windows depot.
#   2. The gesource/ mod folder from the official GE:S server archive (GES_ARCHIVE: URL or path).
#      A marker file records the archive's sha256 (or source when no hash is given), and the mod is
#      reinstalled only when that changes.
# Runs after the WINE image's 10-InitializeWinePrefix.ps1.

$serverDir = $Env:SERVER_DIR
$runAs     = "$($Env:UID):$($Env:GID)"
$changed   = $false

New-Item -ItemType Directory -Path $serverDir -Force | Out-Null

try {
    # ---- 1. Source 2007 Dedicated Server ----

    $srcds = Join-Path $serverDir 'srcds.exe'

    if ($Env:STEAM_APP_UPDATE -in @('true', '1')) {
        Invoke-Hook "PreSteamInstallGame"

        Write-Log "Installing/updating Steam app $Env:STEAM_APP_ID (Windows depot) with SteamCMD"

        $steamArgs = @(
            '+@ShutdownOnFailedCommand', '1',
            '+@NoPromptForPassword', '1',
            '+@sSteamCmdForcePlatformType', 'windows',
            '+force_install_dir', $serverDir,
            '+login', $Env:STEAM_USERNAME
        )
        if ($Env:STEAM_USERNAME -ne 'anonymous' -and $Env:STEAM_PASSWORD) { $steamArgs += $Env:STEAM_PASSWORD }

        $steamArgs += '+app_update', $Env:STEAM_APP_ID
        if ($Env:STEAM_BRANCH) {
            $steamArgs += '-beta', $Env:STEAM_BRANCH
            if ($Env:STEAM_BRANCH_PASSWORD) { $steamArgs += '-betapassword', $Env:STEAM_BRANCH_PASSWORD }
        }

        $validate = $Env:STEAM_VALIDATE -in @('true', '1')
        $attempts = [Math]::Max(1, [int]$Env:STEAM_INSTALL_ATTEMPTS)

        for ($attempt = 1; $attempt -le $attempts; $attempt++) {
            $attemptArgs = $steamArgs
            if ($validate -or $attempt -gt 1) { $attemptArgs += 'validate' }

            & /opt/steamcmd/steamcmd.sh @($attemptArgs + '+quit')
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0 -and (Test-Path -Path $srcds)) {
                Write-Log "SteamCMD install completed"
                break
            }

            Write-Log -Level Warning "SteamCMD attempt $attempt of $attempts failed (exit code $exitCode)"
        }

        $changed = $true
        Invoke-Hook "PostSteamInstallGame"
    } else {
        Write-Log "STEAM_APP_UPDATE is disabled. Skipping the Source 2007 Dedicated Server update."
    }

    if (-not (Test-Path -Path $srcds)) {
        throw "srcds.exe not found in $serverDir. The Source 2007 Dedicated Server (app $Env:STEAM_APP_ID) is not installed."
    }

    # ---- 2. GoldenEye: Source mod ----

    Invoke-Hook "PreInstallGoldenEyeSource"

    $modDir   = Join-Path $serverDir 'gesource'
    $marker   = Join-Path $modDir '.lancommander-archive'
    $archive  = $Env:GES_ARCHIVE
    $isUrl    = $archive -match '^(https?|ftp)://'
    $expected = "$Env:GES_ARCHIVE_SHA256".Trim().ToLowerInvariant()
    $wanted   = if ($expected) { $expected } else { $archive }
    $current  = if (Test-Path -Path $marker) { (Get-Content -Path $marker -Raw).Trim() } else { '' }
    $installed = Test-Path -Path (Join-Path $modDir 'gameinfo.txt')

    if ($installed -and ($current -eq $wanted -or -not $archive)) {
        Write-Log "GoldenEye: Source is installed in $modDir"
    } elseif (-not $archive -or (-not $isUrl -and -not (Test-Path -Path $archive))) {
        if ($installed) {
            Write-Log -Level Warning "GES_ARCHIVE ($archive) not found. Keeping the installed GoldenEye: Source."
        } else {
            throw "GoldenEye: Source is not installed and GES_ARCHIVE ($archive) was not found. Download the server archive from https://www.geshl2.com/server-downloads and put it at that path, or set GES_ARCHIVE to a URL."
        }
    } else {
        $work = Join-Path $Env:CONFIG_DIR '.ges-install'
        Remove-Item -Recurse -Force -Path $work -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        try {
            $file = $archive
            if ($isUrl) {
                Write-Log "Downloading GoldenEye: Source server archive from $archive"
                $file = Join-Path $work 'gesource-server.7z'
                curl -fL --retry 3 --output $file $archive
                if ($LASTEXITCODE -ne 0) { throw "Download failed: $archive" }
            }

            if ($expected) {
                Write-Log "Verifying $file"
                $actual = ((sha256sum $file) -split '\s+')[0]
                if ($actual -ne $expected) {
                    throw "sha256 mismatch for ${file}: expected $expected, got $actual. Set GES_ARCHIVE_SHA256 to match, or to empty to skip the check."
                }
            }

            Write-Log "Extracting $file (this takes a few minutes)"
            $extract = Join-Path $work 'extract'
            7z x -y -bd -bso0 "-o$extract" $file
            if ($LASTEXITCODE -ne 0) { throw "Could not extract $file" }

            # The mod folder is gesource/ with a gameinfo.txt, at the archive root or a level or two down
            $source = Get-ChildItem -Path $extract -Filter 'gameinfo.txt' -Recurse -File -Depth 3 |
                Where-Object { $_.Directory.Name -ieq 'gesource' } |
                Select-Object -First 1 -ExpandProperty DirectoryName
            if (-not $source) { throw "No gesource/gameinfo.txt found in $file" }

            Remove-Item -Recurse -Force -Path $modDir -ErrorAction SilentlyContinue
            Move-Item -Path $source -Destination $modDir
            Set-Content -Path $marker -Value $wanted -NoNewline

            $changed = $true
            Write-Log "GoldenEye: Source installed in $modDir"
        } finally {
            Remove-Item -Recurse -Force -Path $work -ErrorAction SilentlyContinue
        }
    }

    Invoke-Hook "PostInstallGoldenEyeSource"
} finally {
    # ---- Ownership and overlay (also after a failed install) ----

    if ($changed -and (id -u) -eq '0') {
        # SteamCMD and the extraction ran as root. Chown Server/ directly, never through Merged/: a chown
        # through the overlay copies every file up into Overlay/.
        chown -R $runAs $serverDir

        # The overlay was mounted before Server/ was filled, and overlayfs doesn't reliably show
        # lower-dir changes made while it is mounted.
        mountpoint -q $Env:SERVER_ROOT
        if ($LASTEXITCODE -eq 0) {
            umount $Env:SERVER_ROOT
            Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue

            try {
                Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $serverDir -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
                Write-Log "OverlayFS remounted"
            } catch {
                Write-Log -Level Error "Failed to remount OverlayFS: $($_.Exception.Message)"
            }
        }
    }
}

Set-Location $Env:SERVER_ROOT
