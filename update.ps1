<#
    update.ps1 - Automatisches Update-Skript fuer das Chocolatey-Paket "fancontrol"
    Nutzt das AU-Modul (Chocolatey Automatic Package Updater).

    VORAUSSETZUNG:
        choco install chocolatey-au
        # oder: Install-Module -Name AU -Scope CurrentUser

    NUTZUNG:
        Datei in dein Paket-Verzeichnis legen (gleiche Ebene wie fancontrol.nuspec),
        dann darin ausfuehren:
            .\update.ps1

        Prueft nur, ob es etwas Neues gibt, ohne zu packen:
            .\update.ps1 -ChecksumFor none -WhatIf

    WAS DAS SKRIPT TUT:
        1. Fragt die GitHub Release API nach dem neuesten FanControl-Release.
        2. Sucht darin das .NET-10-Installer-Asset (wie im aktuellen Paket verwendet).
        3. Vergleicht die Version mit der aktuellen nuspec-Version.
        4. Falls neuer: laedt den Installer, berechnet SHA256, ersetzt
           url64bit/checksum64 in chocolateyinstall.ps1, hebt die nuspec-Version an
           und packt das .nupkg (choco pack). Gepusht wird NICHT automatisch.
#>

# TLS 1.2 erzwingen - Windows PowerShell 5.1 handelt sonst manchmal nicht automatisch
# TLS 1.2 aus, was GitHub-Verbindungen mit "underlying connection was closed" abbrechen laesst.
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

import-module Chocolatey-AU

$releaseApiUrl = 'https://api.github.com/repos/Rem0o/FanControl.Releases/releases/latest'

function global:au_GetLatest {
    $release = Invoke-RestMethod -Uri $releaseApiUrl -UseBasicParsing -Headers @{
        'User-Agent' = 'chocolatey-au-fancontrol'
    }

    # Nur das .NET-10-Installer-Asset beruecksichtigen (matcht die aktuelle Paket-Variante)
    $asset = $release.assets |
        Where-Object { $_.name -match 'net_10_0_Installer\.exe$' } |
        Select-Object -First 1

    if (-not $asset) {
        throw "Kein passendes Installer-Asset im Release '$($release.tag_name)' gefunden."
    }

    # GitHub-Tag ist z.B. "V273" -> Chocolatey-Paketversion "273.0.0"
    $versionNumber = $release.tag_name -replace '^[Vv]', ''

    return @{
        URL64        = $asset.browser_download_url
        Version      = "$versionNumber.0.0"
        ReleaseNotes = "https://github.com/Rem0o/FanControl.Releases/releases/tag/$($release.tag_name)"
    }
}

function global:au_SearchReplace {
    @{
        ".\tools\chocolateyinstall.ps1" = @{
            "(?m)(?<=^\s{0,10}url64bit\s{0,10}=\s{0,10}')[^']+"   = "$($Latest.URL64)"
            "(?m)(?<=^\s{0,10}checksum64\s{0,10}=\s{0,10}')[^']+" = "$($Latest.Checksum64)"
        }
    }
}

update -ChecksumFor 64