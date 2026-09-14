$ErrorActionPreference = 'SilentlyContinue'

# chocolateyinstall.ps1 restarts FanControl after an upgrade if this marker exists.
# Without that, fans stay on BIOS defaults until the next logon.
$marker = Join-Path $env:TEMP 'fancontrol.wasrunning'
Remove-Item $marker -Force

# FanControl locks its install directory while running, which makes the Inno Setup
# uninstaller prompt instead of running silently. Shut it down first.
$running = Get-Process -Name 'FanControl'
if ($running) {
  Set-Content -Path $marker -Value (Get-Date -Format o)
  $running | Stop-Process -Force
  Start-Sleep -Seconds 2
}
