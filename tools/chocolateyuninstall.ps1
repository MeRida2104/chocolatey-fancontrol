$ErrorActionPreference = 'Stop'

# Chocolatey's auto uninstaller only runs if it recorded a registry snapshot at install
# time, and it records none when an upgrade lands on an existing uninstall key. Without
# this script, "choco uninstall" would then leave FanControl installed.
$softwareName = 'FanControl*'
$defaultDir   = Join-Path ${env:ProgramFiles(x86)} 'FanControl'

[array]$key = Get-UninstallRegistryKey -SoftwareName $softwareName

if ($key.Count -eq 1) {
  $installDir = if ($key[0].InstallLocation) { $key[0].InstallLocation.TrimEnd('\') } else { $defaultDir }

  Uninstall-ChocolateyPackage -PackageName $env:ChocolateyPackageName `
    -FileType 'exe' `
    -SilentArgs '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' `
    -File ($key[0].UninstallString -replace '"', '') `
    -ValidExitCodes @(0)
} elseif ($key.Count -eq 0) {
  Write-Warning "$env:ChocolateyPackageName has already been uninstalled by other means."
  $installDir = $defaultDir
} else {
  Write-Warning "$($key.Count) matches found for '$softwareName', not uninstalling to prevent removing the wrong software:"
  $key | ForEach-Object { Write-Warning "- $($_.DisplayName)" }
  return
}

# FanControl registers its "start with Windows" task itself, at runtime. Its uninstaller
# removes the task too, silent mode included; this is a safety net for when the task
# survives anyway. Only touch it if it points at the directory we just removed.
$task = Get-ScheduledTask -TaskName 'FanControl' -TaskPath '\' -ErrorAction SilentlyContinue
if ($task -and -not (Test-Path (Join-Path $installDir 'FanControl.exe'))) {
  $taskDir = ($task.Actions | Select-Object -First 1).WorkingDirectory
  if ($taskDir -and $taskDir.TrimEnd('\') -eq $installDir) {
    Write-Host 'Removing FanControl scheduled task.'
    Unregister-ScheduledTask -TaskName 'FanControl' -TaskPath '\' -Confirm:$false
  }
}
