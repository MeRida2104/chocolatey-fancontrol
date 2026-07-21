<#
.SYNOPSIS
    Installs and uninstalls the fancontrol package and asserts the result.
.DESCRIPTION
    Meant to run inside a throwaway VM or Windows Sandbox.

    The test runs in two phases. Phase 1 installs the package with
    --ignore-dependencies, which exercises our own packaging without dragging
    in the .NET runtime installer. That matters because the runtime ships as a
    WiX Burn bundle: it grabs the global _MSIExecute mutex and fails with exit
    code 1618 whenever anything else is mid-install, which a freshly booted
    machine frequently is. Phase 1 also reads FanControl.runtimeconfig.json to
    determine whether the runtime dependency is genuinely required.

    Phase 2 then does the full install including dependencies, which is what a
    real user gets. It is allowed to fail on 1618 without failing the run, since
    that reflects a third-party package, not ours.
.PARAMETER Source
    Folder containing the built .nupkg.
#>
param(
    [string]$Source = 'C:\pkg',
    [int]$Retries = 3
)

$ErrorActionPreference = 'Stop'
$script:failed = 0
$exePath = 'C:\Program Files\FanControl\FanControl.exe'

function Assert($label, [bool]$ok) {
    if ($ok) { Write-Host "  [ OK ] $label" -ForegroundColor Green }
    else     { Write-Host "  [FAIL] $label" -ForegroundColor Red; $script:failed++ }
}
function Note($t) { Write-Host "  $t" -ForegroundColor Yellow }
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

# $true while any MSI or WiX Burn bundle holds the global installer mutex.
function Test-InstallerBusy {
    try { $m = [Threading.Mutex]::OpenExisting('Global\_MSIExecute'); $m.Dispose(); return $true }
    catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
    catch [UnauthorizedAccessException]                 { return $true }
    catch                                               { return $false }
}

# The mutex is released between transactions, so a single free reading means
# nothing. Require it to stay free for a stretch before calling it idle.
function Wait-InstallerIdle([int]$StableSec = 20, [int]$TimeoutSec = 600) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $freeSince = $null
    while ($true) {
        if (Test-InstallerBusy) {
            if ($freeSince) { Note 'Windows Installer wieder belegt, Zaehler zurueckgesetzt.' }
            $freeSince = $null
        }
        elseif (-not $freeSince) { $freeSince = Get-Date }
        elseif (((Get-Date) - $freeSince).TotalSeconds -ge $StableSec) { return $true }

        if ((Get-Date) -ge $deadline) { Note "Nach $TimeoutSec s nicht ruhig geworden - fahre trotzdem fort."; return $false }
        Start-Sleep -Seconds 3
    }
}

# choco output goes to the host, so only the exit code lands on the pipeline.
function Invoke-Choco([string[]]$ChocoArgs, [switch]$WaitFirst) {
    for ($i = 1; $i -le $Retries; $i++) {
        if ($WaitFirst) { Wait-InstallerIdle | Out-Null }
        & choco @ChocoArgs | Out-Host
        $code = $LASTEXITCODE
        if ($code -eq 0) { return 0 }
        if ($i -lt $Retries) { Note "Versuch $i fehlgeschlagen (Exitcode $code), neuer Versuch in 45 s..."; Start-Sleep 45 }
    }
    return $code
}

function Get-UninstallEntry {
    Get-ItemProperty @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'FanControl*' }
}

Step 'Chocolatey bereitstellen'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
}
choco --version

# ---------------------------------------------------------------- Phase 1 ---
Step 'PHASE 1 - Nur das Paket selbst (ohne Abhaengigkeit)'
$code = Invoke-Choco @('install', 'fancontrol', "--source=$Source", '--ignore-dependencies', '-y', '--no-progress') -WaitFirst
Assert 'choco install Exitcode 0' ($code -eq 0)

$entry = Get-UninstallEntry
Assert 'Uninstall-Eintrag in der Registry vorhanden' ($null -ne $entry)
if ($entry) { Note "-> $($entry.DisplayName)  |  Uninstall: $($entry.UninstallString)" }
Assert 'FanControl.exe liegt in C:\Program Files\FanControl' (Test-Path $exePath)

Step 'Wird die .NET-Runtime ueberhaupt gebraucht?'
$rc = 'C:\Program Files\FanControl\FanControl.runtimeconfig.json'
if (Test-Path $rc) {
    $opts = (Get-Content $rc -Raw | ConvertFrom-Json).runtimeOptions
    if ($opts.includedFrameworks) {
        Note 'SELF-CONTAINED - Runtime ist mitgeliefert.'
        Note '=> <dependency> im nuspec ist UEBERFLUESSIG und sollte raus.'
    } else {
        $fw = if ($opts.framework) { $opts.framework } else { $opts.frameworks | Select-Object -First 1 }
        Note "FRAMEWORK-ABHAENGIG: braucht $($fw.name) $($fw.version)"
        Note '=> <dependency> im nuspec ist korrekt und noetig.'
    }
    Note "(tfm: $($opts.tfm))"
} else {
    Note 'runtimeconfig.json nicht gefunden - Installation offenbar fehlgeschlagen.'
}

Step 'PHASE 1 - Deinstallation'
$code = Invoke-Choco @('uninstall', 'fancontrol', '-y', '--no-progress')
Assert 'choco uninstall Exitcode 0' ($code -eq 0)
Assert 'Uninstall-Eintrag entfernt' ($null -eq (Get-UninstallEntry))
Assert 'Programmordner entfernt' (-not (Test-Path $exePath))

# ---------------------------------------------------------------- Phase 2 ---
Step 'PHASE 2 - Vollinstallation inkl. Abhaengigkeit (wie beim echten Nutzer)'
Note 'Scheitert das hier mit 1618, liegt es am fremden .NET-Paket, nicht an deinem.'
$code = Invoke-Choco @('install', 'fancontrol', "--source=$Source;https://community.chocolatey.org/api/v2/", '-y', '--no-progress') -WaitFirst
if ($code -eq 0) {
    Assert 'Vollinstallation erfolgreich' $true
    $installed = choco list --limit-output
    Assert '.NET Desktop Runtime mitinstalliert' (@($installed | Where-Object { $_ -match 'desktopruntime' }).Count -gt 0)
    Invoke-Choco @('uninstall', 'fancontrol', '-y', '--no-progress') | Out-Null
} else {
    Note "Vollinstallation Exitcode $code - wird NICHT als Fehler deines Pakets gewertet."
    Note 'Letzte Zeilen aus dem Chocolatey-Log:'
    $log = 'C:\ProgramData\chocolatey\logs\chocolatey.log'
    if (Test-Path $log) { Get-Content $log -Tail 25 | ForEach-Object { "    $_" } }
}

Step 'Ergebnis'
if ($script:failed -eq 0) { Write-Host 'ALLE PRUEFUNGEN BESTANDEN' -ForegroundColor Green }
else { Write-Host "$($script:failed) PRUEFUNG(EN) FEHLGESCHLAGEN" -ForegroundColor Red }
Write-Host "`nFenster bleibt offen. Sandbox schliessen verwirft alles."
