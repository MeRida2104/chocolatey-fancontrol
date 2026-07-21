<#
.SYNOPSIS
    Installs and uninstalls the fancontrol package and asserts the result.
.DESCRIPTION
    Meant to run inside a throwaway VM or Windows Sandbox. It installs
    Chocolatey if missing, installs the package from a local source, checks
    that the application actually landed on disk and registered an uninstall
    entry, then removes it again and checks that nothing is left behind.

    A freshly booted machine is often still busy with its own installer
    transactions, which makes concurrent installs fail with exit code 1618
    (ERROR_INSTALL_ALREADY_RUNNING). The script therefore waits for the
    Windows Installer mutex to be free and retries.
.PARAMETER Source
    Folder containing the built .nupkg.
#>
param(
    [string]$Source = 'C:\pkg',
    [int]$Retries = 3
)

$ErrorActionPreference = 'Stop'
$script:failed = 0

function Assert($label, [bool]$ok) {
    if ($ok) { Write-Host "  [ OK ] $label" -ForegroundColor Green }
    else     { Write-Host "  [FAIL] $label" -ForegroundColor Red; $script:failed++ }
}
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

# $true while any MSI or WiX Burn bundle holds the global installer mutex.
function Test-InstallerBusy {
    try {
        $m = [Threading.Mutex]::OpenExisting('Global\_MSIExecute')
        $m.Dispose()
        return $true
    }
    catch [Threading.WaitHandleCannotBeOpenedException] { return $false }  # frei
    catch [UnauthorizedAccessException]                 { return $true }   # existiert, kein Zugriff
    catch                                               { return $false }
}

function Wait-InstallerIdle([int]$TimeoutSec = 600) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $waited = $false
    while (Test-InstallerBusy) {
        if ((Get-Date) -ge $deadline) {
            Write-Host "  Windows Installer nach $TimeoutSec s immer noch belegt - fahre trotzdem fort." -ForegroundColor Yellow
            return $false
        }
        if (-not $waited) { Write-Host '  Windows Installer ist belegt, warte...' -ForegroundColor Yellow; $waited = $true }
        Start-Sleep -Seconds 5
    }
    if ($waited) { Write-Host '  Windows Installer ist wieder frei.' -ForegroundColor Yellow }
    return $true
}

function Invoke-ChocoWithRetry([string[]]$ChocoArgs) {
    for ($i = 1; $i -le $Retries; $i++) {
        Wait-InstallerIdle | Out-Null
        & choco @ChocoArgs
        if ($LASTEXITCODE -eq 0) { return 0 }
        if ($i -lt $Retries) {
            Write-Host "`n  Versuch $i fehlgeschlagen (Exitcode $LASTEXITCODE), neuer Versuch in 30 s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
    }
    return $LASTEXITCODE
}

function Get-UninstallEntry {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $roots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'FanControl*' }
}

Step 'Auf ruhenden Windows Installer warten'
Wait-InstallerIdle | Out-Null

Step 'Chocolatey bereitstellen'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
}
choco --version

Step 'Installation'
$code = Invoke-ChocoWithRetry @(
    'install', 'fancontrol'
    "--source=$Source;https://community.chocolatey.org/api/v2/"
    '-y', '--no-progress'
)
Assert 'choco install Exitcode 0' ($code -eq 0)

$entry = Get-UninstallEntry
Assert 'Uninstall-Eintrag in der Registry vorhanden' ($null -ne $entry)
if ($entry) { Write-Host "         -> $($entry.DisplayName) @ $($entry.InstallLocation)" }

$exePath = 'C:\Program Files\FanControl\FanControl.exe'
Assert 'FanControl.exe liegt in C:\Program Files\FanControl' (Test-Path $exePath)

$installed = choco list --limit-output
Assert '.NET Desktop Runtime als Abhaengigkeit mitinstalliert' `
    (@($installed | Where-Object { $_ -match 'desktopruntime' }).Count -gt 0)

# Klaert die offene Frage, ob die Runtime-Abhaengigkeit im nuspec ueberhaupt noetig ist:
# framework-abhaengige Builds nennen "framework(s)", self-contained Builds "includedFrameworks".
Step 'Braucht der Build wirklich eine externe .NET-Runtime?'
$rc = 'C:\Program Files\FanControl\FanControl.runtimeconfig.json'
if (Test-Path $rc) {
    $cfg = Get-Content $rc -Raw | ConvertFrom-Json
    $opts = $cfg.runtimeOptions
    if ($opts.includedFrameworks) {
        Write-Host '  SELF-CONTAINED - die Runtime ist mitgeliefert.' -ForegroundColor Yellow
        Write-Host '  => <dependency> im nuspec ist UEBERFLUESSIG und sollte raus.' -ForegroundColor Yellow
    } else {
        $fw = if ($opts.framework) { $opts.framework } else { $opts.frameworks | Select-Object -First 1 }
        Write-Host "  FRAMEWORK-ABHAENGIG: benoetigt $($fw.name) $($fw.version)" -ForegroundColor Green
        Write-Host '  => <dependency> im nuspec ist korrekt.' -ForegroundColor Green
    }
} else {
    Write-Host '  runtimeconfig.json nicht gefunden - Installation vermutlich fehlgeschlagen.' -ForegroundColor Yellow
}

Step 'Deinstallation'
$code = Invoke-ChocoWithRetry @('uninstall', 'fancontrol', '-y', '--no-progress')
Assert 'choco uninstall Exitcode 0' ($code -eq 0)
Assert 'Uninstall-Eintrag entfernt' ($null -eq (Get-UninstallEntry))
Assert 'Programmordner entfernt' (-not (Test-Path $exePath))

Step 'Ergebnis'
if ($script:failed -eq 0) { Write-Host 'ALLE PRUEFUNGEN BESTANDEN' -ForegroundColor Green }
else { Write-Host "$($script:failed) PRUEFUNG(EN) FEHLGESCHLAGEN" -ForegroundColor Red }
Write-Host "`nFenster bleibt offen. Sandbox schliessen verwirft alles."
