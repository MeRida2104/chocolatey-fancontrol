$ErrorActionPreference = 'SilentlyContinue'

# FanControl locks its install directory while running, which makes the Inno Setup
# uninstaller prompt instead of running silently. Shut it down first.
Get-Process -Name 'FanControl' | Stop-Process -Force
Start-Sleep -Seconds 2
