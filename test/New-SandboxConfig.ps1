<#
.SYNOPSIS
    Generates a Windows Sandbox configuration file for testing this package.
.DESCRIPTION
    Windows Sandbox does not support relative paths in <MappedFolders>, so a
    checked-in .wsb would have to hardcode one machine's checkout location.
    This script writes one for wherever the repository actually sits. The
    generated file is git-ignored.

    vGPU is disabled deliberately: on machines with hybrid graphics it is a
    common cause of the sandbox dropping its connection right after start.
.PARAMETER MemoryInMB
    Memory to hand to the sandbox. Raised to 2048 by Sandbox if set lower.
.PARAMETER Start
    Launch the sandbox once the file is written.
.EXAMPLE
    .\test\New-SandboxConfig.ps1 -Start
#>
[CmdletBinding()]
param(
    [int]$MemoryInMB = 8192,
    [switch]$Start
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$outFile  = Join-Path $repoRoot 'fancontrol-sandbox.wsb'

if (-not (Test-Path (Join-Path $repoRoot 'fancontrol.nuspec'))) {
    throw "fancontrol.nuspec nicht in '$repoRoot' gefunden - liegt das Skript noch im test-Ordner?"
}
if (-not (Get-ChildItem $repoRoot -Filter '*.nupkg' -ErrorAction SilentlyContinue)) {
    Write-Warning "Kein .nupkg in '$repoRoot'. Erst 'choco pack' ausfuehren, sonst findet der Test nichts."
}

$config = @"
<Configuration>
  <vGPU>Disable</vGPU>
  <Networking>Enable</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <MemoryInMB>$MemoryInMB</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$repoRoot</HostFolder>
      <SandboxFolder>C:\pkg</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>cmd.exe /c C:\pkg\test\Run-Test.cmd C:\pkg</Command>
  </LogonCommand>
</Configuration>
"@

Set-Content -Path $outFile -Value $config -Encoding UTF8
[xml](Get-Content $outFile -Raw) | Out-Null   # Wohlgeformtheit sicherstellen

Write-Host "Geschrieben: $outFile" -ForegroundColor Green
Write-Host "  Host-Ordner : $repoRoot -> C:\pkg (schreibgeschuetzt)"
Write-Host "  Speicher    : $MemoryInMB MB"

if ($Start) {
    if (-not (Test-Path "$env:SystemRoot\System32\WindowsSandbox.exe")) {
        throw 'Windows Sandbox ist nicht aktiviert. Siehe README, Abschnitt Testing.'
    }
    Write-Host 'Starte Windows Sandbox...' -ForegroundColor Cyan
    Start-Process $outFile
}
