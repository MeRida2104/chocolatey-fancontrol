$ErrorActionPreference = 'Stop'

if (-not (Get-OSArchitectureWidth 64) -or $env:chocolateyForceX86 -eq 'true') {
  throw 'FanControl requires a 64-bit installation of Windows.'
}

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  fileType       = 'exe'
  url64bit       = 'https://github.com/Rem0o/FanControl.Releases/releases/download/V279/FanControl_279_net_10_0_Installer.exe'
  checksum64     = 'e80872a5c7d6f5aae13bfc5b50abf0b57c88b658fabe640d16f3ff415499d7c3'
  checksumType64 = 'sha256'

  softwareName   = 'FanControl*'

  # Inno Setup
  silentArgs     = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /FORCECLOSEAPPLICATIONS /LOG=`"$($env:TEMP)\$($env:ChocolateyPackageName).$($env:ChocolateyPackageVersion).InnoInstall.log`""
  validExitCodes = @(0)
}

Install-ChocolateyPackage @packageArgs

# Restart FanControl if chocolateybeforemodify.ps1 stopped it. The age check keeps a
# marker left behind by an uninstall from starting it on some unrelated later install.
$marker = Join-Path $env:TEMP 'fancontrol.wasrunning'
if ((Test-Path $marker) -and (Get-Item $marker).LastWriteTime -gt (Get-Date).AddMinutes(-30)) {
  try {
    # Prefer FanControl's own "start with Windows" task: it runs in the user's session
    # with the user's token, which a direct start from an elevated or SYSTEM choco would not.
    if (Get-ScheduledTask -TaskName 'FanControl' -TaskPath '\' -ErrorAction SilentlyContinue) {
      Write-Host 'Restarting FanControl via its scheduled task.'
      Start-ScheduledTask -TaskName 'FanControl' -TaskPath '\'
      for ($i = 0; $i -lt 10 -and -not (Get-Process -Name 'FanControl' -ErrorAction SilentlyContinue); $i++) {
        Start-Sleep -Seconds 1
      }
    }

    if (-not (Get-Process -Name 'FanControl' -ErrorAction SilentlyContinue)) {
      $exe = Join-Path ${env:ProgramFiles(x86)} 'FanControl\FanControl.exe'
      if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        # Would land in session 0, invisible to the user.
        Write-Warning 'FanControl was running before the upgrade but cannot be restarted from the SYSTEM account. It will start at the next logon.'
      } else {
        Write-Host 'Restarting FanControl.'
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
      }
    }
  } catch {
    Write-Warning "FanControl could not be restarted: $($_.Exception.Message)"
  }
}
Remove-Item $marker -Force -ErrorAction SilentlyContinue
