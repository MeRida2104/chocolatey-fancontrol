<#
.SYNOPSIS
    Installs and uninstalls the fancontrol package and asserts the result.
.DESCRIPTION
    Meant to run inside a throwaway VM or Windows Sandbox. It installs
    Chocolatey if missing, installs the package from a local source, checks
    that the application actually landed on disk and registered an uninstall
    entry, then removes it again and checks that nothing is left behind.
.PARAMETER Source
    Folder containing the built .nupkg.
#>
param([string]$Source = 'C:\pkg')

$ErrorActionPreference = 'Stop'
$script:failed = 0

function Assert($label, [bool]$ok) {
    if ($ok) { Write-Host "  [ OK ] $label" -ForegroundColor Green }
    else     { Write-Host "  [FAIL] $label" -ForegroundColor Red; $script:failed++ }
}
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

function Get-UninstallEntry {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $roots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'FanControl*' }
}

Step 'Chocolatey bereitstellen'
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
}
choco --version

Step 'Installation'
choco install fancontrol --source="'$Source;https://community.chocolatey.org/api/v2/'" -y --no-progress
Assert 'choco install Exitcode 0' ($LASTEXITCODE -eq 0)

$entry = Get-UninstallEntry
Assert 'Uninstall-Eintrag in der Registry vorhanden' ($null -ne $entry)
if ($entry) { Write-Host "         -> $($entry.DisplayName) @ $($entry.InstallLocation)" }

$exe = Get-ChildItem 'C:\Program Files\FanControl\FanControl.exe' -ErrorAction SilentlyContinue
Assert 'FanControl.exe liegt in C:\Program Files\FanControl' ($null -ne $exe)

$installed = choco list --limit-output
Assert '.NET Desktop Runtime als Abhaengigkeit mitinstalliert' `
    (@($installed | Where-Object { $_ -match 'desktopruntime' }).Count -gt 0)

Step 'Deinstallation'
choco uninstall fancontrol -y --no-progress
Assert 'choco uninstall Exitcode 0' ($LASTEXITCODE -eq 0)
Assert 'Uninstall-Eintrag entfernt' ($null -eq (Get-UninstallEntry))
Assert 'Programmordner entfernt' (-not (Test-Path 'C:\Program Files\FanControl\FanControl.exe'))

Step 'Ergebnis'
if ($script:failed -eq 0) { Write-Host 'ALLE PRUEFUNGEN BESTANDEN' -ForegroundColor Green }
else { Write-Host "$($script:failed) PRUEFUNG(EN) FEHLGESCHLAGEN" -ForegroundColor Red }
Write-Host "`nFenster bleibt offen. Sandbox schliessen verwirft alles."
