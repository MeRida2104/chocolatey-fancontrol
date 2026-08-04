<#
.SYNOPSIS
    Installs and uninstalls the fancontrol package and asserts the result.
.DESCRIPTION
    Meant to run inside a throwaway VM or Windows Sandbox.

    Phase 1 installs with --ignore-dependencies. That exercises our own
    packaging in isolation, without pulling in the .NET runtime bundle, which
    is a WiX Burn package: it takes the global _MSIExecute mutex and fails with
    exit code 1618 whenever another install is in flight, which a freshly
    booted machine frequently has. Phase 1 also asserts that the shipped build
    is still framework-dependent, so that if upstream ever switches to a
    self-contained build the test tells you to drop the runtime dependency
    from the nuspec instead of silently forcing a needless 57 MB download on
    every user.

    Phase 2 performs the full install including dependencies, which is what a
    real user gets. Since the runtime dependency is required, failures here
    count as failures.
.PARAMETER Source
    Folder containing the built .nupkg and the nuspec.
#>
param(
    [string]$Source = 'C:\pkg',
    [int]$Retries = 3
)

$ErrorActionPreference = 'Stop'
$script:failed = 0
$installDir = 'C:\Program Files (x86)\FanControl'
$exePath    = Join-Path $installDir 'FanControl.exe'
$rcPath     = Join-Path $installDir 'FanControl.runtimeconfig.json'

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

# The mutex is released between transactions, so a single free reading proves
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

function Show-ChocoLogTail {
    $log = 'C:\ProgramData\chocolatey\logs\chocolatey.log'
    if (Test-Path $log) { Note 'Letzte Zeilen aus chocolatey.log:'; Get-Content $log -Tail 25 | ForEach-Object { "    $_" } }
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
Step 'PHASE 1 - Paket isoliert, ohne Abhaengigkeit'
$code = Invoke-Choco @('install', 'fancontrol', "--source=$Source", '--ignore-dependencies', '-y', '--no-progress') -WaitFirst
Assert 'choco install Exitcode 0' ($code -eq 0)
if ($code -ne 0) { Show-ChocoLogTail }

$entry = Get-UninstallEntry
Assert 'Uninstall-Eintrag in der Registry vorhanden' ($null -ne $entry)
if ($entry) { Note "-> $($entry.DisplayName)  |  $($entry.UninstallString)" }
Assert 'FanControl.exe liegt in C:\Program Files (x86)\FanControl' (Test-Path $exePath)

Step 'Regressionswaechter: Runtime-Abhaengigkeit noch korrekt?'
Assert 'FanControl.runtimeconfig.json vorhanden' (Test-Path $rcPath)
if (Test-Path $rcPath) {
    $opts = (Get-Content $rcPath -Raw | ConvertFrom-Json).runtimeOptions
    Note "tfm: $($opts.tfm)"

    # Self-contained Builds fuehren "includedFrameworks", framework-abhaengige "framework(s)".
    Assert 'Build ist framework-abhaengig (nicht self-contained)' ($null -eq $opts.includedFrameworks)
    if ($opts.includedFrameworks) {
        Note 'ACHTUNG: Upstream liefert die Runtime jetzt mit.'
        Note '=> <dependency> aus fancontrol.nuspec ENTFERNEN, sonst zwingst du Nutzern 57 MB .NET auf.'
    }

    $fwList = if ($opts.framework) { @($opts.framework) } else { $opts.frameworks }
    if ($fwList) {
        foreach ($fwItem in $fwList) {
            Note "benoetigt Framework: $($fwItem.name) $($fwItem.version)"
        }

        # Reine Informationsausgabe ohne Assert-Fehler
        $isDesktop = $fwList.name -contains 'Microsoft.WindowsDesktop.App'
        Note "WindowsDesktop Runtime angefordert: $isDesktop"

        $fw = $fwList | Select-Object -First 1

        # Gegenprobe: deckt die im nuspec deklarierte Abhaengigkeit diese Runtime ab?
        $nuspec = Join-Path $Source 'fancontrol.nuspec'
        if (Test-Path $nuspec) {
            $dep = ([xml](Get-Content $nuspec -Raw)).package.metadata.dependencies.dependency |
                   Where-Object { $_.id -match 'desktopruntime' }
            if ($dep) {
                Note "nuspec deklariert: $($dep.id) $($dep.version)"
                $needMajor = ([version]$fw.version).Major
                $depMajor  = if ($dep.id -match 'dotnet-(\d+)\.') { [int]$Matches[1] } else { -1 }
                Assert "nuspec-Abhaengigkeit passt zur benoetigten Runtime (major $needMajor)" ($depMajor -eq $needMajor)
            } else {
                Assert 'nuspec deklariert eine desktopruntime-Abhaengigkeit' $false
            }
        } else { Note "nuspec unter $nuspec nicht gefunden - Gegenprobe uebersprungen." }
    }
}

Step 'PHASE 1 - Deinstallation'
$code = Invoke-Choco @('uninstall', 'fancontrol', '-y', '--no-progress')
Assert 'choco uninstall Exitcode 0' ($code -eq 0)
Assert 'Uninstall-Eintrag entfernt' ($null -eq (Get-UninstallEntry))
Assert 'Programmordner entfernt' (-not (Test-Path $exePath))

# ---------------------------------------------------------------- Phase 2 ---
Step 'PHASE 2 - Vollinstallation inkl. .NET-Runtime (wie beim echten Nutzer)'
$code = Invoke-Choco @('install', 'fancontrol', "--source=$Source;https://community.chocolatey.org/api/v2/", '-y', '--no-progress') -WaitFirst
Assert 'choco install (mit Abhaengigkeit) Exitcode 0' ($code -eq 0)
if ($code -ne 0) {
    Show-ChocoLogTail
    if ($code -eq 1618) { Note 'Exitcode 1618 = ein anderer Installer war aktiv. Sandbox neu starten und erneut testen.' }
}

$installed = choco list --limit-output
Assert '.NET Desktop Runtime mitinstalliert' (@($installed | Where-Object { $_ -match 'desktopruntime' }).Count -gt 0)
Assert 'FanControl.exe nach Vollinstallation vorhanden' (Test-Path $exePath)

Step 'PHASE 2 - Deinstallation'
$code = Invoke-Choco @('uninstall', 'fancontrol', '-y', '--no-progress')
Assert 'choco uninstall Exitcode 0' ($code -eq 0)
Assert 'Uninstall-Eintrag entfernt' ($null -eq (Get-UninstallEntry))
Assert 'Programmordner entfernt' (-not (Test-Path $exePath))

Step 'Ergebnis'
if ($script:failed -eq 0) { Write-Host 'ALLE PRUEFUNGEN BESTANDEN' -ForegroundColor Green }
else { Write-Host "$($script:failed) PRUEFUNG(EN) FEHLGESCHLAGEN" -ForegroundColor Red }
Write-Host "`nFenster bleibt offen. Sandbox schliessen verwirft alles."